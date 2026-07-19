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

final class AnimationCompletionObserver: @unchecked Sendable {
    private struct Entry: @unchecked Sendable {
        var criteria: AnimationCompletionCriteria
        var completion: () -> Void
        var order: Int
    }

    // Completion thunks are returned to callers instead of run while this state
    // is locked. Completion callbacks may register nested transactions.
    private struct State: @unchecked Sendable {
        var entries: [Entry] = []
        var activeCriteria = Set<AnimationCompletionCriteria>()
        var bodyFinished = false
        var observedMutation = false
        var registeredAnimation = false
        var completedCriteria = Set<AnimationCompletionCriteria>()
        var nextEntryOrder = 0

        init(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
            entries.append(Entry(criteria: criteria, completion: completion, order: nextEntryOrder))
            nextEntryOrder += 1
        }

        mutating func add(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
            guard !completedCriteria.contains(criteria) else { return }
            entries.append(Entry(criteria: criteria, completion: completion, order: nextEntryOrder))
            nextEntryOrder += 1
        }

        func criteriaForNewAnimation() -> [AnimationCompletionCriteria] {
            orderedCriteria()
                .filter { !completedCriteria.contains($0) }
        }

        func firstCriteriaForNewAnimation() -> AnimationCompletionCriteria? {
            entries.first { !completedCriteria.contains($0.criteria) }?.criteria
        }

        func canStartAnimation(criteria: AnimationCompletionCriteria) -> Bool {
            entries.contains(where: { $0.criteria == criteria }) &&
                !completedCriteria.contains(criteria)
        }

        mutating func listenerDidStart(criteria: AnimationCompletionCriteria) {
            registeredAnimation = true
            activeCriteria.insert(criteria)
        }

        mutating func transactionDidMutate() {
            observedMutation = true
        }

        mutating func bodyDidFinish() -> [() -> Void] {
            bodyFinished = true
            return completionsIfReady(allowNoRegisteredAnimation: false)
        }

        mutating func listenerDidFinish(criteria: AnimationCompletionCriteria) -> [() -> Void] {
            activeCriteria.remove(criteria)
            return completionsIfReady(allowNoRegisteredAnimation: false)
        }

        mutating func noRegisteredAnimationFallbackDidFire(
            usesAnimatedOrdering: Bool
        ) -> [() -> Void] {
            guard !registeredAnimation else {
                return completionsIfReady(allowNoRegisteredAnimation: false)
            }
            if usesAnimatedOrdering {
                return completionsIfReady(allowNoRegisteredAnimation: true)
            }
            return noRegisteredCompletionsIfReady()
        }

        mutating func noRegisteredAnimationFallbackDidFire(
            criteria: AnimationCompletionCriteria
        ) -> [() -> Void] {
            guard bodyFinished,
                  !registeredAnimation,
                  !completedCriteria.contains(criteria),
                  entries.contains(where: { $0.criteria == criteria }) else {
                return []
            }
            completedCriteria.insert(criteria)
            return entries
                .filter { $0.criteria == criteria }
                .map(\.completion)
        }

        mutating func abandonedTransactionDidFinish() -> [() -> Void] {
            guard !observedMutation else {
                return []
            }
            bodyFinished = true
            if registeredAnimation {
                return completionsIfReady(allowNoRegisteredAnimation: false)
            }
            return noRegisteredCompletionsIfReady()
        }

        private mutating func noRegisteredCompletionsIfReady() -> [() -> Void] {
            guard bodyFinished else { return [] }
            let pendingEntries = entries.filter { !completedCriteria.contains($0.criteria) }
            guard let firstCriteria = pendingEntries.first?.criteria else { return [] }
            let hasMultipleCriteria = pendingEntries.contains { $0.criteria != firstCriteria }
            let primary = pendingEntries
                .filter { $0.criteria == firstCriteria }
                .sorted {
                    hasMultipleCriteria ? $0.order > $1.order : $0.order < $1.order
                }
            let remaining = pendingEntries
                .filter { $0.criteria != firstCriteria }
                .sorted { $0.order < $1.order }
            for entry in pendingEntries {
                completedCriteria.insert(entry.criteria)
            }
            return (primary + remaining).map(\.completion)
        }

