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
    let previous = Transaction.ThreadStorage.current
    let scopedTransaction = transaction.scopedTransaction(inheritingFrom: previous ?? Transaction())
    Transaction.ThreadStorage.current = scopedTransaction
    let result: Result
    do {
        result = try body()
    } catch {
        Transaction.ThreadStorage.current = previous
        throw error
    }
    Transaction.ThreadStorage.current = previous
    finalizeAnimationCompletionObserver(
        scopedTransaction.animationCompletionObserver,
        animation: scopedTransaction.effectiveAnimation
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

        init(transaction: Transaction) {
            self.transaction = transaction
        }
    }

    enum ThreadStorage {
        private static let key = "VUI.Transaction.current"

        static var current: Transaction? {
            get {
                (Thread.current.threadDictionary[key] as? ThreadStorageBox)?.transaction
            }
            set {
                if let newValue {
                    Thread.current.threadDictionary[key] = ThreadStorageBox(transaction: newValue)
                } else {
                    Thread.current.threadDictionary.removeObject(forKey: key)
                }
            }
        }
    }

    static var current: Transaction {
        ThreadStorage.current ?? Transaction()
    }

    func scopedTransaction(inheritingFrom parent: Transaction) -> Transaction {
        var transaction = self
        if !hasExplicitAnimationValue,
           parent.hasExplicitAnimationValue {
            transaction.animation = parent.animation
        }
        if !hasExplicitDisablesAnimationsValue,
           parent.hasExplicitDisablesAnimationsValue {
            transaction.disablesAnimations = parent.disablesAnimations
        }
        if !hasExplicitIsContinuousValue,
           parent.hasExplicitIsContinuousValue {
            transaction.isContinuous = parent.isContinuous
        }
        if !hasExplicitTracksVelocityValue,
           parent.hasExplicitTracksVelocityValue {
            transaction.tracksVelocity = parent.tracksVelocity
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

// Content transition key
private struct DisablesContentTransitionsKey: TransactionKey {
    static let defaultValue: Bool = false
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

    var disablesContentTransitions: Bool {
        get { self[DisablesContentTransitionsKey.self] }
        set { self[DisablesContentTransitionsKey.self] = newValue }
    }

    var isAnimated: Bool { animation != nil }

    var effectiveAnimation: Animation? {
        animation ?? (tracksVelocity ? .velocityTracking : nil)
    }

    mutating func disableAnimations() { disablesAnimations = true }
}
