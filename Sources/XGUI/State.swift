//
//  File: State.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

@propertyWrapper public struct State<Value>: DynamicProperty {
    @usableFromInline
    var _value: Value

    @usableFromInline
    var _location: AnyLocation<Value>?

    public init(wrappedValue value: Value) {
        _value = value
    }

    @inlinable
    public init(initialValue value: Value) {
        _value = value
    }

    @usableFromInline
    init(wrappedValue thunk: @autoclosure @escaping () -> Value) where Value: AnyObject, Value: Observable {
        _value = thunk()
        _location = LocationBox(location: ObservableLocation(_value, onValueUpdated: { value in
            fatalError()
        }))
    }

    public var wrappedValue: Value {
        get {
            if let _location {
                return _location.getValue()
            }
            return _value
        }
        nonmutating set {
            if let _location {
                _location.setValue(newValue, transaction: Transaction())
            }
        }
    }

    public var projectedValue: Binding<Value> {
        if let _location {
            return Binding(location: _location)
        }
        print("Accessing State's value outside of being installed on a View. This will result in a constant Binding of the initial value and will not update.")
        return .constant(_value)
    }
}

extension State where Value: ExpressibleByNilLiteral {
    @inlinable public init() {
        self.init(wrappedValue: nil)
    }
}

extension State: Sendable where Value: Sendable {
}

extension State: _DynamicPropertyStorageBinding {
    public static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer,
                                        container: _GraphValue<V>,
                                        fieldOffset: Int,
                                        inputs: inout _GraphInputs) {
        assert(buffer.properties.contains { $0.offset == fieldOffset } == false)
        buffer.properties.append(.init(type: self, offset: fieldOffset))
    }

    mutating func bind(in buffer: inout _DynamicPropertyBuffer, fieldOffset: Int, view: ViewContext, tracker: @escaping Tracker) {
        guard MemoryLayout<Self>.size > .zero else { return }
        
        let onValueUpdated: (Value)->Void = { value in
            //print("Update value: \(value)")
            tracker()
        }
        if let location = self._location {
            if let context = buffer.contexts[fieldOffset] {
                assert(context === _location)
                self._value = location.getValue()
            } else {
                buffer.contexts[fieldOffset] = location
            }
        } else {
            var location: AnyLocation<Value>?
            if let context = buffer.contexts[fieldOffset] {
                location = context as? AnyLocation<Value>
                if location == nil {
                    fatalError("Invalid context type")
                }
            }
            if let location {
                self._location = location
                self._value = location.getValue()
            } else {
                let location: AnyLocation<Value>
                if Value.self is Observable.Type {
                    location = LocationBox(location: ObservableLocation(self._value, onValueUpdated: onValueUpdated))
                } else {
                    location = LocationBox(location: StoredLocation(self._value, onValueUpdated: onValueUpdated))
                }
                buffer.contexts[fieldOffset] = location
                self._location = location
            }
        }
        
        // update tracker
        if Value.self is Observable.Type {
            guard let location = self._location as? LocationBox<ObservableLocation<Value>> else {
                fatalError("Invalid context type")
            }
            location.location.valueUpdated = onValueUpdated
        } else {
            guard let location = self._location as? LocationBox<StoredLocation<Value>> else {
                fatalError("Invalid context type")
            }
            location.location.valueUpdated = onValueUpdated
        }
    }
}