        private mutating func completionsIfReady(
            allowNoRegisteredAnimation: Bool
        ) -> [() -> Void] {
            guard bodyFinished,
                  (registeredAnimation || allowNoRegisteredAnimation),
                  !orderedCriteria().isEmpty else {
                return []
            }
            var completions: [() -> Void] = []
            for criteria in orderedCriteria() where !completedCriteria.contains(criteria) {
                guard !activeCriteria.contains(criteria) else {
                    continue
                }
                completedCriteria.insert(criteria)
                completions.append(
                    contentsOf: entries
                        .filter { $0.criteria == criteria }
                        .map(\.completion)
                )
            }
            return completions
        }

        private func orderedCriteria() -> [AnimationCompletionCriteria] {
            var criteria: [AnimationCompletionCriteria] = []
            if entries.contains(where: { $0.criteria == .removed }) {
                criteria.append(.removed)
            }
            for entry in entries where entry.criteria != .removed && !criteria.contains(entry.criteria) {
                criteria.append(entry.criteria)
            }
            return criteria
        }
    }

    private let state: Mutex<State>

    // Completion observers are shared by every animatable node touched by one
    // transaction. Criteria have separate token counts so logical completion can
    // finish before removal/presentation completion.
    init(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
        state = Mutex(State(criteria: criteria, completion: completion))
    }

    deinit {
        // Dropped transactions with no observed mutation close their
        // no-registered fallback at the observer lifetime boundary.
        runAnimationCompletionActionsImmediately(abandonedTransactionDidFinish())
    }

    func add(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
        state.withLock { state in
            state.add(criteria: criteria, completion: completion)
        }
    }

    func criteriaForNewAnimation() -> [AnimationCompletionCriteria] {
        state.withLock { state in
            state.criteriaForNewAnimation()
        }
    }

    func firstCriteriaForNewAnimation() -> AnimationCompletionCriteria? {
        state.withLock { state in
            state.firstCriteriaForNewAnimation()
        }
    }

    func canStartAnimation(criteria: AnimationCompletionCriteria) -> Bool {
        state.withLock { state in
            state.canStartAnimation(criteria: criteria)
        }
    }

    func listenerDidStart(criteria: AnimationCompletionCriteria) {
        state.withLock { state in
            state.listenerDidStart(criteria: criteria)
        }
    }

    func transactionDidMutate() {
        state.withLock { state in
            state.transactionDidMutate()
        }
    }

    func bodyDidFinish() -> [() -> Void] {
        state.withLock { state in
            state.bodyDidFinish()
        }
    }

    fileprivate func listenerDidFinish(criteria: AnimationCompletionCriteria) -> [() -> Void] {
        state.withLock { state in
            state.listenerDidFinish(criteria: criteria)
        }
    }

    func noRegisteredAnimationFallbackDidFire(usesAnimatedOrdering: Bool) -> [() -> Void] {
        state.withLock { state in
            state.noRegisteredAnimationFallbackDidFire(usesAnimatedOrdering: usesAnimatedOrdering)
        }
    }

    func noRegisteredAnimationFallbackDidFire(criteria: AnimationCompletionCriteria) -> [() -> Void] {
        state.withLock { state in
            state.noRegisteredAnimationFallbackDidFire(criteria: criteria)
        }
    }

    private func abandonedTransactionDidFinish() -> [() -> Void] {
        state.withLock { state in
            state.abandonedTransactionDidFinish()
        }
    }
}

final class AnimationCompletionToken: @unchecked Sendable {
    private let listener: AnimationListener
    let criteria: AnimationCompletionCriteria
    // Some completion paths can retain the same token in more than one local
    // schedule. The token is the shared single-finish guard for those copies.
    private var finished = false

