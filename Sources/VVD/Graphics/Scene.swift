//
//  File: Scene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

public struct SceneState {
    public var view: ViewTransform
    public var projection: ProjectionTransform
    public var model: Matrix4
    public init(view: ViewTransform, projection: ProjectionTransform, model: Matrix4) {
        self.view = view
        self.projection = projection
        self.model = model
    }
}

public struct SceneNode {
    public var name: String
    public var mesh: Mesh?

    public var scale: Vector3 = Vector3(1, 1, 1)
    public var transform: Transform = .identity

    public var children: [SceneNode] = []

    public init(name: String, mesh: Mesh? = nil) {
        self.name = name
        self.mesh = mesh
    }
}

public class Scene {
    public var nodes: [SceneNode] = []
    public init() {
    }
}
