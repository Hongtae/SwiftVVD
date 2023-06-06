//
//  File: EnvironmentKeyTransformModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct _EnvironmentKeyTransformModifier<Value>: ViewModifier, _GraphInputsModifier, _EnvironmentValuesResolve {
    public typealias Body = Never

    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public let transform: (inout Value) -> Void

    @inlinable public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, transform: @escaping (inout Value) -> Void) {
        self.keyPath = keyPath
        self.transform = transform
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        let modifier = modifier.value
        var value = inputs.environmentValues[keyPath: modifier.keyPath]
        modifier.transform(&value)
        inputs.environmentValues[keyPath: modifier.keyPath] = value
    }

    func _resolve(_ values: EnvironmentValues) -> EnvironmentValues {
        var values = values
        var value = values[keyPath: self.keyPath]
        transform(&value)
        values[keyPath: self.keyPath] = value
        return values
    }
}

extension View {
    @inlinable public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, transform: @escaping (inout V) -> Void) -> some View {
        return modifier(_EnvironmentKeyTransformModifier(keyPath: keyPath, transform: transform))
    }
}