    init(listener: AnimationListener, criteria: AnimationCompletionCriteria) {
        self.listener = listener
        self.criteria = criteria
    }

    func start() {
        listener.animationWasAdded()
    }

    func finish() -> [() -> Void] {
        guard !finished else { return [] }
        finished = true
        return listener.animationWasRemoved()
    }
}

class AnimationListener: @unchecked Sendable {
    func animationWasAdded() {
    }

    func animationWasRemoved() -> [() -> Void] {
        []
    }

    func finalizeTransaction() -> [() -> Void] {
        []
    }

    func finalizeStandalonePendingTransaction() -> [() -> Void] {
        finalizeTransaction()
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

    override func animationWasRemoved() -> [() -> Void] {
        first.animationWasRemoved() +
            second.animationWasRemoved()
    }
}

private typealias AtomicBox<Value> = Mutex<Value>

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

private let pendingListeners = AtomicBox(PendingListeners())

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
            Transaction.dispatchDuePendingListeners()
        }
    }

    private static func dispatchDuePendingListeners() {
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

        let actions = Update.ensure {
            result.0.flatMap { $0.finalizeStandalonePendingTransaction() }
        }
        enqueueAnimationCompletionActions(actions)

        if let next = result.1 {
            DispatchQueue.main.asyncAfter(deadline: next) {
                Transaction.dispatchDuePendingListeners()
            }
        }
    }

    static func dispatchPendingListeners(
        finalizingStandalonePending: Bool = false
    ) -> [() -> Void] {
        let pending = pendingListeners.withLock { storage in
            let listeners = storage.pending.compactMap(\.listener)
            storage.pending.removeAll()
            storage.next = nil
            return listeners
        }
        let actions = Update.ensure {
            pending.flatMap {
                finalizingStandalonePending
                    ? $0.finalizeStandalonePendingTransaction()
                    : $0.finalizeTransaction()
            }
        }
        return actions
    }
}

final class AllFinishedAnimationListener: AnimationListener, @unchecked Sendable {
    private struct State {
        var activeCount = 0
        var finalized = false
    }

    private let observer: AnimationCompletionObserver
    private let criteria: AnimationCompletionCriteria
    private let state = Mutex(State())

    init(observer: AnimationCompletionObserver, criteria: AnimationCompletionCriteria) {
        self.observer = observer
        self.criteria = criteria
    }

    override func animationWasAdded() {
        state.withLock { state in
            state.activeCount += 1
        }
        observer.listenerDidStart(criteria: criteria)
    }

    override func animationWasRemoved() -> [() -> Void] {
        let isComplete = state.withLock { state in
            guard state.activeCount > 0 else {
                return false
            }
            state.activeCount -= 1
            return state.activeCount == 0
        }
        guard isComplete else { return [] }
        return observer.listenerDidFinish(criteria: criteria)
    }

    override func finalizeTransaction() -> [() -> Void] {
        let shouldFinalize = state.withLock { state in
            guard !state.finalized else {
                return false
            }
            state.finalized = true
            return true
        }
        guard shouldFinalize else { return [] }
        return observer.bodyDidFinish()
    }

    override func finalizeStandalonePendingTransaction() -> [() -> Void] {
        finalizeTransaction() +
            observer.noRegisteredAnimationFallbackDidFire(usesAnimatedOrdering: false)
    }
}

func runAnimationCompletionActionsImmediately(_ actions: [() -> Void]) {
    guard !actions.isEmpty else { return }
    actions.forEach { action in
        _AGGraph.withoutTracking(action)
    }
}

func enqueueAnimationCompletionActions(_ actions: [() -> Void]) {
    guard !actions.isEmpty else { return }
    let wrapped = actions.map { action in
        {
            _AGGraph.withoutTracking(action)
        }
    }
    // Completion actions may trigger arbitrary view mutations. Queue them until
    // the graph leaves the current evaluation/draw pass when possible.
    if let graph = _AGGraph.current {
        graph.actionOutbox.append(contentsOf: wrapped)
    } else {
        wrapped.forEach { Update.enqueueAction($0) }
    }
}

