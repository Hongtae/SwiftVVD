//
//  File: CG+Extensions.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics

public typealias CGFloat = CoreGraphics.CGFloat
public typealias CGPoint = CoreGraphics.CGPoint
public typealias CGSize = CoreGraphics.CGSize
public typealias CGRect = CoreGraphics.CGRect
#endif

public extension Vector2 {
    init(_ pt: CGPoint) {
        self.init(x: Scalar(pt.x), y: Scalar(pt.y))
    }

    init(_ s: CGSize) {
        self.init(x: Scalar(s.width), y: Scalar(s.height))
    }
}

public extension CGPoint {
    init(_ v: Vector2) {
        self.init(x: CGFloat(v.x), y: CGFloat(v.y))
    }

    func transformed(by m: Matrix2) -> Self {
        let x = self.x * CGFloat(m.m11) + self.y * CGFloat(m.m21)
        let y = self.x * CGFloat(m.m12) + self.y * CGFloat(m.m22)
        return Self(x: x, y: y)
    }

    mutating func transform(by: Matrix2) {
        self = self.transformed(by: by)
    }

    func transformed(by m: Matrix3) -> Self {
        let x = self.x * CGFloat(m.m11) + self.y * CGFloat(m.m21) + CGFloat(m.m31)
        let y = self.x * CGFloat(m.m12) + self.y * CGFloat(m.m22) + CGFloat(m.m32)
        var w = self.x * CGFloat(m.m13) + self.y * CGFloat(m.m23) + CGFloat(m.m33)
        assert(abs(w) != 0.0)
        w = 1.0 / w
        return Self(x: x * w, y: y * w)
    }

    mutating func transform(by: Matrix3) {
        self = self.transformed(by: by)
    }

    var magnitudeSquared: CGFloat   { self.x * self.x + self.y * self.y }
    var magnitude: CGFloat          { self.magnitudeSquared.squareRoot() }

