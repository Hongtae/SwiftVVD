//
//  File: WindowSceneConfiguration.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Creation-time window hints supplied by scene modifiers.
// These values are transferred with the scene item and remain distinct from
// runtime rendering configuration.
struct WindowSceneConfiguration {
    // Requested initial content size. nil means use the platform default.
    var defaultSize: CGSize? = nil

    // Requested initial position expressed as a UnitPoint on screen.
    // nil means let the platform decide.
    var defaultPosition: UnitPoint? = nil

    // Selects the command-menu presenter for this scene root window.
    // The root presenter resolves automatic only when it chooses its host.
    var commandMenuPresentationStyle: CommandMenuPresentationStyle = .automatic

    // Seeds the default host choice for transient presentation children.
    var defaultPresentationHostMode: PresentationHostMode = .overlay
}