private struct AnimationCompletionObserverBox: @unchecked Sendable {
    var observer: AnimationCompletionObserver
}

func enqueueNoRegisteredAnimationFallback(
    _ observer: AnimationCompletionObserver?,
    animation: Animation? = nil,
    retainUntilFire: Bool = true
) {
    guard let observer else { return }
    let box = AnimationCompletionObserverBox(observer: observer)
    if let animation {
        if box.observer.firstCriteriaForNewAnimation() == .removed,
           let fallbackDelay = animation.box.noRegisteredCompletionDelay() {
            let fire: @Sendable () -> Void = {
                enqueueAnimationCompletionActions(
                    box.observer.noRegisteredAnimationFallbackDidFire(
                        usesAnimatedOrdering: true
                    )
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDelay, execute: fire)
            return
        }
        for criteria in box.observer.criteriaForNewAnimation() {
            guard let fallbackDelay = animation.box.noRegisteredCompletionDelay(for: criteria) else {
                continue
            }
            let fire: @Sendable () -> Void = {
                enqueueAnimationCompletionActions(
                    box.observer.noRegisteredAnimationFallbackDidFire(criteria: criteria)
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDelay, execute: fire)
        }
    } else {
        if retainUntilFire {
            let fire: @Sendable () -> Void = {
                enqueueAnimationCompletionActions(
                    box.observer.noRegisteredAnimationFallbackDidFire(
                        usesAnimatedOrdering: false
                    )
                )
            }
            DispatchQueue.main.async(execute: fire)
        } else {
            let fire: @Sendable () -> Void = { [weak observer] in
                guard let observer else { return }
                enqueueAnimationCompletionActions(
                    observer.noRegisteredAnimationFallbackDidFire(
                        usesAnimatedOrdering: false
                    )
                )
            }
            DispatchQueue.main.async(execute: fire)
        }
    }
}

func finalizeAnimationCompletionObserver(
    _ observer: AnimationCompletionObserver?,
    animation: Animation? = nil,
    bodyDidMutate: Bool = true,
    immediateNoMutationCompletion: Bool = false
) {
    enqueueAnimationCompletionActions(observer?.bodyDidFinish() ?? [])
    guard bodyDidMutate else {
        if immediateNoMutationCompletion {
            enqueueAnimationCompletionActions(
                observer?.noRegisteredAnimationFallbackDidFire(
                    usesAnimatedOrdering: false
                ) ?? []
            )
        } else {
            enqueueNoRegisteredAnimationFallback(
                observer,
                animation: nil,
                retainUntilFire: false
            )
        }
        return
    }
    enqueueNoRegisteredAnimationFallback(observer, animation: animation)
}

func finalizeAnimationCompletions(
    in transaction: Transaction,
    animation: Animation? = nil,
    bodyDidMutate: Bool = true,
    immediateNoMutationCompletion: Bool = false
) {
    let actions = Transaction.dispatchPendingListeners()
    if actions.isEmpty {
        finalizeAnimationCompletionObserver(
            transaction.animationCompletionObserver,
            animation: animation,
            bodyDidMutate: bodyDidMutate,
            immediateNoMutationCompletion: immediateNoMutationCompletion
        )
        return
    }

    enqueueAnimationCompletionActions(actions)
    guard bodyDidMutate else {
        if immediateNoMutationCompletion {
            enqueueAnimationCompletionActions(
                transaction.animationCompletionObserver?.noRegisteredAnimationFallbackDidFire(
                    usesAnimatedOrdering: false
                ) ?? []
            )
        } else {
            enqueueNoRegisteredAnimationFallback(
                transaction.animationCompletionObserver,
                animation: nil,
                retainUntilFire: false
            )
        }
        return
    }
    enqueueNoRegisteredAnimationFallback(
        transaction.animationCompletionObserver,
        animation: animation
    )
}

private struct AnimationTransactionKey: TransactionKey {
    typealias Value = Animation?
    static var defaultValue: Animation? { nil }
}

private struct DisablesAnimationsTransactionKey: TransactionKey {
    typealias Value = Bool
    static var defaultValue: Bool { false }
}

private struct AnimationCompletionObserverTransactionKey: TransactionKey {
    typealias Value = AnimationCompletionObserver?
    static var defaultValue: AnimationCompletionObserver? { nil }

    static func _valuesEqual(_ lhs: AnimationCompletionObserver?, _ rhs: AnimationCompletionObserver?) -> Bool {
        lhs === rhs
    }
}

private struct AnimationListenerTransactionKey: TransactionKey {
    typealias Value = AnimationListener?
    static var defaultValue: AnimationListener? { nil }

    static func _valuesEqual(_ lhs: AnimationListener?, _ rhs: AnimationListener?) -> Bool {
        lhs === rhs
    }
}

private struct AnimationLogicalListenerTransactionKey: TransactionKey {
    typealias Value = AnimationListener?
    static var defaultValue: AnimationListener? { nil }

    static func _valuesEqual(_ lhs: AnimationListener?, _ rhs: AnimationListener?) -> Bool {
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
        plist.nonDefaultValue(forKey: TransactionKeyItem<AnimationTransactionKey>.self) != nil
    }

    public var disablesAnimations: Bool {
        get { self[DisablesAnimationsTransactionKey.self] }
        set { self[DisablesAnimationsTransactionKey.self] = newValue }
    }

    var hasExplicitDisablesAnimationsValue: Bool {
        plist.nonDefaultValue(forKey: TransactionKeyItem<DisablesAnimationsTransactionKey>.self) != nil
    }

    var animationCompletionObserver: AnimationCompletionObserver? {
        get { self[AnimationCompletionObserverTransactionKey.self] }
        set { self[AnimationCompletionObserverTransactionKey.self] = newValue }
    }

    func markAnimationCompletionMutation() {
        animationCompletionObserver?.transactionDidMutate()
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

    mutating func addAnimationListener(
        _ listener: AnimationListener,
        tracksStandalonePending: Bool = true
    ) {
        if tracksStandalonePending {
            Transaction.addPendingListener(listener)
        }
        if let existing = animationListener {
            animationListener = ListenerPair(first: existing, second: listener)
        } else {
            animationListener = listener
        }
    }

    mutating func addAnimationLogicalListener(
        _ listener: AnimationListener,
        tracksStandalonePending: Bool = true
    ) {
        if tracksStandalonePending {
            Transaction.addPendingListener(listener)
        }
        if let existing = animationLogicalListener {
            animationLogicalListener = ListenerPair(first: existing, second: listener)
        } else {
            animationLogicalListener = listener
        }
    }

    public mutating func addAnimationCompletion(
        criteria: AnimationCompletionCriteria = .logicallyComplete,
        _ completion: @escaping () -> Void
    ) {
        addAnimationCompletion(
            criteria: criteria,
            tracksStandalonePending: true,
            completion
        )
    }

    mutating func addAnimationCompletion(
        criteria: AnimationCompletionCriteria = .logicallyComplete,
        tracksStandalonePending: Bool,
        _ completion: @escaping () -> Void
    ) {
        let observer: AnimationCompletionObserver
        if let existingObserver = animationCompletionObserver {
            observer = existingObserver
            observer.add(criteria: criteria, completion: completion)
        } else {
            observer = AnimationCompletionObserver(
                criteria: criteria,
                completion: completion
            )
            animationCompletionObserver = observer
        }
        let listener = AllFinishedAnimationListener(
            observer: observer,
            criteria: criteria
        )
        if criteria == .removed {
            addAnimationListener(
                listener,
                tracksStandalonePending: tracksStandalonePending
            )
        } else {
            addAnimationLogicalListener(
                listener,
                tracksStandalonePending: tracksStandalonePending
            )
        }
    }
}
