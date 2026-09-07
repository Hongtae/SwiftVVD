//
//  File: ResolvedGradient.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct ResolvedGradient: Equatable, Sendable {
    struct Stop: Equatable, Sendable {
        var color: Color.Resolved
        var location: CGFloat
        var interpolation: BezierTimingFunction<Float>?
    }

    enum ColorSpace: UInt8, Hashable, Sendable {
        case device, linear, perceptual
    }

    var stops: [Stop]
    var colorSpace: ColorSpace
    var headroom: Float?
}
