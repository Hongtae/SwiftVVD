//
//  File: SharedContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

enum DisplayScaleEnvironmentKey: EnvironmentKey {
    static var defaultValue: CGFloat { return 1 }
}

extension EnvironmentValues {
    public var displayScale: CGFloat {
        set { self[DisplayScaleEnvironmentKey.self] = newValue }
        get { self[DisplayScaleEnvironmentKey.self] }
    }
}

struct WeakObject<T: AnyObject> : Equatable {
    weak var value: T?
    static func == (a: Self, b: Self) -> Bool { a.value === b.value }

    init(_ value: T?) {
        self.value = value
    }
}

class SharedContext {
    var appContext: AppContext

    var window: Window?
    var commandQueue: CommandQueue? // render queue for window swap-chain
    var graphicsContext: GraphicsContext?

    var contentBounds: CGRect
    var contentScaleFactor: CGFloat
    var needsLayout: Bool

    var resourceData: [String: Data] = [:]
    var resourceObjects: [String: AnyObject] = [:]
    var cachedTypeFaces: [Font: TypeFace] = [:]

    var focusedViews: [Int: WeakObject<ViewContext>] = [:]

    init(appContext: AppContext) {
        self.appContext = appContext
        self.contentBounds = .zero
        self.contentScaleFactor = 1
        self.needsLayout = true
    }

    func updateReferencedResourceObjects() {
        struct WeakWrapper {
            weak var value: AnyObject?
        }
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
        var url: URL? = nil
        //TODO: check for Bundle.module crashes on Windows,Linux after Swift 5.8
#if os(macOS) || os(iOS)
        url = bundle.url(forResource: name, withExtension: nil)
#else
        url = bundle.bundleURL.appendingPathComponent(name)
#endif
        if let url {
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
