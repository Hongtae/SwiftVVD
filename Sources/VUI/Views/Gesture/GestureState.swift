//
//  File: GestureState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// GestureState
//
// A property wrapper for values tied to a gesture's active phase.
// The value resets to its initial state whenever the gesture is not active
// (i.e., when the phase transitions to .ended, .failed, or .possible).
//
// Used with Gesture.updating(_:body:) to produce GestureStateGesture<Base, State>.
//
// Internal layout mirrors State<Value>: the actual storage is an AnyLocation<Value>
// wired up by _makeProperty before the gesture wiring pass runs.
@propertyWrapper public struct GestureState<Value>: DynamicProperty {
    @usableFromInline
    var _value: Value

    @usableFromInline
    var _location: AnyLocation<Value>?

    // Closure to apply when the gesture terminates.
    // Default: restore the initial value with no animation.
    fileprivate let _reset: (Value, inout Transaction) -> Void

    public init(wrappedValue: Value) {
        self.init(wrappedValue: wrappedValue, resetTransaction: Transaction())
    }

    public init(initialValue: Value) {
        self.init(wrappedValue: initialValue, resetTransaction: Transaction())
    }

    public init(wrappedValue: Value, resetTransaction: Transaction) {
        self._value = wrappedValue
        self._location = nil
        // Default reset: restore to the initial value using the given transaction.
        let initial = wrappedValue
        let tx = resetTransaction
        self._reset = { _, transaction in
            transaction = tx
            _ = initial  // captures initial for reset in GestureStateGesture
        }
    }

    public init(initialValue: Value, resetTransaction: Transaction) {
        self.init(wrappedValue: initialValue, resetTransaction: resetTransaction)
    }

    public init(wrappedValue: Value, reset: @escaping (Value, inout Transaction) -> Void) {
        self._value = wrappedValue
        self._location = nil
        self._reset = reset
    }

    public init(initialValue: Value, reset: @escaping (Value, inout Transaction) -> Void) {
        self.init(wrappedValue: initialValue, reset: reset)
    }

    // Read-only from outside; written exclusively through the updating(_:body:) closure.
    public var wrappedValue: Value {
        if let _location { return _location.getValue() }
        return _value
    }

    // Returns self so the projected value ($gesture) exposes the GestureState
    // for passing into updating(_:body:).
    public var projectedValue: GestureState<Value> { self }
}

extension GestureState where Value: ExpressibleByNilLiteral {
    public init(resetTransaction: Transaction = Transaction()) {
        self.init(wrappedValue: nil, resetTransaction: resetTransaction)
    }
    public init(reset: @escaping (Value, inout Transaction) -> Void) {
        self.init(wrappedValue: nil, reset: reset)
    }
}

extension GestureState: @unchecked Sendable where Value: Sendable {}

// _makeProperty wires GestureState into the AG graph.
// Creates an AG input node backed by a FunctionalLocation,
// then patches the GestureState struct inside the DynamicProperty buffer so that
// wrappedValue reads/writes go through the AG node.
extension GestureState {
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
        let wiringSubgraph = AGSubgraph.current
        let mountedLocation = MutableBox<AnyLocation<Value>?>(nil)

        assert(buffer.properties.contains { $0.offset == fieldOffset } == false)
        buffer.properties.append(.init(type: Self.self, offset: fieldOffset))
        buffer.contexts[fieldOffset] = { (ptr: UnsafeMutableRawPointer) in
            guard let graph = AttributeGraph.current else {
                fatalError("\(Self.self)._makeProperty context closure called outside an active AttributeGraph context.")
            }
            let currentGS = ptr.assumingMemoryBound(to: GestureState<Value>.self).pointee

            if let location = mountedLocation.value {
                var gs = currentGS
                gs._location = location
                ptr.assumingMemoryBound(to: GestureState<Value>.self).pointee = gs
                return
            }

            let initialValue = currentGS._value
            let cache = MutableBox<Value>(initialValue)
            let attr: Attribute<Value> = AGSubgraph.$current.withValue(wiringSubgraph) {
                graph.makeInput(value: initialValue)
            }
            let location = LocationBox(location: FunctionalLocation<Value>(
                get: {
                    if AttributeGraph.current != nil {
                        let v = attr.value
                        cache.value = v
                        return v
                    }
                    return cache.value
                },
                set: { newValue, _ in
                    cache.value = newValue
                    let box = MutableBox(newValue)
                    inbox.enqueue {
                        attr.setValue(box.value)
                    }
                }
            ))
            mountedLocation.value = location
            var gs = currentGS
            gs._location = location
            ptr.assumingMemoryBound(to: GestureState<Value>.self).pointee = gs
        }
    }
}

// GestureStateGesture
//
// Produced by Gesture.updating(_:body:).
// Passes active gesture values to the body closure and resets
// the GestureState when the gesture terminates.
extension Gesture {
    @inlinable public func updating<State>(
        _ state: GestureState<State>,
        body: @escaping (Self.Value, inout State, inout Transaction) -> Void
    ) -> GestureStateGesture<Self, State> {
        .init(base: self, state: state, body: body)
    }
}

public struct GestureStateGesture<Base, State>: Gesture where Base: Gesture {
    public typealias Value = Base.Value
    public var base: Base
    public var state: GestureState<State>
    public var body: (Self.Value, inout State, inout Transaction) -> Void

    @inlinable public init(
        base: Base,
        state: GestureState<State>,
        body: @escaping (Self.Value, inout State, inout Transaction) -> Void
    ) {
        self.base = base
        self.state = state
        self.body = body
    }

    public static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Self.Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("GestureStateGesture._makeGesture requires AG context")
        }

        // Wire the base gesture graph.
        let baseOutputs = Base._makeGesture(gesture: gesture[\.base], inputs: inputs)
        let phaseAttr = baseOutputs.phase

        // Access the location wired by _makeProperty.
        // If the GestureState was not installed via _makeProperty (e.g., created
        // inline without being a DynamicProperty on the owning view), the location
        // will be nil and we fall back to a local Attribute.
        let selfAttr = gesture._attribute

        // Create a local AG input that mirrors the GestureState's storage.
        // When the GestureState has a proper location (via _makeProperty), we use that;
        // otherwise this attribute acts as the sole storage.
        let stateAttr: Attribute<State> = graph.makeInput(
            value: selfAttr.value.state._value)

        // Side-effect rule: driven by the base gesture's phase.
        // During .active: call the updating body.
        // On termination (.ended, .failed): reset the state to its initial value.
        graph.makeSideEffectRule { () -> Void in
            let gsg = selfAttr.value
            let initialValue = gsg.state._value
            let location = gsg.state._location

            switch phaseAttr.value {
            case .active(let v):
                // Read current state, call body, write back.
                var current = location?.getValue() ?? stateAttr.value
                var tx = Transaction()
                gsg.body(v, &current, &tx)
                stateAttr.setValue(current)
                location?.setValue(current, transaction: tx)

            case .ended, .failed:
                // Gesture terminated: apply reset and restore initial value.
                var resetValue = location?.getValue() ?? stateAttr.value
                var tx = Transaction()
                gsg.state._reset(resetValue, &tx)
                resetValue = initialValue
                stateAttr.setValue(resetValue)
                location?.setValue(resetValue, transaction: tx)

            case .possible:
                // Not yet active, nothing to do.
                break
            }
        }

        return baseOutputs
    }

    public typealias Body = Never
}
