//
//  File: SharedContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD


final class SharedContext: @unchecked Sendable {

    var app: AppContext { appContext! }

    var contentBounds: CGRect
    var contentScaleFactor: CGFloat
    var needsLayout: Bool

    var resourceData: [String: Data] = [:]
    var resourceObjects: [String: AnyObject] = [:]
    var cachedTypeFaces: [Font: TypeFace] = [:]

    // TODO: Use AppWindowsController
    var focusedViews: [Int: WeakObject<AnyObject>] = [:]

    // TODO: Implement with AG
    var gestureHandlers: [_GestureHandler] = [] 

    var window: WindowController { fatalError("Implement with AG") }
    
    var auxiliarySceneContext: AuxiliarySceneContext?
    var alertDismissAction: (() -> Void)?

    init() {
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

