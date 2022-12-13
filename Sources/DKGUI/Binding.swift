//
//  File: Binding.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

@propertyWrapper @dynamicMemberLookup public struct Binding<Value> {
    public var transaction: Transaction
    var value: Value

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.transaction = Transaction()
        self.value = get()
        set(value)
    }

    public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
        self.transaction = Transaction()
        self.value = get()
        set(value, self.transaction)
    }

    public static func constant(_ value: Value) -> Binding<Value> {
        fatalError()
    }

    public var wrappedValue: Value {
        get { value }
        nonmutating set { fatalError() }
    }

    public var projectedValue: Binding<Value> {
        self
    }

    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        fatalError()
    }
}
