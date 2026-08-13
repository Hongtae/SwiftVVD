//
//  File: Screen.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation


public struct ScreenID: Hashable, Sendable {
    public let rawValue: UInt64
}

public struct ScreenInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public static let zero = ScreenInsets()

    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

public protocol Screen: Identifiable where ID == ScreenID {
    /// Runtime identity for matching Window.screen against Application.screens.
    ///
    /// The source is platform-specific: CGDirectDisplayID, HMONITOR, UIScreen
    /// object identity, wl_output name, or another stable display token.
    var id: ScreenID { get }

    /// Full display rectangle in the platform's external window coordinate space.
    ///
    /// The coordinate space and unit match `Window.origin` and
    /// `Window.windowFrame`. AppKit uses points with a top-left origin after
    /// coordinate conversion, while Win32 uses screen pixels.
    var frame: CGRect { get }

    /// Visible display rectangle for normal window placement.
    ///
    /// This excludes the menu bar, Dock, taskbar, or similar reserved system
    /// UI. It uses the same external coordinate space and unit as `frame`.
    var visibleFrame: CGRect { get }

    /// Edge insets for fullscreen content safety, in the platform screen unit.
    ///
    /// These are areas where important fullscreen content can be obscured or
    /// hard to interact with, such as a notch, rounded display corners, or
    /// system gesture areas. This is not the same as visibleFrame.
    var safeAreaInsets: ScreenInsets { get }

    /// Scale factor used to convert screen-space points to backing pixels.
    ///
    /// For normal window/content rendering, pixelSize = pointSize * scaleFactor.
    /// AppKit maps this to backingScaleFactor; UIKit maps this to UIScreen.scale.
    var scaleFactor: CGFloat { get }

    /// Pixel resolution of the current OS display mode.
    ///
    /// This is the fullscreen rendering size in pixels, not a logical point
    /// size. On scaled displays this can differ from both frame.size *
    /// scaleFactor and the physical panel's fixed native resolution.
    var displayModeResolution: CGSize { get }
}
