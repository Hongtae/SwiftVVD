//
//  File: CGTypes.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

#if canImport(CoreGraphics)
import CoreGraphics

public typealias CGAffineTransform = CoreGraphics.CGAffineTransform
public typealias CGLineCap = CoreGraphics.CGLineCap
public typealias CGLineJoin = CoreGraphics.CGLineJoin

extension CGAffineTransform {
    public var matrix3: Matrix3 {
        Matrix3(a, b, 0.0, c, d, 0.0, tx, ty, 1.0)
    }
}

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

extension Vector2 {
    public func applying(_ t: CGAffineTransform) -> Vector2 {
        let x = self.x * Scalar(t.a) + self.y * Scalar(t.c + t.tx)
        let y = self.x * Scalar(t.b) + self.y * Scalar(t.d + t.ty)
        return Vector2(x: x, y: y)
    }
}
