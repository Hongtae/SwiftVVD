//
//  File: EmptyScene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public struct _EmptyScene : Scene {
}

extension _EmptyScene : _PrimitiveScene {
    func makeSceneProxy(modifiers: [any _SceneModifier]) -> any SceneProxy {
        SceneContext(scene: self, modifiers: modifiers, children: [])
    }
}
