//
//  File: Binding.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

@propertyWrapper @dynamicMemberLookup public struct Binding<Value> {
    public var transaction: Transaction
    var location: AnyLocation<Value>
    var _value: Value

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.transaction = Transaction()
        self.location = LocationBox(location: FunctionalLocation(
            get: get,
            set: { value, transaction in
                set(value)
            }))
        self._value = self.location.getValue()
    }

    public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
        self.transaction = Transaction()
        self.location = LocationBox(location: FunctionalLocation(get: get, set: set))
        self._value = self.location.getValue()
    }

    init(location: AnyLocation<Value>) {
        self.transaction = Transaction()
        self.location = location
        self._value = location.getValue()
    }

    public static func constant(_ value: Value) -> Binding<Value> {
        .init(location: LocationBox(location: ConstantLocation(value: value)))
    }

    public var wrappedValue: Value {
        get {
            location.getValue()
        }
        nonmutating set {
            location.setValue(newValue, transaction: transaction)
        }
    }

    public var projectedValue: Binding<Value> {
        self
    }

    @inlinable
    public init(projectedValue: Binding<Value>) {
        self = projectedValue
    }

    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        .constant(_value[keyPath: keyPath])
    }
}

extension Binding: @unchecked Sendable where Value: Sendable {
}

extension Binding: Identifiable where Value: Identifiable {
    public var id: Value.ID {
        _value.id
    }
    public typealias ID = Value.ID
}

extension Binding: Sequence where Value: MutableCollection {
    public typealias Element = Binding<Value.Element>
    public typealias Iterator = IndexingIterator<Binding<Value>>
    public typealias SubSequence = Slice<Binding<Value>>
}

extension Binding: Collection where Value: MutableCollection {
    public typealias Index = Value.Index
    public typealias Indices = Value.Indices
    public var startIndex: Binding<Value>.Index {
        _value.startIndex
    }
    public var endIndex: Binding<Value>.Index {
        _value.endIndex
    }
    public var indices: Value.Indices {
        _value.indices
    }
    public func index(after i: Binding<Value>.Index) -> Binding<Value>.Index {
        _value.index(after: i)
    }
    public func formIndex(after i: inout Binding<Value>.Index) {
        _value.formIndex(after: &i)
    }
    public subscript(position: Binding<Value>.Index) -> Binding<Value>.Element {
        .constant(_value[position])
    }
}

extension Binding: BidirectionalCollection where Value: BidirectionalCollection, Value: MutableCollection {
    public func index(before i: Binding<Value>.Index) -> Binding<Value>.Index {
        _value.index(before: i)
    }

    public func formIndex(before i: inout Binding<Value>.Index) {
        _value.formIndex(before: &i)
    }
}

extension Binding: RandomAccessCollection where Value: MutableCollection, Value: RandomAccessCollection {
}

extension Binding {
    public func transaction(_ transaction: Transaction) -> Binding<Value> {
        var binding = self
        binding.transaction = transaction
        return binding
    }

    public func animation(_ animation: Animation? = .default) -> Binding<Value> {
        transaction(Transaction(animation: animation))
    }
}

extension Binding: DynamicProperty {
    public static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer, container: _GraphValue<V>, fieldOffset: Int, inputs: inout _GraphInputs) {
    }
}
