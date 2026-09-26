//
//  File: AnimationCompletion.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

public struct AnimationCompletionCriteria: Hashable, Sendable {
    private let storage: UInt8

    private init(storage: UInt8) {
        self.storage = storage
    }

    public static let logicallyComplete = AnimationCompletionCriteria(storage: 0)
    public static let removed = AnimationCompletionCriteria(storage: 1)
}

class AnimationListener: @unchecked Sendable {
    func animationWasAdded() {
    }

    func animationWasRemoved() {
    }

    func finalizeTransaction() {
    }

    // Host-owned operations use a separate count so they can wait until every
    // graph-owned animation has drained before releasing their own token.
    func hostedAnimationWasAdded() {
        animationWasAdded()
    }

    func hostedAnimationWasRemoved() {
        animationWasRemoved()
    }

    var hasOnlyHostedAnimations: Bool {
        true
    }

    func observeHostedAnimationReadiness(_ observer: @escaping () -> Void) {
        observer()
    }
}

final class ListenerPair: AnimationListener, @unchecked Sendable {
    private let first: AnimationListener
    private let second: AnimationListener

    init(first: AnimationListener, second: AnimationListener) {
        self.first = first
        self.second = second
    }

    override func animationWasAdded() {
        first.animationWasAdded()
        second.animationWasAdded()
    }

    override func animationWasRemoved() {
        first.animationWasRemoved()
        second.animationWasRemoved()
    }

    override func hostedAnimationWasAdded() {
        first.hostedAnimationWasAdded()
        second.hostedAnimationWasAdded()
    }

    override func hostedAnimationWasRemoved() {
        first.hostedAnimationWasRemoved()
        second.hostedAnimationWasRemoved()
    }

    override var hasOnlyHostedAnimations: Bool {
        first.hasOnlyHostedAnimations && second.hasOnlyHostedAnimations
    }

    override func observeHostedAnimationReadiness(
        _ observer: @escaping () -> Void
    ) {
        first.observeHostedAnimationReadiness(observer)
        second.observeHostedAnimationReadiness(observer)
    }
}

extension Transaction {
    struct AnimationCompletionInfo {
        var completedCount: Int
    }
}

final class AllFinishedListener: AnimationListener, @unchecked Sendable {
    private let callback: (Transaction.AnimationCompletionInfo) -> Void
    private var activeCount = 0
    private var totalCount = 0
    private var hostedCount = 0
    private var finalized = false
    private var hostedReadinessObservers: [() -> Void] = []

    init(callback: @escaping (Transaction.AnimationCompletionInfo) -> Void) {
        self.callback = callback
    }

    deinit {
        finishIfPossible()
    }

    override func animationWasAdded() {
        activeCount += 1
        totalCount += 1
    }

    override func animationWasRemoved() {
        activeCount -= 1
        notifyHostedReadinessIfNeeded()
        finishIfPossible()
    }

    override func hostedAnimationWasAdded() {
        activeCount += 1
        totalCount += 1
        hostedCount += 1
    }

    override func hostedAnimationWasRemoved() {
        activeCount -= 1
        hostedCount -= 1
        notifyHostedReadinessIfNeeded()
        finishIfPossible()
    }

    override var hasOnlyHostedAnimations: Bool {
        activeCount == hostedCount
    }

    override func observeHostedAnimationReadiness(
        _ observer: @escaping () -> Void
    ) {
        hostedReadinessObservers.append(observer)
        if hasOnlyHostedAnimations {
            observer()
        }
    }

    override func finalizeTransaction() {
        finishIfPossible()
    }

    private func finishIfPossible() {
        guard activeCount == 0, !finalized else {
            return
        }
        finalized = true
        callback(Transaction.AnimationCompletionInfo(completedCount: totalCount))
    }

    private func notifyHostedReadinessIfNeeded() {
        guard hasOnlyHostedAnimations else { return }
        for observer in hostedReadinessObservers {
            observer()
        }
    }
}

/// A host-adapter token for platform operations that begin and finish outside
/// the attribute animator. It forwards the same listener lifecycle used by
/// graph-owned animations.
final class AnimationCompletionToken: @unchecked Sendable {
    private let listener: AnimationListener
    private let usesHostedLifecycle: Bool
    private var finished = false

    init(
        listener: AnimationListener,
        usesHostedLifecycle: Bool = false
    ) {
        self.listener = listener
        self.usesHostedLifecycle = usesHostedLifecycle
    }

    func start() {
        if usesHostedLifecycle {
            listener.hostedAnimationWasAdded()
        } else {
            listener.animationWasAdded()
        }
    }

    func finish() {
        guard !finished else {
            return
        }
        finished = true
        if usesHostedLifecycle {
            listener.hostedAnimationWasRemoved()
        } else {
            listener.animationWasRemoved()
        }
    }

    var hasOnlyHostedAnimations: Bool {
        listener.hasOnlyHostedAnimations
    }

    func observeHostedAnimationReadiness(
        _ observer: @escaping () -> Void
    ) {
        listener.observeHostedAnimationReadiness(observer)
    }
}

private struct PendingListeners {
    struct WeakListener {
        weak var listener: AnimationListener?
        var time: DispatchTime

        init(_ listener: AnimationListener, time: DispatchTime) {
            self.listener = listener
            self.time = time
        }
    }

    var pending: [WeakListener] = []
    var next: DispatchTime?
}

private let pendingListeners = Mutex(PendingListeners())

