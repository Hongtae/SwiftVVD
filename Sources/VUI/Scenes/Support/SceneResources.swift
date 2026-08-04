//
//  File: SceneResources.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// SceneResources — per-renderer-host (per-WindowController) resource cache.
// Owned by WindowController; passed down through WindowContext → GraphicsContext.
// Presentation controllers own their corresponding host cache.
final class SceneResources: AppLifetimeResource, @unchecked Sendable {
    struct TypefaceKey: Hashable {
        let font: Font
        let dpi: UInt32
    }

    var contentScaleFactor: CGFloat = 1.0
    var cachedTypefaces: [TypefaceKey: Typeface] = [:]
    var cachedTextures: [String: AnyObject] = [:]
    
    override func purgeResources(reason: ResourcePurgeReason) {
        cachedTypefaces.values.forEach {
            $0.purgeResources(reason: reason)
        }

        switch reason {
        case .lowMemory, .appTermination:
            cachedTypefaces.removeAll()
            cachedTextures.removeAll()
        }
    }
}
