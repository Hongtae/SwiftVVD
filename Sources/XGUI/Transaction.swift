//
//  File: Transaction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
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
            return K.defaultValue
        }
        set { fatalError() }
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
        return try body()
    } catch {
        throw error
    }
}

public func withTransaction<R, V>(_ keyPath: WritableKeyPath<Transaction, V>, _ value: V, _ body: () throws -> R) rethrows -> R {
    var transaction = Transaction()
    transaction[keyPath: keyPath] = value
    return try withTransaction(transaction, body)
}

@usableFromInline
class AnyTransitionBox: @unchecked Sendable {
}

public struct AnyTransition: Sendable {
    fileprivate let box: AnyTransitionBox

    public static var slide: AnyTransition {
        fatalError()
    }
    public static func offset(_ offset: CGSize) -> AnyTransition {
        fatalError()
    }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition {
        fatalError()
    }
    public func combined(with other: AnyTransition) -> AnyTransition {
        fatalError()
    }
    public static func push(from edge: Edge) -> AnyTransition {
        fatalError()
    }
    public static var scale: AnyTransition {
        fatalError()
    }
    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition {
        fatalError()
    }
    public static let opacity: AnyTransition = AnyTransition(box: AnyTransitionBox())

    public static func modifier<E>(active: E, identity: E) -> AnyTransition where E: ViewModifier {
        fatalError()
    }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        fatalError()
    }

    public static let identity: AnyTransition = AnyTransition(box: AnyTransitionBox())

    public static func move(edge: Edge) -> AnyTransition {
        fatalError()
    }

    public func animation(_ animation: Animation?) -> AnyTransition {
        fatalError()
    }
}
