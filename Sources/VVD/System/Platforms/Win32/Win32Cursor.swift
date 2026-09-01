//
//  File: Win32Cursor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_WIN32
import Foundation
import WinSDK

private func systemCursor(_ identifier: UInt) -> HCURSOR? {
    let resource = UnsafePointer<WCHAR>(bitPattern: identifier)
    return LoadCursorW(nil, resource)
}

func win32CreateARGBBitmap(
    from image: Image,
    width: Int? = nil,
    height: Int? = nil,
    templateColor: COLORREF? = nil
) -> HBITMAP? {
    let targetWidth = max(width ?? image.width, 1)
    let targetHeight = max(height ?? image.height, 1)
    guard let source = image.resample(
        width: targetWidth,
        height: targetHeight,
        format: .rgba8,
        interpolation: .bilinear
    ) else {
        return nil
    }

    var bitmapInfo = BITMAPINFO()
    bitmapInfo.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
    bitmapInfo.bmiHeader.biWidth = LONG(targetWidth)
    // A negative height creates a top-down DIB matching VVD image coordinates.
    bitmapInfo.bmiHeader.biHeight = -LONG(targetHeight)
    bitmapInfo.bmiHeader.biPlanes = 1
    bitmapInfo.bmiHeader.biBitCount = 32
    bitmapInfo.bmiHeader.biCompression = DWORD(BI_RGB)
    bitmapInfo.bmiHeader.biSizeImage = DWORD(targetWidth * targetHeight * 4)

    var destination: UnsafeMutableRawPointer?
    guard let bitmap = CreateDIBSection(
        nil,
        &bitmapInfo,
        UINT(DIB_RGB_COLORS),
        &destination,
        nil,
        0
    ), let destination else {
        return nil
    }

    let templateRed = UInt8(truncatingIfNeeded: templateColor ?? 0)
    let templateGreen = UInt8(truncatingIfNeeded: (templateColor ?? 0) >> 8)
    let templateBlue = UInt8(truncatingIfNeeded: (templateColor ?? 0) >> 16)

    source.data.withUnsafeBytes { sourceBytes in
        let source = sourceBytes.bindMemory(to: UInt8.self)
        let destination = destination.assumingMemoryBound(to: UInt8.self)
        for pixel in 0..<(targetWidth * targetHeight) {
            let sourceOffset = pixel * 4
            let destinationOffset = pixel * 4
            let alpha = source[sourceOffset + 3]
            let red = templateColor == nil
                ? source[sourceOffset]
                : templateRed
            let green = templateColor == nil
                ? source[sourceOffset + 1]
                : templateGreen
            let blue = templateColor == nil
                ? source[sourceOffset + 2]
                : templateBlue

            destination[destinationOffset] = UInt8(
                (Int(blue) * Int(alpha) + 127) / 255
            )
            destination[destinationOffset + 1] = UInt8(
                (Int(green) * Int(alpha) + 127) / 255
            )
            destination[destinationOffset + 2] = UInt8(
                (Int(red) * Int(alpha) + 127) / 255
            )
            destination[destinationOffset + 3] = alpha
        }
    }
    return bitmap
}

private func createCustomCursor(
    image: Image,
    hotSpot: CGPoint
) -> HCURSOR? {
    let width = max(image.width, 1)
    let height = max(image.height, 1)
    guard let colorBitmap = win32CreateARGBBitmap(
        from: image,
        width: width,
        height: height
    ) else {
        return nil
    }
    defer { DeleteObject(colorBitmap) }

    let maskStride = ((width + 15) / 16) * 2
    let maskBytes = [UInt8](
        repeating: 0,
        count: maskStride * height
    )
    let maskBitmap = maskBytes.withUnsafeBytes {
        CreateBitmap(
            Int32(width),
            Int32(height),
            1,
            1,
            $0.baseAddress
        )
    }
    guard let maskBitmap else { return nil }
    defer { DeleteObject(maskBitmap) }

    var info = ICONINFO()
    info.fIcon = false
    info.xHotspot = clampedCursorHotSpot(hotSpot.x, extent: width)
    info.yHotspot = clampedCursorHotSpot(hotSpot.y, extent: height)
    info.hbmMask = maskBitmap
    info.hbmColor = colorBitmap
    return CreateIconIndirect(&info)
}

private func clampedCursorHotSpot(
    _ value: CGFloat,
    extent: Int
) -> DWORD {
    guard value.isFinite else { return 0 }
    return DWORD(value.rounded().clamp(min: 0, max: CGFloat(extent - 1)))
}

final class Win32CursorHandle {
    let handle: HCURSOR
    private let ownsHandle: Bool

    init?(_ cursor: Cursor) {
        let result: (HCURSOR?, Bool) = switch cursor {
        case .arrow:
            (systemCursor(32512), false) // IDC_ARROW
        case .text:
            (systemCursor(32513), false) // IDC_IBEAM
        case .wait:
            (systemCursor(32514), false) // IDC_WAIT
        case .crosshair:
            (systemCursor(32515), false) // IDC_CROSS
        case .progress:
            (systemCursor(32650), false) // IDC_APPSTARTING
        case .resizeUpLeftDownRight:
            (systemCursor(32642), false) // IDC_SIZENWSE
        case .resizeUpRightDownLeft:
            (systemCursor(32643), false) // IDC_SIZENESW
        case .resizeLeftRight:
            (systemCursor(32644), false) // IDC_SIZEWE
        case .resizeUpDown:
            (systemCursor(32645), false) // IDC_SIZENS
        case .move:
            (systemCursor(32646), false) // IDC_SIZEALL
        case .notAllowed:
            (systemCursor(32648), false) // IDC_NO
        case .pointingHand:
            (systemCursor(32649), false) // IDC_HAND
        case let .custom(image, hotSpot):
            (createCustomCursor(image: image, hotSpot: hotSpot), true)
        }
        guard let handle = result.0 else { return nil }
        self.handle = handle
        self.ownsHandle = result.1
    }

    deinit {
        if ownsHandle {
            DestroyCursor(handle)
        }
    }
}
#endif // ENABLE_WIN32
