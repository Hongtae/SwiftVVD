//
//  File: Location.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

protocol _Location {
    associatedtype Value
    func getValue() -> Value
    func setValue(_: Value, transaction: Transaction)
}

@usableFromInline
class AnyLocationBase {
    init() {}
}

@usableFromInline
class AnyLocation<Value>: AnyLocationBase, @unchecked Sendable {
    override init() {}

    func getValue() -> Value {
        fatalError()
    }

    func setValue(_: Value, transaction: Transaction) {
        fatalError()
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
    }
}
