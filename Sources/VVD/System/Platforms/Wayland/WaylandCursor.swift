//
//  File: WaylandCursor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND
import Foundation
import Glibc
@preconcurrency
import Wayland

private final class WaylandCustomCursorBuffer {
    let buffer: OpaquePointer
    let width: Int32
    let height: Int32
    let hotSpotX: Int32
    let hotSpotY: Int32

    init?(
        sharedMemory: OpaquePointer,
        image: Image,
        hotSpot: CGPoint
    ) {
        let width = image.width
        let height = image.height
        guard width > 0,
              height > 0,
              width <= Int(Int32.max),
              height <= Int(Int32.max),
              width <= Int.max / 4 / height else {
            return nil
        }

        let byteCount = width * height * 4
        guard byteCount <= Int(Int32.max),
              let source = image.resample(
                  width: width,
                  height: height,
                  format: .rgba8,
                  interpolation: .bilinear
              ),
              source.data.count >= byteCount else {
            return nil
        }

        let name = "/swiftvvd-cursor-\(Foundation.UUID().uuidString)"
        let fileDescriptor = name.withCString {
            shm_open($0, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard fileDescriptor >= 0 else { return nil }
        name.withCString { _ = shm_unlink($0) }
        defer { Glibc.close(fileDescriptor) }

        guard ftruncate(fileDescriptor, off_t(byteCount)) == 0,
              let mapping = mmap(
                  nil,
                  byteCount,
                  PROT_READ | PROT_WRITE,
                  MAP_SHARED,
                  fileDescriptor,
                  0
              ),
              mapping != UnsafeMutableRawPointer(bitPattern: -1) else {
            return nil
        }
        defer { munmap(mapping, byteCount) }

        source.data.withUnsafeBytes { sourceBytes in
            let source = sourceBytes.bindMemory(to: UInt8.self)
            let destination = mapping.assumingMemoryBound(to: UInt8.self)
            for pixel in 0..<(width * height) {
                let offset = pixel * 4
                let alpha = source[offset + 3]
                destination[offset] = UInt8(
                    (Int(source[offset + 2]) * Int(alpha) + 127) / 255
                )
                destination[offset + 1] = UInt8(
                    (Int(source[offset + 1]) * Int(alpha) + 127) / 255
                )
                destination[offset + 2] = UInt8(
                    (Int(source[offset]) * Int(alpha) + 127) / 255
                )
                destination[offset + 3] = alpha
            }
        }

        guard let pool = wl_shm_create_pool(
            sharedMemory,
            fileDescriptor,
            Int32(byteCount)
        ) else {
            return nil
        }
        defer { wl_shm_pool_destroy(pool) }

        guard let buffer = wl_shm_pool_create_buffer(
            pool,
            0,
            Int32(width),
            Int32(height),
            Int32(width * 4),
            WL_SHM_FORMAT_ARGB8888.rawValue
        ) else {
            return nil
        }

        self.buffer = buffer
        self.width = Int32(width)
        self.height = Int32(height)
        self.hotSpotX = Self.clampedHotSpot(hotSpot.x, extent: width)
        self.hotSpotY = Self.clampedHotSpot(hotSpot.y, extent: height)
    }

    deinit {
        wl_buffer_destroy(buffer)
    }

    private static func clampedHotSpot(
        _ value: CGFloat,
        extent: Int
    ) -> Int32 {
        guard value.isFinite else { return 0 }
        return Int32(value.rounded().clamp(min: 0, max: CGFloat(extent - 1)))
    }
}

final class WaylandCursorManager {
    private let sharedMemory: OpaquePointer
    private let surface: OpaquePointer
    private var themes: [Int32: OpaquePointer] = [:]
    private var customBuffer: WaylandCustomCursorBuffer?

    init?(compositor: OpaquePointer, sharedMemory: OpaquePointer) {
        guard let surface = wl_compositor_create_surface(compositor) else {
            return nil
        }
        self.sharedMemory = sharedMemory
        self.surface = surface
    }

    deinit {
        customBuffer = nil
        for theme in themes.values {
            wl_cursor_theme_destroy(theme)
        }
        wl_surface_destroy(surface)
    }

    @discardableResult
    func apply(
        _ cursor: Cursor?,
        visible: Bool,
        pointer: OpaquePointer,
        serial: UInt32,
        scale: Int32
    ) -> Bool {
        guard visible else {
            wl_pointer_set_cursor(pointer, serial, nil, 0, 0)
            customBuffer = nil
            return true
        }

        let cursor = cursor ?? .arrow
        switch cursor {
        case let .custom(image, hotSpot):
            guard let buffer = WaylandCustomCursorBuffer(
                sharedMemory: sharedMemory,
                image: image,
                hotSpot: hotSpot
            ) else {
                return false
            }
            wl_surface_set_buffer_scale(surface, 1)
            wl_pointer_set_cursor(
                pointer,
                serial,
                surface,
                buffer.hotSpotX,
                buffer.hotSpotY
            )
            wl_surface_attach(surface, buffer.buffer, 0, 0)
            wl_surface_damage(surface, 0, 0, buffer.width, buffer.height)
            wl_surface_commit(surface)
            customBuffer = buffer
            return true

        default:
            let scale = max(scale, 1)
            guard let image = themedImage(for: cursor, scale: scale) else {
                return false
            }
            wl_surface_set_buffer_scale(surface, scale)
            wl_pointer_set_cursor(
                pointer,
                serial,
                surface,
                image.hotSpotX / scale,
                image.hotSpotY / scale
            )
            wl_surface_attach(surface, image.buffer, 0, 0)
            wl_surface_damage(
                surface,
                0,
                0,
                image.width / scale,
                image.height / scale
            )
            wl_surface_commit(surface)
            customBuffer = nil
            return true
        }
    }

    private func theme(for scale: Int32) -> OpaquePointer? {
        if let theme = themes[scale] {
            return theme
        }
        let baseSize = ProcessInfo.processInfo.environment["XCURSOR_SIZE"]
            .flatMap(Int32.init)
            .flatMap { $0 > 0 ? $0 : nil } ?? 24
        guard baseSize <= Int32.max / scale,
              let theme = wl_cursor_theme_load(
                  nil,
                  baseSize * scale,
                  sharedMemory
              ) else {
            return nil
        }
        themes[scale] = theme
        return theme
    }

    private func themedImage(
        for cursor: Cursor,
        scale: Int32
    ) -> (
        buffer: OpaquePointer,
        width: Int32,
        height: Int32,
        hotSpotX: Int32,
        hotSpotY: Int32
    )? {
        guard let theme = theme(for: scale) else { return nil }
        for name in Self.themeNames(for: cursor) {
            let themedCursor = name.withCString {
                wl_cursor_theme_get_cursor(theme, $0)
            }
            guard let themedCursor,
                  themedCursor.pointee.image_count > 0,
                  let images = themedCursor.pointee.images,
                  let image = images[0],
                  let buffer = wl_cursor_image_get_buffer(image) else {
                continue
            }
            return (
                buffer,
                Int32(image.pointee.width),
                Int32(image.pointee.height),
                Int32(image.pointee.hotspot_x),
                Int32(image.pointee.hotspot_y)
            )
        }
        return nil
    }

    static func themeNames(for cursor: Cursor) -> [String] {
        switch cursor {
        case .arrow:
            ["default", "left_ptr", "arrow"]
        case .text:
            ["text", "xterm"]
        case .wait:
            ["wait", "watch"]
        case .crosshair:
            ["crosshair", "cross"]
        case .progress:
            ["progress", "left_ptr_watch", "half-busy", "wait", "watch"]
        case .resizeUpLeftDownRight:
            ["nwse-resize", "size_fdiag", "bd_double_arrow"]
        case .resizeUpRightDownLeft:
            ["nesw-resize", "size_bdiag", "fd_double_arrow"]
        case .resizeLeftRight:
            ["ew-resize", "size_hor", "sb_h_double_arrow"]
        case .resizeUpDown:
            ["ns-resize", "size_ver", "sb_v_double_arrow"]
        case .move:
            ["move", "all-scroll", "fleur", "size_all"]
        case .notAllowed:
            ["not-allowed", "crossed_circle", "forbidden"]
        case .pointingHand:
            ["pointer", "hand2", "hand1"]
        case .custom:
            []
        }
    }
}

#endif // ENABLE_WAYLAND
