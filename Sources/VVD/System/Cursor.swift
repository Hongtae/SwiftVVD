//
//  File: Cursor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public enum Cursor: Sendable {
    case arrow
    case cross
    case hand
    case iBeam
    case notAllowed
    case resizeLeftRight
    case resizeUpDown
    case resizeUpLeftDownRight
    case resizeUpRightDownLeft

    /// A raster cursor with a hotspot in top-left-origin image pixel coordinates.
    case custom(Image, hotSpot: CGPoint)

    public static func custom(_ image: Image) -> Cursor {
        .custom(image, hotSpot: .zero)
    }
}