    static func + (lhs: Self, rhs: Self) -> Self {
        return Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        return Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func -= (lhs: inout Self, rhs: Self) {
        lhs = lhs - rhs
    }

    static func * (lhs: Self, rhs: CGFloat) -> Self {
        return Self(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    static func *= (lhs: inout Self, rhs: CGFloat) {
        lhs = lhs * rhs
    }   
}

public extension CGSize {
    init(_ v: Vector2) {
        self.init(width: CGFloat(v.x), height: CGFloat(v.y))
    }

    static func * (lhs: Self, rhs: CGFloat) -> Self {
        return Self(width: lhs.width * rhs, height: lhs.height * rhs)
    }

    static func *= (lhs: inout Self, rhs: CGFloat) {
        lhs = lhs * rhs
    } 
}

public extension CGRect {
    func intersectsLine(_ pt1: CGPoint, _ pt2: CGPoint) -> Bool {
        if self.isEmpty { return false }
        if self.isInfinite { return true }

        let origin = CGPoint(x: self.minX, y: self.minY)
        let size = CGSize(width: self.width, height: self.height)

        let pos0 = CGPoint(x: (pt1.x - origin.x) / size.width, y: (pt1.y - origin.y) / size.height)
        let pos1 = CGPoint(x: (pt2.x - origin.x) / size.width, y: (pt2.y - origin.y) / size.height)

        // check each point located over each axis
        if pos0.x < 0.0 && pos1.x < 0.0     { return false }
        if pos0.x > 1.0 && pos1.x > 1.0     { return false }
        if pos0.y < 0.0 && pos1.y < 0.0     { return false }
        if pos0.y > 1.0 && pos1.y > 1.0     { return false }

        // check point inside of 0~1
        if pos0.x >= 0.0 && pos0.x <= 1.0 && pos0.y >= 0.0 && pos0.y <= 1.0 { return true }
        if pos1.x >= 0.0 && pos1.x <= 1.0 && pos1.y >= 0.0 && pos1.y <= 1.0 { return true }

        let dX = pos1.x - pos0.x    // x amount
        let dY = pos1.y - pos0.y    // y amount

        if abs(dX) == 0 { return true } // vertical aligned
        if abs(dY) == 0 { return true } // horizontal aligned

        // formula y = (dY * x) / dX + b
        let b = pos0.y - ((dY * pos0.x) / dX) // y-intercept (y for x = 0)
        if dX * dY > 0.0 {
            // positive slope
            let y0 = (-b * dX) / dY     // x-intercept (x for y = 0)
            if b > 1.0 || y0 > 1.0 {
                return false
            }
        } else {
            // negative slope
            let x1 = dY / dX + b        // y for x = 1
            if b < 0.0 || x1 > 1.0 {
                return false
            }
        }
        return true
    }

    func intersectsTriangle(_ pt1: CGPoint, _ pt2: CGPoint, _ pt3: CGPoint) -> Bool {
        if self.isEmpty { return false }
        if self.isInfinite { return true }

        let origin = CGPoint(x: self.minX, y: self.minY)
        let size = CGSize(width: self.width, height: self.height)

        let pos0 = CGPoint(x: (pt1.x - origin.x) / size.width, y: (pt1.y - origin.y) / size.height)
        let pos1 = CGPoint(x: (pt2.x - origin.x) / size.width, y: (pt2.y - origin.y) / size.height)
        let pos2 = CGPoint(x: (pt3.x - origin.x) / size.width, y: (pt3.y - origin.y) / size.height)

        // check each point located over each axis
        if pos0.x < 0.0 && pos1.x < 0.0 && pos2.x < 0.0 { return false }
        if pos0.x > 1.0 && pos1.x > 1.0 && pos2.x > 1.0 { return false }
        if pos0.y < 0.0 && pos1.y < 0.0 && pos2.y < 0.0 { return false }
        if pos0.y > 1.0 && pos1.y > 1.0 && pos2.y > 1.0 { return false }

        // check point inside of 0~1
        if pos0.x >= 0.0 && pos0.x <= 1.0 && pos0.y >= 0.0 && pos0.y <= 1.0 { return true }
        if pos1.x >= 0.0 && pos1.x <= 1.0 && pos1.y >= 0.0 && pos1.y <= 1.0 { return true }
        if pos2.x >= 0.0 && pos2.x <= 1.0 && pos2.y >= 0.0 && pos2.y <= 1.0 { return true }

        // all points located outside of rect (0~1,0~1).
        // test intersect with four line-segments of rect.
        let lineIntersection = { (v1: CGPoint, v2: CGPoint) -> Bool in
            var result = false
            if ((v1.x < 0.0 && v2.x < 0.0) || (v1.x > 1.0 && v2.x > 1.0) ||
                (v1.y < 0.0 && v2.y < 0.0) || (v1.y > 1.0 && v2.y > 1.0)) {            
            } else if (v1.x >= 0.0 && v1.x <= 1.0 && v1.y >= 0.0 && v1.y <= 1.0) {
                // v1 is inside
                result = true
            } else if (v2.x >= 0.0 && v2.x <= 1.0 && v2.y >= 0.0 && v2.y <= 1.0) {
                // v2 is inside
                result = true
            } else {
                let dx = v2.x - v1.x
                let dy = v2.y - v1.y
                // no intersection with vertical, horizontal (calculated above)
                if abs(dx) == 0.0 {
                    // vertical aligned
                } else if abs(dy) == 0.0 {
                    // horizontal aligned
                } else {
                    // formula y = a * x + b, (a = dy/dx)
                    let a = dy / dx
                    let b = v1.y - a * v1.x     // y-intercept (y for x = 0)
                    if a > 0 {                  // positive slope
                        let y0 = (-b) / a       // x-intercept (x for y = 0)
                        if b <= 1.0 && y0 <= 1.0 {
                            result = true
                        }
                    } else {
                        let x1 = a + b          // y for x = 1
                        if b >= 0.0 && x1 <= 1.0 {
                            result = true
                        }
                    }
                }
            }
            return result
        }
        if lineIntersection(pos0, pos1) { return true }
        if lineIntersection(pos1, pos2) { return true }
        if lineIntersection(pos2, pos0) { return true }

        // test intersect with point of triangle are included.
        // using cross-products for triangle direction (+z or -z),
        // (0,0),(0,1),(1,1),(1,0) and each points makes triangle direction for
        // intersection if direction is matched.
        let triangleOrientation = { (v1: CGPoint, v2: CGPoint, v3: CGPoint) -> Int in
            if (v1.x * (v2.y - v3.y) + v2.x * (v3.y - v1.y) + v3.x * (v1.y - v2.y)) > 0.0 {
                return 1
            }
            return -1
        }
        if (abs(triangleOrientation(pos0, pos1, CGPoint(x: 0.0, y: 0.0)) +
                triangleOrientation(pos1, pos2, CGPoint(x: 0.0, y: 0.0)) +
                triangleOrientation(pos2, pos0, CGPoint(x: 0.0, y: 0.0))) == 3) {
            return true
        }
        if (abs(triangleOrientation(pos0, pos1, CGPoint(x: 0.0, y: 1.0)) +
                triangleOrientation(pos1, pos2, CGPoint(x: 0.0, y: 1.0)) +
                triangleOrientation(pos2, pos0, CGPoint(x: 0.0, y: 1.0))) == 3) {
            return true
        }
        if (abs(triangleOrientation(pos0, pos1, CGPoint(x: 1.0, y: 1.0)) +
                triangleOrientation(pos1, pos2, CGPoint(x: 1.0, y: 1.0)) +
                triangleOrientation(pos2, pos0, CGPoint(x: 1.0, y: 1.0))) == 3) {
            return true
        }
        if (abs(triangleOrientation(pos0, pos1, CGPoint(x: 1.0, y: 0.0)) +
                triangleOrientation(pos1, pos2, CGPoint(x: 1.0, y: 0.0)) +
                triangleOrientation(pos2, pos0, CGPoint(x: 1.0, y: 0.0))) == 3) {
            return true
        }
        return false
    }
}

//#if !(os(iOS) || targetEnvironment(macCatalyst))
#if os(macOS) || os(Linux) || os(Windows) || os(Android)
public extension AffineTransform2 {
    init(_ t: AffineTransform) {
        self.init(linear: Matrix2(Scalar(t.m11), Scalar(t.m12),
                                  Scalar(t.m21), Scalar(t.m22)),
                  origin: Vector2(Scalar(t.tX), Scalar(t.tY)))
    }
}

public extension AffineTransform {
    init(_ t: AffineTransform2) {
        self.init(m11: CGFloat(t.matrix2.m11), m12: CGFloat(t.matrix2.m12),
                  m21: CGFloat(t.matrix2.m21), m22: CGFloat(t.matrix2.m22),
                  tX: CGFloat(t.translation.x), tY: CGFloat(t.translation.y))
    }
}
#endif
