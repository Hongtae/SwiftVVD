//
//  File: Cursor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public enum Cursor: Sendable {
    /// The standard arrow cursor.
    case arrow

    /// A text-selection cursor, usually rendered as an I-beam.
    case text

    /// A cursor indicating that the application is not currently interactive.
    case wait

    /// A precision-selection crosshair.
    case crosshair

    /// A cursor indicating background work while interaction remains available.
    case progress

    /// A diagonal resize cursor pointing up-left and down-right.
    case resizeUpLeftDownRight

    /// A diagonal resize cursor pointing up-right and down-left.
    case resizeUpRightDownLeft

    /// A horizontal resize cursor pointing left and right.
    case resizeLeftRight

    /// A vertical resize cursor pointing up and down.
    case resizeUpDown

    /// A four-direction cursor indicating that an item can be moved.
    case move

    /// A cursor indicating that the requested operation is not permitted.
    case notAllowed

    /// A pointing hand used for links and other directly selectable items.
    case pointingHand

    /// A raster cursor with a hotspot in top-left-origin image pixel coordinates.
    case custom(Image, hotSpot: CGPoint)

    public static func custom(_ image: Image) -> Cursor {
        .custom(image, hotSpot: .zero)
    }
}
