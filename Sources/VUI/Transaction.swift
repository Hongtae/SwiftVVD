//
//  File: Transaction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

public struct Transaction {
    @usableFromInline
    var plist: PropertyList

    @inlinable public init() {
        plist = PropertyList()
    }

    @inlinable init(plist: PropertyList) {
        self.plist = plist
    }

    public subscript<K>(key: K.Type) -> K.Value where K: TransactionKey {
        get {
            plist.value(forKey: TransactionKeyItem<K>.self)
        }
        set {
            plist.setValue(newValue, forKey: TransactionKeyItem<K>.self)
        }
    }

    @inlinable var isEmpty: Bool {
        plist.isEmpty
    }
}

extension Transaction {
    struct ID: Hashable {
        // Zero is the unallocated sentinel. Ordinary reads allocate a nonzero
        // thread id lazily through ThreadStorage.currentID.
        var value: UInt32 = 0

        init() {}

        init(value: UInt32) {
            self.value = value
        }
    }

    static var id: ID {
        // Reading the id is observable state: it must return a stable nonzero
        // value for the current thread after the first access.
        ThreadStorage.currentID
    }

    static func _core_barrier() {
        // A barrier advances identity without installing or mutating
        // Transaction.current.
        ThreadStorage.advanceID()
    }
}

@available(*, unavailable)
extension Transaction: Sendable {
}

public enum _ScrollViewAnimationMode: Hashable {
    case never
    case discreteChanges
    case always
}

@available(*, unavailable)
extension _ScrollViewAnimationMode: Sendable {
}

public protocol TransactionKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
    static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool
}

extension Transaction {
    struct TransactionKeyItem<T: TransactionKey>: PropertyKey {
        static var defaultValue: T.Value {
            T.defaultValue
        }

        static func valuesEqual(_ a: T.Value, _ b: T.Value) -> Bool {
            T._valuesEqual(a, b)
        }

        var description: String {
            "TransactionKey: \(T.self)"
        }
    }
}

extension TransactionKey {
    public static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool {
        false
    }
}

extension TransactionKey where Self.Value: Equatable {
    public static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool {
        lhs == rhs
    }
}

extension TransactionKey where Self: EnvironmentKey, Self.Value: Equatable {
    public static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool {
        Self._valuesEqual(lhs, rhs)
    }
}

public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
    let previous = Transaction.ThreadStorage.currentBox
    if transaction.isEmpty,
       previous?.transaction.hasLocalAnimationCompletionState != true {
        return try body()
    }

    let parentTransaction = previous?.transaction ?? Transaction()
    let scopedTransaction = transaction.scopedTransaction(inheritingFrom: parentTransaction)
    let scopedBox = Transaction.ThreadStorageBox(transaction: scopedTransaction)
    return try Transaction.ThreadStorage.withValue(scopedBox) {
        try body()
    }
}

public func withTransaction<R, V>(_ keyPath: WritableKeyPath<Transaction, V>, _ value: V, _ body: () throws -> R) rethrows -> R {
    var transaction = Transaction()
    transaction[keyPath: keyPath] = value
    return try withTransaction(transaction, body)
}

extension Transaction {
    final class ThreadStorageBox {
        let transaction: Transaction

        init(transaction: Transaction) {
            self.transaction = transaction
        }
    }

    enum ThreadStorage {
        private static let transaction = _AGThreadLocal<ThreadStorageBox?>(nil)
        private static let idKey = "VUI.Transaction.currentID"

        static var currentBox: ThreadStorageBox? {
            transaction.value
        }

        static var current: Transaction? {
            currentBox?.transaction
        }

        static func withValue<Result>(
            _ box: ThreadStorageBox?,
            _ body: () throws -> Result
        ) rethrows -> Result {
            try transaction.withValue(box, operation: body)
        }

