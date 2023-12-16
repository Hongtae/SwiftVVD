//
//  File: GestureState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

@propertyWrapper public struct GestureState<Value> : DynamicProperty {
    fileprivate var state: State<Value>
    fileprivate let reset: (Binding<Value>) -> Void

    public init(wrappedValue: Value) {
        fatalError()
    }

    public init(initialValue: Value) {
        self.init(wrappedValue: initialValue, resetTransaction: Transaction())
    }

    public init(wrappedValue: Value, resetTransaction: Transaction) {
        fatalError()
    }

    public init(initialValue: Value, resetTransaction: Transaction) {
        self.init(wrappedValue: initialValue, resetTransaction: resetTransaction)
    }

    public init(wrappedValue: Value, reset: @escaping (Value, inout Transaction) -> Void) {
        fatalError()
    }

    public init(initialValue: Value, reset: @escaping (Value, inout Transaction) -> Void) {
        self.init(wrappedValue: initialValue, reset: reset)
    }
    public var wrappedValue: Value {
        fatalError()
    }
    public var projectedValue: GestureState<Value> {
        fatalError()
    }
}

extension GestureState where Value : ExpressibleByNilLiteral {
    public init(resetTransaction: Transaction = Transaction()) {
        fatalError()
    }
    public init(reset: @escaping (Value, inout Transaction) -> Void) {
        fatalError()
    }
}

extension Gesture {
    @inlinable public func updating<State>(_ state: GestureState<State>,
                                           body: @escaping (Self.Value, inout State, inout Transaction) -> Void) -> GestureStateGesture<Self, State> {
        return .init(base: self, state: state, body: body)
    }
}

public struct GestureStateGesture<Base, State> : Gesture where Base : Gesture {
    public typealias Value = Base.Value
    public var base: Base
    public var state: GestureState<State>
    public var body: (Self.Value, inout State, inout Transaction) -> Void
    @inlinable public init(base: Base,
                           state: GestureState<State>,
                           body: @escaping (Self.Value, inout State, inout Transaction) -> Void) {
        self.base = base
        self.state = state
        self.body = body
    }
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Self.Value> {
        fatalError()
    }
    public typealias Body = Never
}
