//
//  File: TextLineMetrics.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Primary-font line inputs in rendering coordinates, independent of fallback glyph metrics.
struct FontLineMetrics: Equatable, Sendable {
    let ascent: CGFloat
    let height: CGFloat
    let heightWithoutSystemLeading: CGFloat
    let leading: CGFloat

    init(metrics: ResolvedFontMetrics, pointSize: CGFloat, isTextStyle: Bool, scale: CGFloat) {
        let ascent = floor(metrics.ascender + 0.5)
        let descent = -metrics.descender
        let height = isTextStyle ? metrics.ascender + descent : ascent + floor(descent + 0.5)
        var adjustedHeight = height
        if isTextStyle, pointSize <= 21, (ascent - height) + descent > 0.0001 {
            adjustedHeight = ascent + ceil(descent)
        }
        self.ascent = ascent * scale
        self.height = (height > 0 ? height : 0.0001) * scale
        self.heightWithoutSystemLeading = (adjustedHeight > 0 ? adjustedHeight : 0.0001) * scale
        self.leading = isTextStyle ? metrics.leading * scale : 0
    }

    func height(usesSystemLeading: Bool) -> CGFloat {
        usesSystemLeading && leading != 0 ? height : heightWithoutSystemLeading
    }

    func leading(usesSystemLeading: Bool, usesNegativeLeading: Bool) -> CGFloat {
        if leading < 0 { return usesNegativeLeading ? leading : 0 }
        return usesSystemLeading ? leading : 0
    }
}

/// Call-local line extents; positive leading and baseline offsets have separate contributions.
struct TextLineMetrics {
    private var lower: CGFloat = 0
    private var upper: CGFloat = 0
    private var tail: CGFloat = 0

    mutating func add(ascent: CGFloat, height: CGFloat, leading: CGFloat, baselineOffset: CGFloat) {
        var low = ascent - height
        var high = ascent + min(leading, 0)
        lower = min(lower, low)
        upper = max(upper, high)
        low += baselineOffset
        high += baselineOffset
        lower = min(lower, low)
        upper = max(upper, high)
        tail = max(tail, max(leading, 0) - low)
    }

    var height: CGFloat { upper - lower }
    var baseline: CGFloat { upper }
    func spacing(requested: CGFloat) -> CGFloat { max(requested, tail + lower) }
}