        static var currentID: ID {
            // Reading the current transaction id lazily creates a thread id; the
            // explicit barrier path below always advances to a fresh one.
            if let value = (Thread.current.threadDictionary[idKey] as? NSNumber)?.uint32Value,
               value != 0 {
                return ID(value: value)
            }
            let value = ThreadIDState.next()
            Thread.current.threadDictionary[idKey] = NSNumber(value: value)
            return ID(value: value)
        }

        static func advanceID() {
            let next = ThreadIDState.next()
            Thread.current.threadDictionary[idKey] = NSNumber(value: next)
        }

        #if DEBUG
        static func resetCurrentIDForTesting() {
            Thread.current.threadDictionary.removeObject(forKey: idKey)
        }
        #endif

        private enum ThreadIDState {
            private static let nextID = Atomic<UInt32>(1)

            static func next() -> UInt32 {
                // Transaction ids are per-thread once assigned, but allocation
                // comes from one process-wide monotonically advancing counter.
                return nextID.wrappingAdd(1, ordering: .relaxed).oldValue
            }
        }
    }

    static var current: Transaction {
        ThreadStorage.current ?? Transaction()
    }

    var current: Transaction {
        let threadTransaction = Self.current
        guard !threadTransaction.isEmpty else {
            return self
        }
        guard !isEmpty else {
            return threadTransaction
        }

        var transaction = threadTransaction
        transaction.plist.merge(plist)
        return transaction
    }

    static func withScopedThreadTransaction<Result>(
        _ transaction: Transaction,
        _ body: () throws -> Result
    ) rethrows -> Result {
        let previous = ThreadStorage.currentBox
        let parentTransaction = previous?.transaction ?? Transaction()
        let scopedTransaction = transaction.scopedTransaction(inheritingFrom: parentTransaction)
        let scopedBox = ThreadStorageBox(transaction: scopedTransaction)
        return try ThreadStorage.withValue(scopedBox) {
            try body()
        }
    }

    var hasLocalAnimationCompletionState: Bool {
        animationListener != nil ||
        animationLogicalListener != nil
    }

    func scopedTransaction(inheritingFrom parent: Transaction) -> Transaction {
        // Older runtime baselines install the child transaction
        // storage as-is. Current semantics merge parent keys first, while
        // keeping completion listener identity local to the child scope.
        guard isDeployedOnOrAfter(.v5) else {
            return self
        }

        let localAnimationListener = animationListener
        let localAnimationLogicalListener = animationLogicalListener
        var transaction = self
        // Merge parent values for ordinary transaction keys, then restore local
        // listener identity. Completion ownership is scoped to the transaction
        // that installed it, not to the inherited parent box.
        transaction.plist.merge(parent.plist)
        if transaction.animationListener !== localAnimationListener {
            transaction.animationListener = localAnimationListener
        }
        if transaction.animationLogicalListener !== localAnimationLogicalListener {
            transaction.animationLogicalListener = localAnimationLogicalListener
        }
        return transaction
    }
}

// Gesture / physics animation keys
private struct IsContinuousKey: TransactionKey {
    static let defaultValue: Bool = false
}
private struct FromScrollViewKey: TransactionKey {
    static let defaultValue: Bool = false
}
private struct TracksVelocityKey: TransactionKey {
    static let defaultValue: Bool = false
}

// Frame interval key
private struct AnimationFrameIntervalKey: TransactionKey {
    static let defaultValue: Double? = nil
}

// Animation scheduling reason key
private struct AnimationReasonKey: TransactionKey {
    static let defaultValue: UInt32? = nil
}

// Content transition key
private struct DisablesContentTransitionsKey: TransactionKey {
    static let defaultValue: Bool = false
}

private struct ScrollTargetAnchorKey: TransactionKey {
    static let defaultValue: UnitPoint? = nil
}

private struct ScrollPositionUpdatePreservesVelocityKey: TransactionKey {
    static let defaultValue: Bool = false
}

