//
//  File: SceneConfiguration.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// SceneConfiguration — creation-time window hints supplied by scene modifiers.
//
// Distinct from WindowContext.Configuration, which controls runtime behaviour
// (frame rate, background colour, etc.) and can change at any time.
// SceneConfiguration values are read once by AppWindowsController when the
// WindowController is first created, then stored on WindowController for
// later use (e.g. when makeWindow() opens the platform window).
struct SceneConfiguration {
    // Requested initial content size. nil means use the platform default.
    var defaultSize: CGSize? = nil

    // Requested initial position expressed as a UnitPoint on screen.
    // (.center = screen centre, .topLeading = top-left corner, etc.)
    // nil means let the platform decide.
    var defaultPosition: UnitPoint? = nil
}
