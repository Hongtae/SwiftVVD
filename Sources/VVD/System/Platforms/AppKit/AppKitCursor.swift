//
//  File: AppKitCursor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
@_implementationOnly import AppKit

@MainActor
func makeAppKitCursor(_ cursor: Cursor) -> NSCursor? {
    switch cursor {
    case .arrow:
        return NSCursor.arrow
    case .text:
        return NSCursor.iBeam
    case .wait:
        // AppKit does not expose an application-selectable busy cursor.
        return NSCursor.arrow
    case .crosshair:
        return NSCursor.crosshair
    case .progress:
        // Keep interaction available when no public progress cursor exists.
        return NSCursor.arrow
    case .resizeUpLeftDownRight:
        return NSCursor.frameResize(position: .topLeft, directions: .all)
    case .resizeUpRightDownLeft:
        return NSCursor.frameResize(position: .topRight, directions: .all)
    case .resizeLeftRight:
        return NSCursor.columnResize
    case .resizeUpDown:
        return NSCursor.rowResize
    case .move:
        return NSCursor.openHand
    case .notAllowed:
        return NSCursor.operationNotAllowed
    case .pointingHand:
        return NSCursor.pointingHand
    case let .custom(image, hotSpot):
        guard image.width > 0,
              image.height > 0,
              let data = image.encode(format: .png),
              let nativeImage = NSImage(data: data) else {
            return nil
        }

        nativeImage.size = NSSize(
            width: image.width,
            height: image.height
        )
        return NSCursor(
            image: nativeImage,
            hotSpot: NSPoint(
                x: clampedCursorHotSpot(hotSpot.x, extent: image.width),
                y: clampedCursorHotSpot(hotSpot.y, extent: image.height)
            )
        )
    }
}

private func clampedCursorHotSpot(
    _ value: CGFloat,
    extent: Int
) -> CGFloat {
    guard value.isFinite else { return 0 }
    return value.rounded().clamp(min: 0, max: CGFloat(extent - 1))
}

#endif // ENABLE_APPKIT
