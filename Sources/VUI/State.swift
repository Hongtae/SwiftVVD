//
//  File: State.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
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

extension State {
    public static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeProperty called outside an active AttributeGraph context.")
        }

        let inbox = graph.inbox
        // Capture the active AGSubgraph at wiring time so the state node is registered
        // to the correct subgraph (e.g. the one created by Optional._makeView).
        let wiringSubgraph = AGSubgraph.current
        // Shared across all body evaluations for this @State field.
        let mountedLocation = MutableBox<AnyLocation<Value>?>(nil)

        assert(buffer.properties.contains { $0.offset == fieldOffset } == false)
        buffer.properties.append(.init(type: Self.self, offset: fieldOffset))
        buffer.contexts[fieldOffset] = { (ptr: UnsafeMutableRawPointer) in
            guard let graph = AttributeGraph.current else {
                fatalError("\(Self.self)._makeProperty context closure called outside an active AttributeGraph context.")
            }
            let currentState = ptr.assumingMemoryBound(to: State<Value>.self).pointee

            if let location = mountedLocation.value {
                // Already mounted: restore the location on this view copy.
                var s = currentState
                s._location = location
                ptr.assumingMemoryBound(to: State<Value>.self).pointee = s
                return
            }

            // First body evaluation: create the AG input node.
            // Register it in the wiring-time subgraph so it is cleaned up correctly.
            let initialValue = currentState._value
            // Synchronous cache so wrappedValue.get works outside AG context
            // (e.g. inside button action closures captured during body evaluation).
            let cache = MutableBox<Value>(initialValue)
            let attr: Attribute<Value> = AGSubgraph.$current.withValue(wiringSubgraph) {
                graph.makeInput(value: initialValue)
            }
            // Capture the owning graph so the getter can detect cross-graph calls.
            // When a button action fires inside GestureGraph's AG context, the current
            // AttributeGraph can differ from the graph that owns this attr.
            // Accessing attr.value from the wrong graph causes an index-out-of-range
            // because each AttributeGraph has its own independent nodes array.
            let owningGraph = graph
            let location = LocationBox(location: FunctionalLocation<Value>(
                get: {
                    // Read the AG node only when executing inside the same graph that
                    // owns this attribute. Any other context (no AG, or a different
                    // graph such as GestureGraph) must fall back to the cache.
                    if AttributeGraph.current === owningGraph {
                        let v = attr.value
                        cache.value = v
                        return v
                    }
                    // Outside AG context, or different graph (e.g. GestureGraph firing
                    // a button action): return cached value without accessing the node.
                    return cache.value
                },
                set: { newValue, _ in
                    cache.value = newValue
                    let box = MutableBox(newValue)   // @unchecked Sendable for capture
                    inbox.enqueue {
                        attr.setValue(box.value)
                    }
                }
            ))
            mountedLocation.value = location
            var s = currentState
            s._location = location
            ptr.assumingMemoryBound(to: State<Value>.self).pointee = s
        }
    }
}
