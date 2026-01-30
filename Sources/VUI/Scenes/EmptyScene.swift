//
//  File: EmptyScene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public struct _EmptyScene: Scene {

    @inlinable public init() {
    }

    public static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        fatalError()
    }

    public typealias Body = Never
}

extension _EmptyScene: Sendable {
}

extension _EmptyScene: _PrimitiveScene {
}
