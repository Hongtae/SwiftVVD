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
    do {
        return try Transaction.$_current.withValue(.init(transaction: transaction)) {
            try body()
        }
    } catch {
        throw error
    }
}

public func withTransaction<R, V>(_ keyPath: WritableKeyPath<Transaction, V>, _ value: V, _ body: () throws -> R) rethrows -> R {
    var transaction = Transaction()
    transaction[keyPath: keyPath] = value
    return try withTransaction(transaction, body)
}

extension Transaction {
    struct _Local: @unchecked Sendable {
        let transaction: Transaction
    }
    @TaskLocal
    static var _current: _Local?
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

    /// Whether the animation system should track and apply gesture velocity.
    /// Used by spring animations to match the in-progress gesture velocity.
    public var tracksVelocity: Bool {
        get { self[TracksVelocityKey.self] }
        set { self[TracksVelocityKey.self] = newValue }
    }

    /// Override the default display-link frame interval for this transaction's animations.
    /// `nil` means use the default frame rate.
    public var animationFrameInterval: Double? {
        get { self[AnimationFrameIntervalKey.self] }
        set { self[AnimationFrameIntervalKey.self] = newValue }
    }

    /// When `true`, content transitions (e.g. `.contentTransition(.numericText())`)
    /// are suppressed and views update without their transition animation.
    public var disablesContentTransitions: Bool {
        get { self[DisablesContentTransitionsKey.self] }
        set { self[DisablesContentTransitionsKey.self] = newValue }
    }

    /// `true` when an animation is attached to this transaction and animations are not disabled.
    public var isAnimated: Bool { animation != nil && !disablesAnimations }

    /// The animation to use, taking `disablesAnimations` into account.
    /// Returns `nil` when animations are disabled even if `animation` is set.
    public var effectiveAnimation: Animation? { disablesAnimations ? nil : animation }

    /// Disables all animations for this transaction.
    public mutating func disableAnimations() { disablesAnimations = true }
}
