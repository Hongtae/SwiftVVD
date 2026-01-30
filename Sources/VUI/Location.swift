//
//  File: Location.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Observation

protocol _Location {
    associatedtype Value
    func getValue() -> Value
    mutating func setValue(_: Value, transaction: Transaction)
}

@usableFromInline
class AnyLocationBase {
    init() {}

    struct TrackerKey: Hashable {
        let id: ObjectIdentifier
        let offset: Int
    }
    private var notificationTargets: [TrackerKey: () -> Void] = [:]
    func addTracker(key: TrackerKey, tracker: @escaping ()->Void) {
        notificationTargets[key] = tracker
    }
    func removeTracker(key: TrackerKey) {
        notificationTargets.removeValue(forKey: key)
    }
    func notifyChange() {
        notificationTargets.values.map { $0 }
            .forEach { $0() }
    }
}

@usableFromInline
class AnyLocation<Value>: AnyLocationBase, @unchecked Sendable {
    override init() {}

    func getValue() -> Value {
        fatalError()
    }

    func setValue(_: Value, transaction: Transaction) {
        notifyChange()
    }
}

struct FunctionalLocation<Value>: _Location {
    struct Functions {
        var getValue: ()->Value
        var setValue: (Value, Transaction)->Void
    }
    let functions: Functions

    init(get: @escaping ()->Value, set: @escaping (Value, Transaction)->Void) {
        self.functions = Functions(getValue: get, setValue: set)
    }

    func getValue() -> Value {
        functions.getValue()
    }

    func setValue(_ value: Value, transaction: Transaction) {
        functions.setValue(value, transaction)
    }
}

struct ConstantLocation<Value>: _Location {
    let value: Value
    func getValue() -> Value { value }
    func setValue(_: Value, transaction: Transaction) {}
}

struct StoredLocation<Value>: _Location {
    var _value: Value
    var valueUpdated: (Value)->Void
    init(_ value: Value, onValueUpdated: @escaping (Value)->Void) {
        self._value = value
        self.valueUpdated = onValueUpdated
    }
    func getValue() -> Value {
        _value
    }
    mutating func setValue(_ value: Value, transaction: Transaction) {
        self._value = value
        self.valueUpdated(value)
    }
}

struct ObservableLocation<Value>: _Location {
    let _value: Value
    var valueUpdated: (Value)->Void
    init(_ value: Value, onValueUpdated: @escaping (Value)->Void) {
        self._value = value
        self.valueUpdated = onValueUpdated
    }
    func getValue() -> Value {
        _value
    }
    func setValue(_ value: Value, transaction: Transaction) {
        self.valueUpdated(value)
    }
}

class LocationBox<Location: _Location>: AnyLocation<Location.Value>, @unchecked Sendable {
    var location: Location
    var _value: Location.Value
    init(location: Location) {
        self.location = location
        self._value = location.getValue()
    }
    override func getValue() -> Location.Value {
        location.getValue()
    }
    override func setValue(_ value: Location.Value, transaction: Transaction) {
        location.setValue(value, transaction: transaction)
        super.setValue(value, transaction: transaction)
    }
}

protocol AnyLocationBox {
    associatedtype Location: _Location
    var location: Location { get }
}

extension LocationBox: AnyLocationBox {
}
