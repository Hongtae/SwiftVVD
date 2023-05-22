//
//  File: EnvironmentKeyTransformModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

struct _EnvironmentKeyTransformModifier<Value>: ViewModifier, _EnvironmentValuesResolve {
    typealias Body = Never

    var keyPath: WritableKeyPath<EnvironmentValues, Value>
    let transform: (inout Value) -> Void

    init(keyPath: WritableKeyPath<EnvironmentValues, Value>, transform: @escaping (inout Value) -> Void) {
        self.keyPath = keyPath
        self.transform = transform
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
    public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, transform: @escaping (inout V) -> Void) -> some View {
        return modifier(_EnvironmentKeyTransformModifier(keyPath: keyPath, transform: transform))
    }
}
