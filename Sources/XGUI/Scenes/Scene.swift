//
//  File: Scene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol Scene {
    associatedtype Body : Scene
    var body: Self.Body { get }
}

protocol _PrimitiveScene : Scene {
    func makeSceneProxy(modifiers: [any _SceneModifier]) -> any SceneProxy
}

extension _PrimitiveScene {
    public var body: Never { neverBody() }
}

extension Never : Scene {
}

struct TupleScene<T> : Scene, _PrimitiveScene {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    subscript<U>(keyPath: KeyPath<T, U>) -> U {
        self.value[keyPath: keyPath]
    }

    func makeSceneProxy(modifiers: [any _SceneModifier]) -> any SceneProxy {
        let mirror = Mirror(reflecting: value)
        let children = mirror.children.map { child in
            let scene = child as! (any Scene)
            return _makeSceneProxy(scene, modifiers: modifiers)
        }
        let proxy = SceneContext(scene: self, modifiers: modifiers, children: children)
        return proxy
    }
}
