//
//  File: SceneResources.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// SceneResources — per-scene (per-WindowController) render resource cache.
// Owned by WindowController; passed down through WindowContext → GraphicsContext.
// Aux/modal windows under the same WindowController share the same instance.
final class SceneResources: @unchecked Sendable {
    var contentScaleFactor: CGFloat = 1.0
    var cachedTypeFaces: [Font: TypeFace] = [:]
    var cachedTextures: [String: AnyObject] = [:]
}
