//
//  File: Scene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct SceneState {
    public let view: ViewTransform
    public let projection: ProjectionTransform
    public var model: Matrix4
}

public struct SceneNode {
    let name: String
    let mesh: Mesh?

    var scale: Vector3 = Vector3(1, 1, 1)
    var transform: Transform = .identity

    var children: [SceneNode]
}

public class Scene {
    var nodes: [SceneNode]

    public init() {
        self.nodes = []
    }
}
