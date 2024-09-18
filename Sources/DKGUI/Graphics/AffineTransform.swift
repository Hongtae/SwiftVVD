//
//  File: AffineTransform.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

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

    public init() {
        self.a = 1.0
        self.b = 0.0
        self.c = 0.0
        self.d = 1.0
        self.tx = 0.0
        self.ty = 0.0
    }

    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public init(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ tx: CGFloat, _ ty: CGFloat) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

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

    public var isIdentity: Bool { self == Self.identity }
    
    public static var identity: Self { .init(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0) }

    public func concatenating(_ t2: Self) -> Self {
        let a = self.a * t2.a + self.b * t2.c
        let b = self.a * t2.b + self.b * t2.d
        let c = self.c * t2.a + self.d * t2.c
        let d = self.c * t2.b + self.d * t2.d
        let tx = self.tx * t2.a + self.ty * t2.c + t2.tx
        let ty = self.tx * t2.b + self.ty * t2.d + t2.ty
        return .init(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    public func inverted() -> Self {
        let det = self.a * self.d - self.b * self.c
        if abs(det) > .ulpOfOne {
            let inv = 1.0 / det
            let a = self.d * inv
            let b = -self.b * inv
            let c = -self.c * inv
            let d = self.a * inv
            let tx = -(self.tx * a + self.ty * c)
            let ty = -(self.tx * b + self.ty * d)
            return .init(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
        }
        // cannot be inverted, return unchanged.
        return self
    }

    public func rotated(by angle: CGFloat) -> Self {
        Self(rotationAngle: angle).concatenating(self)
    }

    public func scaledBy(x sx: CGFloat, y sy: CGFloat) -> Self {
        Self(scaleX: sx, y: sy).concatenating(self)
    }

    public func translatedBy(x tx: CGFloat, y ty: CGFloat) -> Self {
        Self(translationX: tx, y: ty).concatenating(self)
    }
}

extension AffineTransform {
    public var matrix3: Matrix3 {
        Matrix3(a, b, 0.0, c, d, 0.0, tx, ty, 1.0)
    }
}

extension CGPoint {
    public func applying(_ t: AffineTransform) -> CGPoint {
        let x = self.x * t.a + self.y * t.c + t.tx
        let y = self.x * t.b + self.y * t.d + t.ty
        return CGPoint(x: x, y: y)
    }
}

extension CGSize {
    public func applying(_ t: AffineTransform) -> CGSize {
        let w = self.width * t.a + self.height * t.c
        let h = self.width * t.b + self.height * t.d
        return CGSize(width: w, height: h)
    }
}

extension CGRect {
    public func applying(_ t: AffineTransform) -> CGRect {
        let pts = [
            CGPoint(x: self.minX, y: self.minY).applying(t),
            CGPoint(x: self.minX, y: self.maxY).applying(t),
            CGPoint(x: self.maxX, y: self.minY).applying(t),
            CGPoint(x: self.maxX, y: self.maxX).applying(t),
        ]
        let minX = pts.min { a, b in a.x < b.x }!.x
        let maxX = pts.max { a, b in a.x < b.x }!.x
        let minY = pts.min { a, b in a.y < b.y }!.y
        let maxY = pts.max { a, b in a.y < b.y }!.y
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
