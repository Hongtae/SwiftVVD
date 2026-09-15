//
//  File: AttributedTextMetrics.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension NSAttributedString {
    struct Metrics: Equatable {
        var size: CGSize
        var scale: CGFloat
        var firstBaseline: CGFloat
        var lastBaseline: CGFloat
        var baselineAdjustment: CGFloat
        var requestedWidth: CGFloat
        var numberOfLines: UInt?
        var hasTruncatedRanges: Bool

        // Equality describes the measured extent and scale. Cache entries must
        // still preserve the other fields and their count-request eligibility.
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.size == rhs.size && lhs.scale == rhs.scale
        }

        mutating func update(layoutMargins: EdgeInsets, pixelLength: CGFloat) {
            size.width = (layoutMargins.leading + layoutMargins.trailing) + size.width
            size.height = (layoutMargins.top + layoutMargins.bottom) + size.height
            let rawFirstBaseline = layoutMargins.top + firstBaseline
            firstBaseline = (rawFirstBaseline / pixelLength).rounded() * pixelLength
            baselineAdjustment = firstBaseline - rawFirstBaseline
            lastBaseline = ceil((layoutMargins.top + lastBaseline + baselineAdjustment)
                / pixelLength) * pixelLength
        }
    }
}
