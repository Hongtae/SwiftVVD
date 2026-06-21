//
//  File: Transaction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

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
        var value: UInt32 = 0

        init() {}

        init(value: UInt32) {
            self.value = value
        }
    }

    static var id: ID {
        ThreadStorage.currentID
    }

    static func _core_barrier() {
        ThreadStorage.advanceID()
    }
}

@available(*, unavailable)
extension Transaction: Sendable {
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
    try withTransaction(
        transaction,
        immediateNoMutationCompletion: false,
        body
    )
}

func withTransaction<Result>(
    _ transaction: Transaction,
    immediateNoMutationCompletion: Bool,
    _ body: () throws -> Result
) rethrows -> Result {
    let previous = Transaction.ThreadStorage.currentBox
    if transaction.isEmpty,
       previous?.transaction.hasLocalAnimationCompletionState != true {
        return try body()
    }

    let parentTransaction = previous?.transaction ?? Transaction()
    let scopedTransaction = transaction.scopedTransaction(inheritingFrom: parentTransaction)
    let scopedBox = Transaction.ThreadStorageBox(transaction: scopedTransaction)
    Transaction.ThreadStorage.currentBox = scopedBox
    let result: Result
    do {
        result = try body()
    } catch {
        Transaction.ThreadStorage.currentBox = previous
        finalizeAnimationCompletions(
            in: scopedTransaction,
            animation: scopedTransaction.effectiveAnimation,
            bodyDidMutate: scopedBox.bodyDidMutate,
            immediateNoMutationCompletion: immediateNoMutationCompletion
        )
        throw error
    }
    Transaction.ThreadStorage.currentBox = previous
    finalizeAnimationCompletions(
        in: scopedTransaction,
        animation: scopedTransaction.effectiveAnimation,
        bodyDidMutate: scopedBox.bodyDidMutate,
        immediateNoMutationCompletion: immediateNoMutationCompletion
    )
    return result
}

public func withTransaction<R, V>(_ keyPath: WritableKeyPath<Transaction, V>, _ value: V, _ body: () throws -> R) rethrows -> R {
    var transaction = Transaction()
    transaction[keyPath: keyPath] = value
    return try withTransaction(transaction, body)
}

extension Transaction {
    final class ThreadStorageBox {
        let transaction: Transaction
        var bodyDidMutate = false

        init(transaction: Transaction) {
            self.transaction = transaction
        }
    }

    enum ThreadStorage {
        private static let key = "VUI.Transaction.current"
        private static let idKey = "VUI.Transaction.currentID"

        static var currentBox: ThreadStorageBox? {
            get {
                Thread.current.threadDictionary[key] as? ThreadStorageBox
            }
            set {
                if let newValue {
                    Thread.current.threadDictionary[key] = newValue
                } else {
                    Thread.current.threadDictionary.removeObject(forKey: key)
                }
            }
        }

        static var current: Transaction? {
            get {
                currentBox?.transaction
            }
            set {
                if let newValue {
                    currentBox = ThreadStorageBox(transaction: newValue)
                } else {
                    currentBox = nil
                }
            }
        }

        static var currentID: ID {
            let value = (Thread.current.threadDictionary[idKey] as? NSNumber)?.uint32Value ?? 0
            return ID(value: value)
        }

        static func advanceID() {
            let next = currentID.value &+ 1
            Thread.current.threadDictionary[idKey] = NSNumber(value: next)
        }

        static func markMutation(for transaction: Transaction) {
            transaction.markAnimationCompletionMutation()
            guard let currentBox,
                  currentBox.transaction.animationCompletionObserver === transaction.animationCompletionObserver else {
                return
            }
            currentBox.bodyDidMutate = true
        }
    }

    static var current: Transaction {
        ThreadStorage.current ?? Transaction()
    }

    var hasLocalAnimationCompletionState: Bool {
        animationCompletionObserver != nil ||
        animationListener != nil ||
        animationLogicalListener != nil
    }

    func scopedTransaction(inheritingFrom parent: Transaction) -> Transaction {
        let localCompletionObserver = animationCompletionObserver
        let localAnimationListener = animationListener
        let localAnimationLogicalListener = animationLogicalListener
        var transaction = self
        transaction.plist.merge(parent.plist)
        if transaction.animationCompletionObserver !== localCompletionObserver {
            transaction.animationCompletionObserver = localCompletionObserver
        }
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

private struct ScrollContentOffsetAdjustmentBehaviorKey: TransactionKey {
    static var defaultValue: ScrollContentOffsetAdjustmentBehavior { .automatic }
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

    public var scrollContentOffsetAdjustmentBehavior: ScrollContentOffsetAdjustmentBehavior {
        get { self[ScrollContentOffsetAdjustmentBehaviorKey.self] }
        set { self[ScrollContentOffsetAdjustmentBehaviorKey.self] = newValue }
    }

    var isAnimated: Bool { animation != nil }

    var effectiveAnimation: Animation? {
        animation ?? (tracksVelocity ? .velocityTracking : nil)
    }

    mutating func disableAnimations() { disablesAnimations = true }
}
