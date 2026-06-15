//
//  File: Binding.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

@propertyWrapper @dynamicMemberLookup public struct Binding<Value> {
    public var transaction: Transaction
    var location: AnyLocation<Value>
    var _value: Value
    var passesLocalTransactionToSetter: Bool
    var finalizesLocalTransactionAfterSetter: Bool

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.transaction = Transaction()
        self.passesLocalTransactionToSetter = false
        self.finalizesLocalTransactionAfterSetter = true
        self.location = LocationBox(location: FunctionalLocation(
            get: get,
            set: { value, transaction in
                set(value)
            },
            marksMutation: false
        ))
        self._value = self.location.getValue()
    }

    public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
        self.transaction = Transaction()
        self.passesLocalTransactionToSetter = true
        self.finalizesLocalTransactionAfterSetter = true
        self.location = LocationBox(location: FunctionalLocation(
            get: get,
            set: set,
            marksMutation: false
        ))
        self._value = self.location.getValue()
    }

    init(
        get: @escaping () -> Value,
        set: @escaping (Value, Transaction) -> Void,
        passesLocalTransactionToSetter: Bool,
        finalizesLocalTransactionAfterSetter: Bool
    ) {
        self.transaction = Transaction()
        self.passesLocalTransactionToSetter = passesLocalTransactionToSetter
        self.finalizesLocalTransactionAfterSetter = finalizesLocalTransactionAfterSetter
        self.location = LocationBox(location: FunctionalLocation(
            get: get,
            set: set,
            marksMutation: false
        ))
        self._value = self.location.getValue()
    }

    init(location: AnyLocation<Value>) {
        self.transaction = Transaction()
        self.location = location
        self._value = location.getValue()
        self.passesLocalTransactionToSetter = false
        self.finalizesLocalTransactionAfterSetter = false
    }

    public static func constant(_ value: Value) -> Binding<Value> {
        .init(location: LocationBox(location: ConstantLocation(value: value)))
    }

    public var wrappedValue: Value {
        get {
            location.getValue()
        }
        nonmutating set {
            let shouldFinalizeLocalTransactionAfterSetter =
                finalizesLocalTransactionAfterSetter
                && !transaction.isEmpty
                && (passesLocalTransactionToSetter || Transaction.current.isEmpty)
            let setterTransaction = passesLocalTransactionToSetter ? transaction : resolvedTransaction
            location.setValue(newValue, transaction: setterTransaction)
            if shouldFinalizeLocalTransactionAfterSetter {
                finalizeAnimationCompletionObserver(transaction.animationCompletionObserver)
            }
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
        let location = self.location
        let getter = {
            location.getValue()[keyPath: keyPath]
        }
        let setter = { value, transaction in
            var enclosingValue = location.getValue()
            enclosingValue[keyPath: keyPath] = value
            location.setValue(enclosingValue, transaction: transaction)
        }
        return Binding<Subject>(
            get: getter,
            set: setter,
            passesLocalTransactionToSetter: false,
            finalizesLocalTransactionAfterSetter: false
        )
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
        let location = self.location
        let getter = {
            location.getValue()[position]
        }
        let setter = { newValue in
            var enclosingValue = location.getValue()
            enclosingValue[position] = newValue
            location.setValue(enclosingValue, transaction: resolvedTransaction)
        }
        return Binding<Value>.Element(get: getter, set: setter)
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
    private var resolvedTransaction: Transaction {
        let current = Transaction.current
        guard !transaction.isEmpty else {
            return current
        }
        guard current.isEmpty else {
            finalizeAnimationCompletionObserver(transaction.animationCompletionObserver)
            return current
        }
        return transaction
    }

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
        assert(buffer.properties.contains { $0.offset == fieldOffset } == false)
        buffer.properties.append(.init(type: self, offset: fieldOffset))
    }
}
