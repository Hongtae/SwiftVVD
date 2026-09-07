//
//  File: BezierTimingFunction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct BezierTimingFunction<T: BinaryFloatingPoint & Sendable>: Equatable, Sendable {
    var p1x: T
    var p1y: T
    var p2x: T
    var p2y: T
}
