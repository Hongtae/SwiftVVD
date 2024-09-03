//
//  File: State.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

class StoredLocation<Value> : AnyLocation<Value> {
    var _value: Value
    let valueUpdated: (Value)->Void
    init(_value: Value, onValueUpdated: @escaping (Value)->Void) {
        self._value = _value
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

@propertyWrapper public struct State<Value> : DynamicProperty {
    @usableFromInline
    internal var _value: Value

    @usableFromInline
    internal var _location: AnyLocation<Value>?

    public init(wrappedValue value: Value) {
        _value = value
    }

    //@_alwaysEmitIntoClient
    @inlinable
    public init(initialValue value: Value) {
        _value = value
    }

    public var wrappedValue: Value {
        get { _value }
        nonmutating set {
            // lazy update value
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
        fatalError()
    }
}

extension State where Value : ExpressibleByNilLiteral {
    @inlinable public init() {
        self.init(wrappedValue: nil)
    }
}

protocol _StoredLocationCallback {
    associatedtype Value
    mutating func _setCallback(_: @escaping ()-> Void)
}

extension State : _StoredLocationCallback {
    // setup callback from ViewProxy
    mutating func _setCallback(_ callback: @escaping () -> Void) {
        self._location = StoredLocation<Value>(
            _value: self._value,
            onValueUpdated: { _ in
                callback()
            })
    }
}
