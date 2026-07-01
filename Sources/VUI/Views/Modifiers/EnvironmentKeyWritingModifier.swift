//
//  File: EnvironmentKeyWritingModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct _EnvironmentKeyWritingModifier<Value>: ViewModifier, _GraphInputsModifier {
    public typealias Body = Never

    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public var value: Value

    @inlinable public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, value: Value) {
        self.keyPath = keyPath
        self.value = value
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeInputs called outside an active _AGGraph context.")
        }
        let parentEnvAttr = inputs.cachedEnvironment.value.environment
        let newEnvAttr: Attribute<EnvironmentValues> = graph.makeRule {
            let m = modifier._attribute.value   // dep: modifier value changes
            var env = parentEnvAttr.value.trackingCopy() // dep: parent environment changes
            env[keyPath: m.keyPath] = m.value
            return env
        }
        inputs.cachedEnvironment = MutableBox(CachedEnvironment(environment: newEnvAttr))
    }
}

extension View {
    @inlinable public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        return modifier(_EnvironmentKeyWritingModifier(keyPath: keyPath, value: value))
    }
}
