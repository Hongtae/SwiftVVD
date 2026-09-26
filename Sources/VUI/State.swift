//
//  File: State.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

@attached(accessor, names: named(init), named(get), named(set))
@attached(peer, names: prefixed(_), prefixed(__), prefixed(`$`))
public macro State() = #externalMacro(
    module: "VUIMacros",
    type: "StateMacro"
)

@attached(accessor, names: named(init), named(get), named(set))
@attached(peer, names: prefixed(_), prefixed(__), prefixed(`$`))
public macro State<Value>(initialValue: Value) = #externalMacro(
    module: "VUIMacros",
    type: "StateMacro"
)

@attached(accessor, names: named(init), named(get), named(set))
@attached(peer, names: prefixed(_), prefixed(__), prefixed(`$`))
public macro State<Value>(wrappedValue: Value) = #externalMacro(
    module: "VUIMacros",
    type: "StateMacro"
)

@attached(accessor, names: named(init), named(get), named(set))
public macro _StatePropertyWrapperStorage(initialValue: String) = #externalMacro(
    module: "VUIMacros",
    type: "StatePropertyWrapperStorageMacro"
)

@attached(accessor, names: named(init), named(get), named(set))
public macro _StatePropertyWrapperStorage() = #externalMacro(
    module: "VUIMacros",
    type: "StatePropertyWrapperStorageMacro"
)

@attached(accessor, names: named(get))
public macro _StateInitialStoredValue(_ initialValue: String) = #externalMacro(
    module: "VUIMacros",
    type: "StateInitialStoredValueMacro"
)

@attached(accessor, names: named(get))
public macro _StateProjectedValue() = #externalMacro(
    module: "VUIMacros",
    type: "StateProjectedValueMacro"
)

@attached(accessor, names: named(get))
public macro _PropertyWrapperProjectedValue() = #externalMacro(
    module: "VUIMacros",
    type: "ProjectedValueMacro"
)

