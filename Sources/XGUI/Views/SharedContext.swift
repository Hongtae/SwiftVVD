//
//  File: SharedContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

enum DisplayScaleEnvironmentKey: EnvironmentKey {
    static var defaultValue: CGFloat { return 1 }
}

extension EnvironmentValues {
    public var displayScale: CGFloat {
        set { self[DisplayScaleEnvironmentKey.self] = newValue }
        get { self[DisplayScaleEnvironmentKey.self] }
    }
}

protocol ViewRoot : AnyObject, _GraphValueResolver {
    associatedtype Root : View
    var root: Root { get }
    var graph: _GraphValue<Root> { get }
    var scene: SceneContext { get }
}

extension ViewRoot {
    func value<T>(atPath path: _GraphValue<T>) -> T? {
        graph.value(atPath: path, from: root)
    }
}

class TypedViewRoot<Root> : ViewRoot where Root : View {
    let root: Root
    let graph: _GraphValue<Root>
    unowned let scene: SceneContext

    init(root: Root, graph: _GraphValue<Root>, scene: SceneContext) {
        self.root = root
        self.graph = graph
        self.scene = scene
    }
}

final class SharedContext: @unchecked Sendable {
    unowned var scene: SceneContext
    var app: AppContext {
        scene.app
    }

    var root: (any ViewRoot)?

    var contentBounds: CGRect
    var contentScaleFactor: CGFloat
    var needsLayout: Bool
    var viewsNeedToReloadResources: [WeakObject<ViewContext>] = []

    var resourceData: [String: Data] = [:]
    var resourceObjects: [String: AnyObject] = [:]
    var cachedTypeFaces: [Font: TypeFace] = [:]

    var focusedViews: [Int: WeakObject<ViewContext>] = [:]

    var gestureHandlers: [_GestureHandler] = []

    init(scene: SceneContext) {
        self.scene = scene
        self.contentBounds = .zero
        self.contentScaleFactor = 1
        self.needsLayout = true
    }

    func updateReferencedResourceObjects() {
        let weakMap = resourceObjects.mapValues {
            WeakObject<AnyObject>($0)
        }
        resourceObjects.removeAll()
        resourceObjects = weakMap.compactMapValues {
            $0.value
        }
    }

    func loadResourceData(name: String, bundle: Bundle?, cache: Bool) -> Data? {
        Log.debug("Loading resource: \(name)...")
        let bundle = bundle ?? Bundle.module
        if let url = bundle.url(forResource: name, withExtension: nil) {
            if let data = self.resourceData[url.path] {
                return data
            }
            do {
                Log.debug("Loading resource: \(url)")
                let data = try Data(contentsOf: url, options: [])
                if cache {
                    self.resourceData[url.path] = data
                }
                return data
            } catch {
                Log.error("Error on loading data: \(error)")
            }
        }
        Log.error("cannot load resource.")
        return nil
    }

    @TaskLocal
    static var taskLocalContext: SharedContext? = nil
}

private struct ResourceBundleKey: EnvironmentKey {
    static let defaultValue: Bundle? = nil
}

extension EnvironmentValues {
    public var resourceBundle: Bundle? {
        get { self[ResourceBundleKey.self] }
        set { self[ResourceBundleKey.self] = newValue }
    }
}
