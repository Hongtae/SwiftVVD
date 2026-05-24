//
//  File: AppKitScreen.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
@_implementationOnly import AppKit

struct AppKitScreen: Screen {
    let id: ScreenID
    let screen: NSScreen

    var frame: CGRect {
        screen.frame
    }

    var visibleFrame: CGRect {
        screen.visibleFrame
    }

    var safeAreaInsets: ScreenInsets {
        let insets = screen.safeAreaInsets
        return ScreenInsets(top: insets.top,
                            left: insets.left,
                            bottom: insets.bottom,
                            right: insets.right)
    }

    var scaleFactor: CGFloat {
        screen.backingScaleFactor
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        if #available(macOS 26.0, *), let displayID = screen.cgDirectDisplayID {
            guard displayID != kCGNullDirectDisplay else {
                return nil
            }
            return displayID
        }

        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard displayID != kCGNullDirectDisplay else {
            return nil
        }
        return displayID
    }

    private var displayID: CGDirectDisplayID? {
        Self.displayID(for: screen)
    }

    private static func screenID(for screen: NSScreen) -> ScreenID {
        if let displayID = displayID(for: screen) {
            return ScreenID(rawValue: UInt64(displayID))
        }

        let pointer = UInt64(UInt(bitPattern: Unmanaged.passUnretained(screen).toOpaque()))
        return ScreenID(rawValue: (UInt64(1) << 63) | pointer)
    }

    var displayModeResolution: CGSize {
        guard let displayID,
              let mode = CGDisplayCopyDisplayMode(displayID) else {
            return .zero
        }
        return CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
    }

    init(_ screen: NSScreen) {
        self.id = Self.screenID(for: screen)
        self.screen = screen
    }
}

#endif //if ENABLE_APPKIT
