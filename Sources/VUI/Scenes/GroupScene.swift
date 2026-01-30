//
//  File: GroupScene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

extension Group: Scene where Content: Scene {
    @inlinable
    public init(@SceneBuilder content: () -> Content) {
        self.init(_content: content())
    }
    
    public static func _makeScene(scene: _GraphValue<Group<Content>>, inputs: _SceneInputs) -> _SceneOutputs {
        fatalError()
    }
}

extension Group: _PrimitiveScene where Content: Scene {
}