@usableFromInline
func _stateValuesAreKnownEqual<Value>(_ lhs: Value, _ rhs: Value) -> Bool {
    guard let lhs = lhs as? AnyHashable,
          let rhs = rhs as? AnyHashable else {
        return withUnsafeBytes(of: lhs) { lhsBytes in
            withUnsafeBytes(of: rhs) { rhsBytes in
                lhsBytes.elementsEqual(rhsBytes)
            }
        }
    }
    return lhs == rhs
}

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
        _location = ObservableLocation(_value, onValueUpdated: { value in
            fatalError()
        })
    }

    public var wrappedValue: Value {
        get {
            if let _location {
                if GraphHost.isUpdating {
                    return _value
                }
                return _location.getValue()
            }
            return _value
        }
        nonmutating set {
            if let _location {
                _location.setValue(newValue, transaction: Transaction.current)
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

@export(implementation)
@_transparent
public func _stateNil<T>(of _: () -> T) -> T? {
    nil
}

extension State {
    @export(implementation)
    public static func _makeStorage(
        _ makeInitialValue: @escaping () -> Value
    ) -> LazyState<Value> {
        LazyState(initialValue: makeInitialValue)
    }

    @export(implementation)
    public static func _makeStorage(initialValue: Value) -> LazyState<Value> {
        LazyState(_initialValue: initialValue)
    }

    @export(implementation)
    public static func _makeStorageFrozen(
        _ makeInitialValue: @escaping () -> Value
    ) -> LazyState<Value> {
        LazyState(initialValue: makeInitialValue)
    }

    @export(implementation)
    public static func _makeStorageFrozen(initialValue: Value) -> LazyState<Value> {
        LazyState(_initialValue: initialValue)
    }

    public static var _propertyStorageSize: Int? {
        16
    }
}

@_documentation(visibility: internal)
public struct LazyState<Value>: DynamicProperty {
    public enum Storage: @unchecked Sendable {
        case thunk(() -> Value)
        case value(Value)
    }

    @usableFromInline
    var _storage: Storage

    @usableFromInline
    var _location: AnyLocation<Value>?

    public init(initialValue thunk: @escaping () -> Value) {
        _storage = .thunk(thunk)
    }

    @export(implementation)
    public init(_initialValue: Value) {
        _storage = .value(_initialValue)
    }

    public var wrappedValue: Value {
        get {
            if let _location {
                if GraphHost.isUpdating {
                    switch _storage {
                    case .thunk(let thunk):
                        return thunk()
                    case .value(let value):
                        return value
                    }
                }
                return _location.getValue()
            }

            switch _storage {
            case .thunk(let thunk):
                return thunk()
            case .value(let value):
                return value
            }
        }
        nonmutating set {
            _location?.setValue(newValue, transaction: Transaction.current)
        }
    }

    public var projectedValue: Binding<Value> {
        if let _location {
            return Binding(location: _location)
        }
        print("Accessing State's value outside of being installed on a View. This will result in a constant Binding of the initial value and will not update.")
        return .constant(wrappedValue)
    }

    public static var _propertyStorageSize: Int? {
        16
    }

    public static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeProperty called outside an active _AGGraph context.")
        }

        let wiringSubgraph = AGSubgraph.current
        let signal: Attribute<Void> = AGSubgraph.withCurrent(wiringSubgraph) {
            graph.makeInput(value: ())
        }
        let mountedLocation = MutableBox<AnyLocation<Value>?>(nil)

        assert(buffer.properties.contains { $0.offset == fieldOffset } == false)
        buffer.properties.append(.init(type: Self.self, offset: fieldOffset))
        buffer.contexts[fieldOffset] = { (ptr: UnsafeMutableRawPointer) in
            guard _AGGraph.current != nil else {
                fatalError("\(Self.self)._makeProperty context closure called outside an active _AGGraph context.")
            }
            let currentState = ptr.assumingMemoryBound(to: LazyState<Value>.self).pointee
            _ = signal.value

            if let location = mountedLocation.value {
                var state = currentState
                state._storage = .value(location.update().0)
                state._location = location
                ptr.assumingMemoryBound(to: LazyState<Value>.self).pointee = state
                return
            }

            let initialValue: Value
            switch currentState._storage {
            case .thunk(let thunk):
                initialValue = thunk()
            case .value(let value):
                initialValue = value
            }
            let location = StoredLocation<Value>(
                initialValue: initialValue,
                host: GraphHost.currentHost,
                signal: signal.asWeak().base
            )
            mountedLocation.value = location
            var state = currentState
            state._storage = .value(location.update().0)
            state._location = location
            ptr.assumingMemoryBound(to: LazyState<Value>.self).pointee = state
        }
    }
}

extension State {
    public static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeProperty called outside an active _AGGraph context.")
        }

        // Capture the active AGSubgraph at wiring time so the state node is registered
        // to the correct subgraph (e.g. the one created by Optional._makeView).
        let wiringSubgraph = AGSubgraph.current
        let signal: Attribute<Void> = AGSubgraph.withCurrent(wiringSubgraph) {
            graph.makeInput(value: ())
        }
        // Shared across all body evaluations for this @State field.
        let mountedLocation = MutableBox<AnyLocation<Value>?>(nil)

        assert(buffer.properties.contains { $0.offset == fieldOffset } == false)
        buffer.properties.append(.init(type: Self.self, offset: fieldOffset))
        buffer.contexts[fieldOffset] = { (ptr: UnsafeMutableRawPointer) in
            guard _AGGraph.current != nil else {
                fatalError("\(Self.self)._makeProperty context closure called outside an active _AGGraph context.")
            }
            let currentState = ptr.assumingMemoryBound(to: State<Value>.self).pointee
            _ = signal.value

            if let location = mountedLocation.value {
                // Already mounted: restore the location on this view copy.
                var s = currentState
                s._value = location.update().0
                s._location = location
                ptr.assumingMemoryBound(to: State<Value>.self).pointee = s
                return
            }

            // Resolve the host on first mount so the stored update closure does
            // not retain it. The signal still belongs to the wiring subgraph.
            let initialValue = currentState._value
            let location = StoredLocation<Value>(
                initialValue: initialValue,
                host: GraphHost.currentHost,
                signal: signal.asWeak().base
            )
            mountedLocation.value = location
            var s = currentState
            s._value = location.update().0
            s._location = location
            ptr.assumingMemoryBound(to: State<Value>.self).pointee = s
        }
    }
}
