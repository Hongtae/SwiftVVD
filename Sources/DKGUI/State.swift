//
//  File: State.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

@propertyWrapper public struct State<Value>: DynamicProperty {
    var value: Value

    public init(wrappedValue value: Value) {
        self.value = value
    }

    public init(initialValue value: Value) {
        self.value = value
    }

    public var wrappedValue: Value {
        get { value }
        nonmutating set { fatalError() }
    }

    public var projectedValue: Binding<Value> {
        return Binding(get: { return self.wrappedValue },
                       set: { newValue in self.wrappedValue = newValue })
    }
}
