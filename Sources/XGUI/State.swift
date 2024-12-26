//
//  File: State.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

class StoredLocation<Value> : AnyLocation<Value>, @unchecked Sendable {
    var _value: Value
    let valueUpdated: (Value)->Void
    init(_ value: Value, onValueUpdated: @escaping (Value)->Void) {
        self._value = value
        self.valueUpdated = onValueUpdated
    }
    override func getValue() -> Value {
        _value
    }
    override func setValue(_ value: Value, transaction: Transaction) {
        self._value = value
        self.valueUpdated(value)
    }
}

class ObservableLocation<Value> : AnyLocation<Value>, @unchecked Sendable {
    init(_ value: Value, onValueUpdated: @escaping (Value)->Void) {
        fatalError()
    }
    override func getValue() -> Value {
        fatalError()
    }
}

@propertyWrapper public struct State<Value> : DynamicProperty {
    @usableFromInline
    var _value: Value

    @usableFromInline
    var _location: AnyLocation<Value>?

    public init(wrappedValue value: Value) {
        _value = value
        _location = StoredLocation(_value, onValueUpdated: { value in
            print("Update value: \(value)")
        })
    }

    @inlinable
    public init(initialValue value: Value) {
        _value = value
    }

    @usableFromInline
    init(wrappedValue thunk: @autoclosure @escaping () -> Value) where Value: AnyObject, Value: Observable {
        _value = thunk()
        _location = ObservableLocation(_value, onValueUpdated: { value in
            fatalError()
        })
    }

    public var wrappedValue: Value {
        get {
            if let _location {
                return _location.getValue()
            }
            return _value
        }
        nonmutating set {
            print("set value: \(newValue)")
            if let _location {
                _location.setValue(newValue, transaction: Transaction())
            }
        }
    }

    public var projectedValue: Binding<Value> {
        if let _location {
            return Binding(location: _location)
        }
        return .constant(_value)
    }

    public static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer,
                                        container: _GraphValue<V>,
                                        fieldOffset: Int,
                                        inputs: inout _GraphInputs) {
        print("\(Self.self)._makeProperty")
        //fatalError()
    }
}

extension State where Value : ExpressibleByNilLiteral {
    @inlinable public init() {
        self.init(wrappedValue: nil)
    }
}

extension State : Sendable where Value : Sendable {
}

