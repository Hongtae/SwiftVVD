//
//  File: EnvironmentKeyTransformModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

public struct _EnvironmentKeyTransformModifier<Value> : ViewModifier, _GraphInputsModifier, _EnvironmentValuesResolve {
    public typealias Body = Never

    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public let transform: (inout Value) -> Void

    @inlinable public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, transform: @escaping (inout Value) -> Void) {
        self.keyPath = keyPath
        self.transform = transform
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        inputs.modifiers.append(_InputModifier(graph: modifier))
    }

    func _resolve(_ values: EnvironmentValues) -> EnvironmentValues {
        var values = values
        var value = values[keyPath: self.keyPath]
        transform(&value)
        values[keyPath: self.keyPath] = value
        return values
    }

    func _resolve(_ values: inout EnvironmentValues) {
        var value = values[keyPath: self.keyPath]
        transform(&value)
        values[keyPath: self.keyPath] = value
    }

    class _InputModifier : _GraphInputResolve {
        typealias Modifier = _EnvironmentKeyTransformModifier<Value>
        var isResolved: Bool {  modifier != nil }
        var modifier: Modifier?
        let graph: _GraphValue<Modifier>
        init(graph: _GraphValue<Modifier>) {
            self.graph = graph
        }

        func apply(inputs: inout _GraphInputs) {
            if let modifier {
                modifier._resolve(&inputs.environment)
            }
        }

        func resolve<T>(encloser: T, graph: _GraphValue<T>) {
            if let modifier = graph.value(atPath: self.graph, from: encloser) {
                self.modifier = modifier
            }
        }

        static func == (lhs: _EnvironmentKeyTransformModifier<Value>._InputModifier, rhs: _EnvironmentKeyTransformModifier<Value>._InputModifier) -> Bool {
            lhs === rhs
        }
    }
}

extension View {
    @inlinable public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, transform: @escaping (inout V) -> Void) -> some View {
        return modifier(_EnvironmentKeyTransformModifier(keyPath: keyPath, transform: transform))
    }
}
