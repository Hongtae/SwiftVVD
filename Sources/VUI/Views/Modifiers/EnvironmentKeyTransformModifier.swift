//
//  File: EnvironmentKeyTransformModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public struct _EnvironmentKeyTransformModifier<Value>: ViewModifier, _GraphInputsModifier {
    public typealias Body = Never

    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public let transform: (inout Value) -> Void

    @inlinable public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, transform: @escaping (inout Value) -> Void) {
        self.keyPath = keyPath
        self.transform = transform
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        fatalError("Implement with AG")
    }
}

extension View {
    @inlinable public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, transform: @escaping (inout V) -> Void) -> some View {
        return modifier(_EnvironmentKeyTransformModifier(keyPath: keyPath, transform: transform))
    }
}
