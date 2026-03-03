//
//  File: RuntimeWindowConfig.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// _RuntimeWindowConfig — runtime-mutable window settings supplied by scene modifiers.
//
// Distinct from SceneConfiguration (applied once at window creation) and
// WindowContext.Configuration (platform render config).
// Values here are re-evaluated whenever the AG scene graph updates and applied
// immediately to all live WindowControllers via AppWindowsController.syncWindowControllers.
struct _RuntimeWindowConfig {
    // nil = modifier not applied; the existing WindowContext.Configuration value is kept.
    var activeFrameRate: CGFloat? = nil
    var inactiveFrameRate: CGFloat? = nil
    var drawDebugInfo: _DrawDebug.Info = []
}

// Preference key that carries _RuntimeWindowConfig up the scene tree to AppGraph.
// reduce: frame rates override (last modifier wins), debug flags union.
extension _RuntimeWindowConfig {
    struct Key: PreferenceKey {
        static var defaultValue: _RuntimeWindowConfig { _RuntimeWindowConfig() }
        
        static func reduce(value: inout _RuntimeWindowConfig,
                           nextValue: () -> _RuntimeWindowConfig) {
            let next = nextValue()
            if let r = next.activeFrameRate   { value.activeFrameRate   = r }
            if let r = next.inactiveFrameRate { value.inactiveFrameRate = r }
            value.drawDebugInfo.formUnion(next.drawDebugInfo)
        }
    }
}
