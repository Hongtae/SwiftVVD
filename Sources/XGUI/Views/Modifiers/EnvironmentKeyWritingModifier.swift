//
//  File: EnvironmentKeyWritingModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public struct _EnvironmentKeyWritingModifier<Value> : ViewModifier, _GraphInputsModifier, _EnvironmentValuesResolve {
    public typealias Body = Never

    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public var value: Value

    @inlinable public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, value: Value) {
        self.keyPath = keyPath
        self.value = value
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        inputs.modifiers.append(_InputModifier(graph: modifier))
    }

    func _resolve(_ values: EnvironmentValues) -> EnvironmentValues {
        var values = values
        values[keyPath: self.keyPath] = value
        return values
    }

    func _resolve(_ values: inout EnvironmentValues) {
        values[keyPath: self.keyPath] = value
    }

    class _InputModifier : _GraphInputResolve {
        typealias Modifier = _EnvironmentKeyWritingModifier<Value>
        var isResolved: Bool {  modifier != nil }
        var modifier: Modifier?
        let graph: _GraphValue<Modifier>
        init(graph: _GraphValue<Modifier>) {
            self.graph = graph
        }

        func apply(to environment: inout EnvironmentValues) {
            if let modifier {
                modifier._resolve(&environment)
            }
        }

        func reset() {
            modifier = nil
        }
        
        func resolve(container: some _GraphValueResolver) {
            if let modifier = container.value(atPath: self.graph) {
                self.modifier = modifier
            }
        }

        static func == (lhs: _InputModifier, rhs: _InputModifier) -> Bool {
            lhs === rhs
        }
    }
}

extension View {
    @inlinable public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        return modifier(_EnvironmentKeyWritingModifier(keyPath: keyPath, value: value))
    }
}
