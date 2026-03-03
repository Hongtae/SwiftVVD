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
        // Capture the active Subgraph at wiring time so the state node is registered
        // to the correct subgraph (e.g. the one created by Optional._makeView).
        let wiringSubgraph = Subgraph.current
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
            let attr: Attribute<Value> = Subgraph.$current.withValue(wiringSubgraph) {
                graph.makeInput(value: initialValue)
            }
            let location = LocationBox(location: FunctionalLocation<Value>(
                get: {
                    // Inside a rule: read the AG node (registers dependency).
                    if AttributeGraph.current != nil {
                        let v = attr.value
                        cache.value = v
                        return v
                    }
                    // Outside AG context (e.g. action closure): return cached value.
                    return cache.value
                },
                set: { newValue, _ in
                    cache.value = newValue
                    let box = MutableBox(newValue)   // @unchecked Sendable for capture
                    inbox.enqueue { attr.setValue(box.value) }
                }
            ))
            mountedLocation.value = location
            var s = currentState
            s._location = location
            ptr.assumingMemoryBound(to: State<Value>.self).pointee = s
        }
    }
}

