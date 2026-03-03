//
//  File: SharedContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
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

final class SharedContext: @unchecked Sendable {

    var scene: Any { fatalError("Implement with AG") }
    var app: AppContext { fatalError("Implement with AG") }
    var root: Any?

    var contentBounds: CGRect
    var contentScaleFactor: CGFloat
    var needsLayout: Bool

    var resourceData: [String: Data] = [:]
    var resourceObjects: [String: AnyObject] = [:]
    var cachedTypeFaces: [Font: TypeFace] = [:]
    var focusedViews: [Int: WeakObject<AnyObject>] = [:]


    var gestureHandlers: [_GestureHandler] = []

    var window: WindowContext { fatalError("Implement with AG") }
    
    var auxiliarySceneContext: AuxiliarySceneContext?
    var alertDismissAction: (() -> Void)?

    init(scene: Any) {
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
