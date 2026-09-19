//
//  File: UIKitScreen.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_UIKIT
import Foundation
internal import UIKit

struct UIKitScreen: Screen {
    let id: ScreenID
    let screen: UIScreen

    var frame: CGRect {
        screen.bounds
    }

    var visibleFrame: CGRect {
        screen.bounds
    }

    var safeAreaInsets: ScreenInsets {
        let insets = screen.overscanCompensationInsets
        return ScreenInsets(top: insets.top,
                            left: insets.left,
                            bottom: insets.bottom,
                            right: insets.right)
    }

    var scaleFactor: CGFloat {
        screen.scale
    }

    var displayModeResolution: CGSize {
        if let mode = screen.currentMode {
            return mode.size
        }

        return CGSize(width: screen.bounds.width * screen.scale,
                      height: screen.bounds.height * screen.scale)
    }

    init(_ screen: UIScreen) {
        self.id = ScreenID(rawValue: UInt64(UInt(bitPattern: Unmanaged.passUnretained(screen).toOpaque())))
        self.screen = screen
    }
}

#endif //if ENABLE_UIKIT
