//
//  File: Binding.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private final class BindingLocationTracker<Value> {
    private final class Identity {
    }

    private let identity: Identity
    private let location: AnyLocation<Value>
    private let key: AnyLocationBase.TrackerKey

    init(
        location: AnyLocation<Value>,
        graph: _AGGraph,
        signal: Attribute<Void>
    ) {
        self.location = location
        let identity = Identity()
        self.identity = identity
        key = AnyLocationBase.TrackerKey(
            id: ObjectIdentifier(identity),
            offset: 0
        )
        let inbox = graph.inbox
        let graphReference = UnsafeSendableBox(_AGGraphWeakRef(graph))
        let weakSignal = signal.asWeak().base
        location.addTracker(key: key) { [weak inbox] in
            inbox?.enqueue {
                guard let graph = graphReference.value.graph,
                      _AGGraph.current === graph,
                      weakSignal.isValid(in: graph) else {
                    return
                }
                graph.invalidateAttribute(weakSignal.toStrong())
            }
        }
    }

    deinit {
        location.removeTracker(key: key)
    }
}

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
            }
        ))
        self._value = self.location.getValue()
    }

    public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
        self.transaction = Transaction()
        self.location = LocationBox(location: FunctionalLocation(
            get: get,
            set: set
        ))
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
        projecting(keyPath)
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
            location.setValue(enclosingValue, transaction: transaction)
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
    func projecting<P>(_ projection: P) -> Binding<P.Projected>
        where P: Projection, P.Base == Value
    {
        var binding = Binding<P.Projected>(
            location: location.projecting(projection)
        )
        binding.transaction = transaction
        return binding
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

extension Binding {
    public init<V>(_ base: Binding<V>) where Value == V? {
        self = base.projecting(BindingOperations.ToOptional<V>())
    }

    public init?(_ base: Binding<Value?>) {
        guard base.wrappedValue != nil else { return nil }
        self = base.projecting(BindingOperations.ForceUnwrapping<Value>())
    }

    public init<V>(_ base: Binding<V>) where Value == AnyHashable, V: Hashable {
        self = base.projecting(BindingOperations.ToAnyHashable<V>())
    }
}

extension Binding: DynamicProperty {
    public static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "Binding._makeProperty called outside an active _AGGraph "
                    + "context."
            )
        }

        let wiringSubgraph = AGSubgraph.current
        let signal: Attribute<Void> = AGSubgraph.withCurrent(wiringSubgraph) {
            graph.makeInput(value: ())
        }
        let tracker = MutableBox<BindingLocationTracker<Value>?>(nil)

        assert(!buffer.properties.contains { $0.offset == fieldOffset })
        buffer.properties.append(.init(type: self, offset: fieldOffset))
        buffer.contexts[fieldOffset] = {
            (pointer: UnsafeMutableRawPointer) in
            var binding = pointer
                .assumingMemoryBound(to: Binding<Value>.self)
                .pointee
            if tracker.value == nil {
                tracker.value = BindingLocationTracker(
                    location: binding.location,
                    graph: graph,
                    signal: signal
                )
            }
            _ = signal.value
            binding._value = binding.location.update().0
            pointer.assumingMemoryBound(to: Binding<Value>.self).pointee =
                binding
        }
    }
}
