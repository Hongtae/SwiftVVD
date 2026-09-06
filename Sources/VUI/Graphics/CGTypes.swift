//
//  File: CGTypes.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
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
public typealias CGContext = CoreGraphics.CGContext
public typealias CGImage = CoreGraphics.CGImage
public typealias CGLineCap = CoreGraphics.CGLineCap
public typealias CGLineJoin = CoreGraphics.CGLineJoin

extension CGAffineTransform {
    @inlinable
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

// Empty compatibility placeholders for APIs that accept CoreGraphics image/context types when CoreGraphics is unavailable.
public struct CGContext: Hashable {}
public struct CGImage: Hashable, Sendable {}

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

public struct CGVector: Hashable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat

    public init(dx: CGFloat, dy: CGFloat) {
        self.dx = dx
        self.dy = dy
    }

    public static let zero = CGVector(dx: 0.0, dy: 0.0)
}

#endif

extension Float: VectorArithmetic {
    @inlinable
    public mutating func scale(by rhs: Double) { self *= Float(rhs) }
    @inlinable
    public var magnitudeSquared: Double { Double(self * self) }
}

extension Double: VectorArithmetic {
    @inlinable
    public mutating func scale(by rhs: Double) { self *= rhs }
    @inlinable
    public var magnitudeSquared: Double { self * self }
}

extension CGFloat: VectorArithmetic {
    @inlinable
    public mutating func scale(by rhs: Double) { self = self * rhs }
    @inlinable
    public var magnitudeSquared: Double { self * self }
}

extension Double: Animatable {
    public typealias AnimatableData = Double
}

extension CGFloat: Animatable {
    public typealias AnimatableData = CGFloat
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
    @inlinable
    public func applying(_ t: CGAffineTransform) -> Vector2 {
        let x = self.x * Scalar(t.a) + self.y * Scalar(t.c) + Scalar(t.tx)
        let y = self.x * Scalar(t.b) + self.y * Scalar(t.d) + Scalar(t.ty)
        return Vector2(x: x, y: y)
    }
}