extension Transaction {
    static func addPendingListener(_ listener: AnimationListener) {
        let time = DispatchTime.now() + .milliseconds(10)
        let next = pendingListeners.withLock { storage -> DispatchTime? in
            storage.pending.append(
                PendingListeners.WeakListener(listener, time: time)
            )
            if let next = storage.next, next <= time {
                return nil
            }
            storage.next = time
            return time
        }

        guard let next else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: next) {
            Transaction.dispatchPending()
        }
    }

    private static func dispatchPending() {
        let now = DispatchTime.now()
        let result = pendingListeners.withLock { storage in
            var due: [AnimationListener] = []
            var future: [PendingListeners.WeakListener] = []
            future.reserveCapacity(storage.pending.count)

            for weakListener in storage.pending {
                if weakListener.time <= now {
                    if let listener = weakListener.listener {
                        due.append(listener)
                    }
                } else if weakListener.listener != nil {
                    future.append(weakListener)
                }
            }

            storage.pending = future
            storage.next = future.map(\.time).min()
            return (due, storage.next)
        }

        Update.ensure {
            result.0.forEach { $0.finalizeTransaction() }
        }

        if let next = result.1 {
            DispatchQueue.main.asyncAfter(deadline: next) {
                Transaction.dispatchPending()
            }
        }
    }

    // Deterministic test hook for the otherwise dispatch-time-driven weak
    // listener queue. Production code always uses dispatchPending().
    static func dispatchPendingListeners() {
        let listeners = pendingListeners.withLock { storage in
            let listeners = storage.pending.compactMap(\.listener)
            storage.pending.removeAll()
            storage.next = nil
            return listeners
        }
        Update.ensure {
            listeners.forEach { $0.finalizeTransaction() }
        }
    }
}

private struct AnimationTransactionKey: TransactionKey {
    typealias Value = Animation?
    static var defaultValue: Animation? { nil }
}

private struct DisablesAnimationsTransactionKey: TransactionKey {
    typealias Value = Bool
    static var defaultValue: Bool { false }
}

private struct AnimationListenerTransactionKey: TransactionKey {
    typealias Value = AnimationListener?
    static var defaultValue: AnimationListener? { nil }

    static func _valuesEqual(
        _ lhs: AnimationListener?,
        _ rhs: AnimationListener?
    ) -> Bool {
        lhs === rhs
    }
}

private struct AnimationLogicalListenerTransactionKey: TransactionKey {
    typealias Value = AnimationListener?
    static var defaultValue: AnimationListener? { nil }

    static func _valuesEqual(
        _ lhs: AnimationListener?,
        _ rhs: AnimationListener?
    ) -> Bool {
        lhs === rhs
    }
}

extension Transaction {
    public init(animation: Animation?) {
        plist = PropertyList()
        self.animation = animation
    }

    public var animation: Animation? {
        get { self[AnimationTransactionKey.self] }
        set { self[AnimationTransactionKey.self] = newValue }
    }

    var hasExplicitAnimationValue: Bool {
        plist.nonDefaultValue(
            forKey: TransactionKeyItem<AnimationTransactionKey>.self
        ) != nil
    }

    public var disablesAnimations: Bool {
        get { self[DisablesAnimationsTransactionKey.self] }
        set { self[DisablesAnimationsTransactionKey.self] = newValue }
    }

    var hasExplicitDisablesAnimationsValue: Bool {
        plist.nonDefaultValue(
            forKey: TransactionKeyItem<DisablesAnimationsTransactionKey>.self
        ) != nil
    }

    var animationListener: AnimationListener? {
        get { self[AnimationListenerTransactionKey.self] }
        set { self[AnimationListenerTransactionKey.self] = newValue }
    }

    var animationLogicalListener: AnimationListener? {
        get { self[AnimationLogicalListenerTransactionKey.self] }
        set { self[AnimationLogicalListenerTransactionKey.self] = newValue }
    }

    var combinedAnimationListener: AnimationListener? {
        switch (animationListener, animationLogicalListener) {
        case let (regular?, logical?):
            return ListenerPair(first: regular, second: logical)
        case let (regular?, nil):
            return regular
        case let (nil, logical?):
            return logical
        case (nil, nil):
            return nil
        }
    }

    var animationIgnoringTransitionPhase: Animation? {
        guard disablesAnimations else {
            return animation
        }
        var result: Animation?
        plist.forEachValue(
            forKey: TransactionKeyItem<AnimationTransactionKey>.self
        ) { value, stop in
            guard let value else {
                return
            }
            result = value
            stop = true
        }
        return result
    }

    mutating func addAnimationListener(_ listener: AnimationListener) {
        Transaction.addPendingListener(listener)
        if let existing = animationListener {
            animationListener = ListenerPair(first: existing, second: listener)
        } else {
            animationListener = listener
        }
    }

    mutating func addAnimationLogicalListener(_ listener: AnimationListener) {
        Transaction.addPendingListener(listener)
        if let existing = animationLogicalListener {
            animationLogicalListener = ListenerPair(
                first: existing,
                second: listener
            )
        } else {
            animationLogicalListener = listener
        }
    }

    public mutating func addAnimationCompletion(
        criteria: AnimationCompletionCriteria = .logicallyComplete,
        _ completion: @escaping () -> Void
    ) {
        let reason: CustomEventTrace.ActionEventType.Reason =
            criteria == .removed
            ? .animationRemoved
            : .animationLogicallyCompleted
        let listener = AllFinishedListener { _ in
            Update.enqueueAction(reason: reason, completion)
        }
        if criteria == .removed {
            addAnimationListener(listener)
        } else {
            addAnimationLogicalListener(listener)
        }
    }
}
