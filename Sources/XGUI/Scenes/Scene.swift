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

protocol SceneRoot: AnyObject, _GraphValueResolver {
    associatedtype Root: Scene
    var root: Root { get }
    var graph: _GraphValue<Root> { get }
    var app: AppContext { get }
}

extension SceneRoot {
    func value<T>(atPath path: _GraphValue<T>) -> T? {
        graph.value(atPath: path, from: root)
    }
}

class TypedSceneRoot<Root>: SceneRoot where Root: Scene {
    let root: Root
    let graph: _GraphValue<Root>
    unowned var app: AppContext

    init(root: Root, graph: _GraphValue<Root>, app: AppContext) {
        self.root = root
        self.graph = graph
        self.app = app
    }
}

public struct _SceneInputs {
    var root: any SceneRoot
    var environment: EnvironmentValues
    var properties: PropertyList = .init()
    var modifiers: [any _GraphInputResolve] = []
}

extension _SceneInputs {
    mutating func resetModifiers() {
        self.modifiers.indices.forEach { index in
            self.modifiers[index].reset()
        }
    }
}

public struct _SceneOutputs {
    let scene: (any SceneGenerator)?
}
