//
//  File: SceneContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import DKGame

protocol WindowProxy: AnyObject {
    associatedtype Content: View
    var view: Content { get }
    var identifier: String { get }
    var contextType: Any.Type { get }
    var window: Window? { get }
    var swapChain: SwapChain? { get }
    @MainActor func makeWindow() -> Window?
}

protocol SceneProxy {
    associatedtype Content: Scene
    var scene: Content { get }
    var children: [any SceneProxy] { get }
    var windows: [any WindowProxy] { get }
}

extension SceneProxy {
    func windowProxy<D>(for type: D.Type = D.self) -> (any WindowProxy)? {
        for window in self.windows {
            if window.contextType == type {
                return window
            }
        }
        return nil
    }

    func windowProxy(forID id: String) -> (any WindowProxy)? {
        for window in self.windows {
            if window.identifier == id {
                return window
            }
        }
        return nil
    }
}

struct SceneContext<Content>: SceneProxy where Content: Scene {
    var scene: Content
    var children: [any SceneProxy]
    var windows: [any WindowProxy]
    init(scene: Content, children: [any SceneProxy]) {
        self.scene = scene
        self.children = children
        self.windows = children.flatMap { $0.windows }
    }
    init(scene: Content, window: any WindowProxy) {
        self.scene = scene
        self.children = []
        self.windows = [window]
    }
}

func _makeSceneProxy<Content>(_ scene: Content) -> any SceneProxy where Content: Scene {
    if let prim = scene as? (any _PrimitiveScene) {
        return prim.makeSceneProxy()
    }
    let child = _makeSceneProxy(scene.body)
    return SceneContext(scene: scene, children: [child])
}
