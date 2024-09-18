//
//  File: SceneContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

protocol WindowProxy: AnyObject {
//    associatedtype Content: View
//    var view: Content { get }
    var identifier: String { get }
    var contextType: Any.Type { get }
    var window: Window? { get }
    var swapChain: SwapChain? { get }
    @MainActor func makeWindow() -> Window?
}

protocol SceneProxy: AnyObject {
    associatedtype Content: Scene
    var scene: Content { get }
//    var modifiers: [any _SceneModifier] { get }
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

class SceneContext<Content>: SceneProxy where Content: Scene {
    var scene: Content
    var modifiers: [any _SceneModifier]
    var children: [any SceneProxy]
    var windows: [any WindowProxy]
    init(scene: Content, modifiers: [any _SceneModifier], children: [any SceneProxy]) {
        self.scene = scene
        self.modifiers = modifiers
        self.children = children
        self.windows = children.flatMap { $0.windows }
    }
    init(scene: Content, modifiers: [any _SceneModifier], window: any WindowProxy) {
        self.scene = scene
        self.modifiers = modifiers
        self.children = []
        self.windows = [window]
    }
}

func _makeSceneProxy<Content>(_ scene: Content,
                              modifiers: [any _SceneModifier]) -> any SceneProxy where Content: Scene {
    if let prim = scene as? (any _PrimitiveScene) {
        return prim.makeSceneProxy(modifiers: modifiers)
    }
    let child = _makeSceneProxy(scene.body, modifiers: modifiers)
    return SceneContext(scene: scene, modifiers: modifiers, children: [child])
}
