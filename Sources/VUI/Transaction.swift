//
//  File: Transaction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
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
    struct TransactionKeyItem<T: TransactionKey>: PropertyItem {
        static var defaultValue: T.Value {
            T.defaultValue
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
