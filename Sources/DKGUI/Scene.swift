//
//  File: Scene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import DKGame

public protocol Scene {
    associatedtype Body: Scene
    var body: Self.Body { get }
}

protocol PrimitiveScene: Scene {
    func makeSceneProxies() -> [SceneProxy]
}

extension PrimitiveScene {
    public var body: Never { neverBody() }
}

struct _TupleScene<T>: PrimitiveScene {

    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    func makeSceneProxies() -> [SceneProxy] {
        return Mirror(reflecting: value).children.flatMap { child in
            if let scene = child as? any Scene {
                return _TupleScene<T>._makeSceneProxies(scene)
            }
            return []
        }
    }

    func makeWindowProxy() -> WindowProxy? { nil }
}

class WindowProxy: WindowDelegate {
    var frame: Frame?
    var screen: Screen?
    var window: Window?
    weak var scene: SceneProxy?

    func makeWindow() -> Window? { nil }

    init(frame: Frame? = nil, screen: Screen? = nil, window: Window? = nil, scene: SceneProxy? = nil) {
        self.frame = frame
        self.screen = screen
        self.window = window
        self.scene = scene
    }
}

class SceneProxy {
    let scene: any Scene
    let children: [SceneProxy]

    weak var parent: SceneProxy?
    var windowProxy: WindowProxy?

    init(scene: any Scene, children: [SceneProxy], parent: SceneProxy? = nil) {
        self.scene = scene
        self.children = children
        self.parent = parent
    }

    func makeWindowProxies() -> [WindowProxy] {
        var proxies: [WindowProxy] = []
        if let proxy = windowProxy {
            proxies.append(proxy)
        }
        for child in children {
            proxies.append(contentsOf: child.makeWindowProxies())
        }
        return proxies
    }
}

extension Scene {
    static func _makeSceneProxies(_ scene: any Scene) -> [SceneProxy] {
        if let prim = scene as? (any PrimitiveScene) {
            return prim.makeSceneProxies()
        }
        let children = _makeSceneProxies(scene.body)
        return [SceneProxy(scene: scene, children: children)]
    }
}
