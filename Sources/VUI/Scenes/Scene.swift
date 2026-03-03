//
//  File: Scene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder var body: Self.Body { get }
    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs
}

extension Scene {
    public static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        Body._makeScene(scene: scene[\.body], inputs: inputs)
    }
}

extension Never: Scene {
}

protocol _PrimitiveScene: Scene {
}

extension _PrimitiveScene {
    public var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }
}

public struct _SceneInputs {
    var environment: EnvironmentValues
    var properties: PropertyList = .init()
}

public struct _SceneOutputs {
    let scene: Any?
}
