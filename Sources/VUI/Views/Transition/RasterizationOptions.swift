//
//  File: RasterizationOptions.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Raster output hints carried by content-transition state into display-list interpolation.
struct RasterizationOptions: Equatable {
    // Bitfield for layer, color, alpha, and drawable behavior needed by the render path.
    struct Flags: OptionSet, Equatable, Hashable, Sendable {
        let rawValue: UInt32

        static let isAccelerated = Flags(rawValue: 1 << 0)
        static let isOpaque = Flags(rawValue: 1 << 1)
        static let rendersAsynchronously = Flags(rawValue: 1 << 2)
        static let prefersDisplayCompositing = Flags(rawValue: 1 << 3)
        static let rendersFirstFrameAsync = Flags(rawValue: 1 << 4)
        static let allowsPackedDrawable = Flags(rawValue: 1 << 5)
        static let alphaOnly = Flags(rawValue: 1 << 6)
        static let requiresLayer = Flags(rawValue: 1 << 7)
        static let rgbaContext = Flags(rawValue: 1 << 8)
        static let highRes = Flags(rawValue: 1 << 9)
        static let fixedPixelFormat = Flags(rawValue: 1 << 10)
        static let defaultFlags: Flags = [.allowsPackedDrawable, .requiresLayer]

        mutating func set(_ flag: Flags, to value: Bool) {
            if value {
                insert(flag)
            } else {
                remove(flag)
            }
        }
    }

    var rbColorMode: Int32
    var colorMode: ColorRenderingMode
    var allowedDynamicRange: Image.DynamicRange?
    var flags: Flags
    var maxDrawableCount: Int8

    init(
        colorMode: ColorRenderingMode = .nonLinear,
        allowedDynamicRange: Image.DynamicRange? = nil,
        flags: Flags = .defaultFlags
    ) {
        self.rbColorMode = -1
        self.colorMode = colorMode
        self.allowedDynamicRange = allowedDynamicRange
        self.flags = flags
        self.maxDrawableCount = 3
    }

    var isAccelerated: Bool {
        get { flags.contains(.isAccelerated) }
        set { flags.set(.isAccelerated, to: newValue) }
    }

    var isOpaque: Bool {
        get { flags.contains(.isOpaque) }
        set { flags.set(.isOpaque, to: newValue) }
    }

    var rendersAsynchronously: Bool {
        get { flags.contains(.rendersAsynchronously) }
        set { flags.set(.rendersAsynchronously, to: newValue) }
    }

    var prefersDisplayCompositing: Bool {
        get { flags.contains(.prefersDisplayCompositing) }
        set { flags.set(.prefersDisplayCompositing, to: newValue) }
    }

    var rendersFirstFrameAsynchronously: Bool {
        get { flags.contains(.rendersFirstFrameAsync) }
        set { flags.set(.rendersFirstFrameAsync, to: newValue) }
    }

    var allowsPackedDrawable: Bool {
        get { flags.contains(.allowsPackedDrawable) }
        set { flags.set(.allowsPackedDrawable, to: newValue) }
    }

    var requiresLayer: Bool {
        get { flags.contains(.requiresLayer) }
        set { flags.set(.requiresLayer, to: newValue) }
    }

    var fixedPixelFormat: Bool {
        get { flags.contains(.fixedPixelFormat) }
        set { flags.set(.fixedPixelFormat, to: newValue) }
    }

    var alphaOnly: Bool {
        get { flags.contains(.alphaOnly) }
        set { flags.set(.alphaOnly, to: newValue) }
    }

    var resolvedColorMode: Int32 {
        if rbColorMode != -1 {
            return rbColorMode
        }

        switch colorMode {
        case .nonLinear:
            return alphaOnly ? 9 : 0
        case .linear:
            return alphaOnly ? 10 : 1
        case .extendedLinear:
            return alphaOnly ? 10 : 2
        }
    }
}
