//
//  File: CGTypes.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

#if canImport(CoreGraphics)
import CoreGraphics

public typealias CGAffineTransform = CoreGraphics.CGAffineTransform
public typealias CGLineCap = CoreGraphics.CGLineCap
public typealias CGLineJoin = CoreGraphics.CGLineJoin

#else
public typealias CGAffineTransform = AffineTransform

public enum CGLineCap: Int32, Sendable {
    case butt = 0
    case round = 1
    case square = 2
}

public enum CGLineJoin: Int32, Sendable {
    case miter = 0
    case round = 1
    case bevel = 2
}

#endif

extension CGFloat: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self = self * rhs }
    public var magnitudeSquared: Double { self * self }
}
