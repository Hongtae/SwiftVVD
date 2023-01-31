//
//  File: EnvironmentKeyWritingModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

protocol _EnvironmentValuesResolve {
    func resolve(_ values: EnvironmentValues) -> EnvironmentValues
}

struct _EnvironmentKeyWritingModifier<Value>: ViewModifier, _EnvironmentValuesResolve {
    typealias Body = Never

    var keyPath: WritableKeyPath<EnvironmentValues, Value>
    var value: Value
    init(keyPath: WritableKeyPath<EnvironmentValues, Value>, value: Value) {
        self.keyPath = keyPath
        self.value = value
    }

    func resolve(_ values: EnvironmentValues) -> EnvironmentValues {
        var values = values
        values[keyPath: self.keyPath] = value
        return values
    }
}

extension View {
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        return modifier(_EnvironmentKeyWritingModifier(keyPath: keyPath, value: value))
    }
}
