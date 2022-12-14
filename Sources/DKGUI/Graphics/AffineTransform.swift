//
//  File: AffineTransform.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

/*-------
  a  b  0
  c  d  0
  tx ty 1
  -------*/

public struct AffineTransform: Equatable, Sendable {
    public var a: CGFloat
    public var b: CGFloat
    public var c: CGFloat
    public var d: CGFloat
    public var tx: CGFloat
    public var ty: CGFloat

    public init(rotationAngle r: CGFloat) {
        let cosR = cos(r)
        let sinR = sin(r)
        self.a = cosR
        self.b = sinR
        self.c = -sinR
        self.d = cosR
        self.tx = 0.0
        self.ty = 0.0
    }

    public init(scaleX x: CGFloat, y: CGFloat) {
        self.a = x
        self.b = 0.0
        self.c = 0.0
        self.d = y
        self.tx = 0.0
        self.ty = 0.0
    }

    public init(translationX x: CGFloat, y: CGFloat) {
        self.a = 1.0
        self.b = 0.0
        self.c = 0.0
        self.d = 1.0
        self.tx = x
        self.ty = y
    }

    public init() {
        self.a = 1.0
        self.b = 0.0
        self.c = 0.0
        self.d = 1.0
        self.tx = 0.0
        self.ty = 0.0
    }

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = CGFloat(a)
        self.b = CGFloat(b)
        self.c = CGFloat(c)
        self.d = CGFloat(d)
        self.tx = CGFloat(tx)
        self.ty = CGFloat(ty)
    }

    public init(a: Float, b: Float, c: Float, d: Float, tx: Float, ty: Float) {
        self.a = CGFloat(a)
        self.b = CGFloat(b)
        self.c = CGFloat(c)
        self.d = CGFloat(d)
        self.tx = CGFloat(tx)
        self.ty = CGFloat(ty)
    }

    public var isIdentity: Bool { self == AffineTransform.identity }
    
    public static var identity: AffineTransform { .init(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0) }

    public func concatenating(_ t2: AffineTransform) -> AffineTransform {
        let a = self.a * t2.a + self.b * t2.c
        let b = self.a * t2.b + self.b * t2.d
        let c = self.c * t2.a + self.d * t2.c
        let d = self.c * t2.b + self.d * t2.d
        let tx = self.tx * t2.a + self.ty * t2.c + t2.tx
        let ty = self.tx * t2.b + self.ty * t2.d + t2.ty
        return .init(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    public func inverted() -> CGAffineTransform {
        var a: CGFloat = 1.0
        var b: CGFloat = 0.0
        var c: CGFloat = 0.0
        var d: CGFloat = 1.0
        let det = self.a * self.d - self.b * self.c
        if det.isZero == false {
            let inv = 1.0 / det
            a = self.d * inv
            b = -self.b * inv
            c = -self.c * inv
            d = self.a * inv
        }
        let tx = -(self.tx * a + self.ty * c)
        let ty = -(self.tx * b + self.ty * d)
        return .init(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    public func rotated(by angle: CGFloat) -> CGAffineTransform {
        self.concatenating(.init(rotationAngle: angle))
    }

    public func scaledBy(x sx: CGFloat, y sy: CGFloat) -> CGAffineTransform {
        self.concatenating(.init(scaleX: sx, y: sy))
    }

    public func translatedBy(x tx: CGFloat, y ty: CGFloat) -> CGAffineTransform {
        self.concatenating(.init(translationX: tx, y: ty))
    }
}

#if canImport(CoreGraphics)
import CoreGraphics
public typealias CGAffineTransform = CoreGraphics.CGAffineTransform
#else
public typealias CGAffineTransform = AffineTransform
#endif
