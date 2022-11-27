//
//  File: Scene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol Scene {
    associatedtype Body: Scene
    var body: Self.Body { get }
}

protocol PrimitiveScene: Scene {
    func makeSceneProxy() -> any SceneProxy
}

extension PrimitiveScene {
    public var body: Never { neverBody() }
}

struct TupleScene<T>: PrimitiveScene, Scene {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    subscript<U>(keyPath: KeyPath<T, U>) -> U {
        self.value[keyPath: keyPath]
    }

    func makeSceneProxy() -> any SceneProxy {
        let mirror = Mirror(reflecting: value)
        let children = mirror.children.map { child in
            let scene = child as! (any Scene)
            return _makeSceneProxy(scene)
        }
        let proxy = SceneContext(scene: self, children: children)
        return proxy
    }
}