private struct ScrollToRequiresCompleteVisibilityKey: TransactionKey {
    static let defaultValue: Bool = false
}

private struct ScrollContentOffsetAdjustmentBehaviorKey: TransactionKey {
    static var defaultValue: ScrollContentOffsetAdjustmentBehavior { .automatic }
}

private struct ScrollViewAnimatesKey: TransactionKey {
    nonisolated(unsafe) static let defaultValue: _ScrollViewAnimationMode = .never
}

private struct ScrollInfoKey: TransactionKey {
    static var defaultValue: [UInt32: ScrollViewCommitInfo] { [:] }
}

extension Transaction {
    /// Whether this transaction arose from a continuous (gesture-driven) interaction.
    /// When `true`, the animation system uses velocity data for physics-based animations.
    public var isContinuous: Bool {
        get { self[IsContinuousKey.self] }
        set { self[IsContinuousKey.self] = newValue }
    }

    var hasExplicitIsContinuousValue: Bool {
        plist.nonDefaultValue(forKey: TransactionKeyItem<IsContinuousKey>.self) != nil
    }

    var fromScrollView: Bool {
        get { self[FromScrollViewKey.self] }
        set { self[FromScrollViewKey.self] = newValue }
    }

    /// Whether the animation system should track and apply gesture velocity.
    /// Used by spring animations to match the in-progress gesture velocity.
    public var tracksVelocity: Bool {
        get { self[TracksVelocityKey.self] }
        set { self[TracksVelocityKey.self] = newValue }
    }

    var hasExplicitTracksVelocityValue: Bool {
        plist.nonDefaultValue(forKey: TransactionKeyItem<TracksVelocityKey>.self) != nil
    }

    var animationFrameInterval: Double? {
        get { self[AnimationFrameIntervalKey.self] }
        set { self[AnimationFrameIntervalKey.self] = newValue }
    }

    var animationReason: UInt32? {
        get { self[AnimationReasonKey.self] }
        set { self[AnimationReasonKey.self] = newValue }
    }

    var disablesContentTransitions: Bool {
        get { self[DisablesContentTransitionsKey.self] }
        set { self[DisablesContentTransitionsKey.self] = newValue }
    }

    public var scrollTargetAnchor: UnitPoint? {
        get { self[ScrollTargetAnchorKey.self] }
        set { self[ScrollTargetAnchorKey.self] = newValue }
    }

    public var scrollPositionUpdatePreservesVelocity: Bool {
        get { self[ScrollPositionUpdatePreservesVelocityKey.self] }
        set { self[ScrollPositionUpdatePreservesVelocityKey.self] = newValue }
    }

    var scrollToRequiresCompleteVisibility: Bool {
        get { self[ScrollToRequiresCompleteVisibilityKey.self] }
        set { self[ScrollToRequiresCompleteVisibilityKey.self] = newValue }
    }

    public var scrollContentOffsetAdjustmentBehavior: ScrollContentOffsetAdjustmentBehavior {
        get { self[ScrollContentOffsetAdjustmentBehaviorKey.self] }
        set { self[ScrollContentOffsetAdjustmentBehaviorKey.self] = newValue }
    }

    public var _scrollViewAnimates: _ScrollViewAnimationMode {
        get { self[ScrollViewAnimatesKey.self] }
        set { self[ScrollViewAnimatesKey.self] = newValue }
    }

    subscript(scrollInfo id: UInt32) -> ScrollViewCommitInfo? {
        get {
            self[ScrollInfoKey.self][id]
        }
        set {
            var storage = self[ScrollInfoKey.self]
            storage[id] = newValue
            self[ScrollInfoKey.self] = storage
        }
    }

    var isAnimated: Bool { animation != nil && !disablesAnimations }

    var effectiveAnimation: Animation? {
        animation ?? (tracksVelocity ? .velocityTracking : nil)
    }

    mutating func disableAnimations() { disablesAnimations = true }
}
