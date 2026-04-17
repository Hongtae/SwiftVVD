//
//  File: AppWindowsController.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// AppWindowsController manages all WindowControllers for the app.
//
// Owns four registries keyed by WindowKey, matching the scene type:
//   mainWindowControllers      <- WindowGroup (multiple instances allowed per key)
//   singleWindowControllers    <- Window       (one instance per key)
//   auxiliaryWindowControllers <- auxiliary/popover windows
//   settingsWindowController   <- Settings scene (at most one)
//
// AppMain owns this alongside AppGraph.
class AppWindowsController: @unchecked Sendable {

    // WindowGroup: array because openWindow() can open multiple instances per key.
    var mainWindowControllers: [WindowKey: [WindowController]] = [:]

    // Window scene: single instance per key.
    var singleWindowControllers: [WindowKey: WindowController] = [:]

    // Auxiliary / popover windows, single instance per key.
    var auxiliaryWindowControllers: [WindowKey: WindowController] = [:]

    // Settings scene, at most one app-wide.
    var settingsWindowController: WindowController? = nil

    // Dynamic aux windows (popups, popovers), strong ownership, nested under a parent.
    var dynamicAuxWindows: [WindowController] = []

    // Dynamic modal windows, single active at a time per parent.
    var dynamicModalWindows: [WindowController] = []

    // Modal slot dedup prevents the same logical slot from showing twice.
    var modalSlots: [AnyHashable: AnyWeakObject] = [:]

    // Controllers that have been closed but may be restored.
    var dismissedWindowControllers: [WindowController] = []

    // Tracks the number of open windows per key (for openWindow action).
    var windowCounts: [WindowKey: UInt32] = [:]

    // Cascade offset per key, applied when opening successive windows of the same type.
    var cascadeNumbers: [WindowKey: UInt32] = [:]
    var auxiliaryCascadeNumber: UInt32 = 0

    // All currently live controllers (flattened across all registries).
    var allWindowControllers: [WindowController] {
        var result: [WindowController] = []
        mainWindowControllers.values.forEach { result.append(contentsOf: $0) }
        singleWindowControllers.values.forEach { result.append($0) }
        auxiliaryWindowControllers.values.forEach { result.append($0) }
        if let s = settingsWindowController { result.append(s) }
        result.append(contentsOf: dynamicAuxWindows)
        result.append(contentsOf: dynamicModalWindows)
        return result
    }

    // MARK: - Dynamic aux window management

    /// Register a dynamic aux window under a parent (platform-window or overlay).
    /// AppWindowsController owns the strong ref; parent holds a weak ref.
    func presentAuxiliaryWindow(_ aux: WindowController, in parent: WindowController) {
        dynamicAuxWindows.removeAll { $0.parentWindow == nil }
        dynamicAuxWindows.append(aux)
        parent.addAuxChild(aux)
    }

    /// Recursively dismiss an aux window and all its descendants.
    func dismissAuxiliaryWindow(_ aux: WindowController) {
        // Dismiss descendants first (DFS).
        let descendants = dynamicAuxWindows.filter { isDescendant($0, of: aux) }
        descendants.forEach { _remove(aux: $0) }
        _remove(aux: aux)
    }

    private func _remove(aux: WindowController) {
        aux.parentWindow?.removeAuxChild(aux)
        dynamicAuxWindows.removeAll { $0 === aux }
    }

    private func isDescendant(_ controller: WindowController,
                               of ancestor: WindowController) -> Bool {
        var current = controller.parentWindow
        while let p = current {
            if p === ancestor { return true }
            current = p.parentWindow
        }
        return false
    }

    // MARK: - Dynamic modal window management

    /// Returns false if a modal is already active in the parent (single-modal constraint).
    func presentModalWindow(_ modal: WindowController,
                            in parent: WindowController,
                            key: AnyHashable,
                            initiated: Bool = true) -> Bool {
        // Dedup: reject if the slot is already occupied.
        modalSlots = modalSlots.filter { $0.value.value != nil }
        if modalSlots[key]?.value != nil { return false }
        modalSlots[key] = AnyWeakObject(modal)

        dynamicModalWindows.append(modal)
        parent.addModalChild(modal, initiated: initiated)
        return true
    }

    func dismissModalWindow(_ modal: WindowController) {
        modal.parentWindow?.removeModalChild(modal)
        dynamicModalWindows.removeAll { $0 === modal }
        // Release modal slot.
        modalSlots = modalSlots.filter { $0.value.value != nil && $0.value.value !== modal }
    }

    func releaseModalSlot(key: AnyHashable) {
        modalSlots.removeValue(forKey: key)
    }

    // Synchronizes the controller registries against the current SceneList,
    // and applies runtime window config to all live controllers.
    // Must be called from outside an AG context; internally activates `graph`
    // to pull-evaluate the AG nodes.
    func syncWindowControllers(sceneListAttr: Attribute<[SceneList.Item]>?,
                               runtimeConfigAttr: Attribute<_RuntimeWindowConfig>? = nil,
                               in graph: AttributeGraph) {
        guard let attr = sceneListAttr else { return }

        AttributeGraph.$current.withValue(graph) {
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

            // Apply runtime window config to all live controllers.
            if let rc = runtimeConfigAttr?.value {
                for wc in allWindowControllers {
                    var cfg = wc.config
                    if let r = rc.activeFrameRate   { cfg.activeFrameInterval   = 1.0 / r }
                    if let r = rc.inactiveFrameRate { cfg.inactiveFrameInterval = 1.0 / r }
                    cfg.drawDebugInfo = rc.drawDebugInfo
                    wc.config = cfg
                }
            }
        }
    }
}
