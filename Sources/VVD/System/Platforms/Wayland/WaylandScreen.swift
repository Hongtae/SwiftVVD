//
//  File: WaylandScreen.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND
import Foundation

struct WaylandScreen: Screen {
    let id: ScreenID
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaInsets: ScreenInsets
    let scaleFactor: CGFloat
    let displayModeResolution: CGSize

    init(id: ScreenID, frame: CGRect, scaleFactor: CGFloat, displayModeResolution: CGSize) {
        self.id = id
        self.frame = frame
        self.visibleFrame = frame
        self.safeAreaInsets = .zero
        self.scaleFactor = scaleFactor
        self.displayModeResolution = displayModeResolution
    }
}

#endif //if ENABLE_WAYLAND
