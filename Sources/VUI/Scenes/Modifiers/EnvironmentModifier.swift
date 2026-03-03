//
//  File: EnvironmentModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Observation

// _EnvironmentKeyWritingModifier and _EnvironmentKeyTransformModifier are
// _GraphInputsModifier conformers. The _SceneModifier extension in
// SceneModifier.swift provides _makeScene automatically when Body == Never.

extension _EnvironmentKeyWritingModifier: _SceneModifier {}
extension _EnvironmentKeyTransformModifier: _SceneModifier {}

extension Scene {
    public func environment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>,
        _ value: V
    ) -> some Scene {
        modifier(_EnvironmentKeyWritingModifier(keyPath: keyPath, value: value))
    }

    public func transformEnvironment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>,
        transform: @escaping (inout V) -> Void
    ) -> some Scene {
        modifier(_EnvironmentKeyTransformModifier(keyPath: keyPath, transform: transform))
    }

    /// Injects an `Observable` object into the environment by its concrete type.
    /// Uses `_EnvironmentKeyWritingModifier<T?>`.
    /// Downstream scenes and views can read it with `@Environment(T.self)`.
    /// Passing `nil` removes the object from the environment.
    public func environment<T: AnyObject & Observable>(_ object: T?) -> some Scene {
        modifier(_EnvironmentKeyWritingModifier(
            keyPath: \EnvironmentValues[_obs: ObjectIdentifier(T.self)],
            value: object
        ))
    }
}
