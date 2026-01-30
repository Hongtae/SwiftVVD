//
//  File: CGTypes.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

#if canImport(CoreGraphics)
//import CoreGraphics
@_exported import CoreGraphics

public typealias CGFloat = CoreGraphics.CGFloat
public typealias CGPoint = CoreGraphics.CGPoint
public typealias CGSize = CoreGraphics.CGSize
public typealias CGRect = CoreGraphics.CGRect

public typealias CGAffineTransform = CoreGraphics.CGAffineTransform
public typealias CGLineCap = CoreGraphics.CGLineCap
public typealias CGLineJoin = CoreGraphics.CGLineJoin

extension CGAffineTransform {
    public var matrix3: Matrix3 {
        Matrix3(a, b, 0.0, c, d, 0.0, tx, ty, 1.0)
    }
}

#else
public typealias CGFloat = Foundation.CGFloat
public typealias CGPoint = Foundation.CGPoint
public typealias CGSize = Foundation.CGSize
public typealias CGRect = Foundation.CGRect

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

extension Float: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= Float(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}

extension Double: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= rhs }
    public var magnitudeSquared: Double { self * self }
}

extension CGFloat: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self = self * rhs }
    public var magnitudeSquared: Double { self * self }
}

extension CGPoint: Animatable {
    public typealias AnimatableData = AnimatablePair<CGFloat, CGFloat>
    public var animatableData: AnimatableData {
        @inlinable get { return .init(x, y) }
        @inlinable set { (x, y) = newValue[] }
    }
}

extension CGSize: Animatable {
    public typealias AnimatableData = AnimatablePair<CGFloat, CGFloat>
    public var animatableData: AnimatableData {
        @inlinable get { return .init(width, height) }
        @inlinable set { (width, height) = newValue[] }
    }
}

extension CGRect: Animatable {
    public typealias AnimatableData = AnimatablePair<CGPoint.AnimatableData, CGSize.AnimatableData>
    public var animatableData: AnimatableData {
        @inlinable get {
            return .init(origin.animatableData, size.animatableData)
        }
        @inlinable set {
            (origin.animatableData, size.animatableData) = newValue[]
        }
    }
}

extension Vector2 {
    public func applying(_ t: CGAffineTransform) -> Vector2 {
        let x = self.x * Scalar(t.a) + self.y * Scalar(t.c) + Scalar(t.tx)
        let y = self.x * Scalar(t.b) + self.y * Scalar(t.d) + Scalar(t.ty)
        return Vector2(x: x, y: y)
    }
}
