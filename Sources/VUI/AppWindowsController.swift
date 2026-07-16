//
//  File: AppWindowsController.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// AppWindowsController manages statically declared scene WindowControllers for the app.
// Dynamic presentation children such as popovers, modals, and sheets are owned
// directly by their parent WindowController, not by this static-scene registry.
class AppWindowsController: @unchecked Sendable {

    // WindowGroup: array because openWindow() can open multiple instances per key.
    var mainWindowControllers: [WindowKey: [WindowController]] = [:]

    // Window scene: single instance per key.
    var singleWindowControllers: [WindowKey: WindowController] = [:]

    // Reserved for statically declared auxiliary scenes.
    var auxiliaryWindowControllers: [WindowKey: WindowController] = [:]

    // Settings scene — at most one app-wide.
    var settingsWindowController: WindowController? = nil

    // Controllers that have been closed but may be restored.
    var dismissedWindowControllers: [WindowController] = []

    // Tracks the number of open windows per key (for openWindow action).
    var windowCounts: [WindowKey: UInt32] = [:]

    // Cascade offset per key — applied when opening successive windows of the same type.
    var cascadeNumbers: [WindowKey: UInt32] = [:]
    var auxiliaryCascadeNumber: UInt32 = 0

    // All currently live static-scene controllers (flattened across all registries).
    // Dynamic children (sheets, popovers, modals) are NOT included here — they are
    // owned by their parent WindowController.
    var allWindowControllers: [WindowController] {
        var result: [WindowController] = []
        mainWindowControllers.values.forEach { result.append(contentsOf: $0) }
        singleWindowControllers.values.forEach { result.append($0) }
        auxiliaryWindowControllers.values.forEach { result.append($0) }
        if let s = settingsWindowController { result.append(s) }
        return result
    }

    // Synchronizes the controller registries against the current SceneList,
    // and applies runtime window configuration overrides to all live controllers.
    // Must be called from outside an AG context; internally activates `graph`
    // to pull-evaluate the AG nodes.
    func syncWindowControllers(sceneListAttr: Attribute<[SceneList.Item]>?,
                               configurationOverrideAttr: Attribute<WindowConfiguration.Override>? = nil,
                               in graph: _AGGraph) {
        guard let attr = sceneListAttr else { return }

        _AGGraph.withCurrent(graph) {
            let items = attr.value
            let activeKeys = Set(items.map { $0.windowKey })

            // Open: create a controller for each newly-appearing item.
            for item in items {
                let makeWC = {
                    let wc = item.makeController()
                    wc.sceneConfiguration = item.sceneConfiguration
                    return wc
                }
                switch item.kind {
                case .main:
                    if mainWindowControllers[item.windowKey] == nil {
                        mainWindowControllers[item.windowKey] = [makeWC()]
                    }
                case .single:
                    if singleWindowControllers[item.windowKey] == nil {
                        singleWindowControllers[item.windowKey] = makeWC()
                    }
                case .settings:
                    if settingsWindowController == nil {
                        settingsWindowController = makeWC()
                    }
                case .auxiliary:
                    if auxiliaryWindowControllers[item.windowKey] == nil {
                        auxiliaryWindowControllers[item.windowKey] = makeWC()
                    }
                }
            }

            // Close: remove controllers whose window keys disappeared.
            mainWindowControllers      = mainWindowControllers.filter      { activeKeys.contains($0.key) }
            singleWindowControllers    = singleWindowControllers.filter    { activeKeys.contains($0.key) }
            auxiliaryWindowControllers = auxiliaryWindowControllers.filter { activeKeys.contains($0.key) }
            if !items.contains(where: { $0.kind == .settings }) {
                settingsWindowController = nil
            }

            // An absent preference removes any override left by a previous sync.
            let configurationOverride = configurationOverrideAttr?.value ?? .init()
            for windowController in allWindowControllers {
                windowController.configurationOverride = configurationOverride
            }
        }
    }
}
