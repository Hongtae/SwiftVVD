//
//  File: Bezier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

struct QuadraticBezier {
    let p0: CGPoint     // start point
    let p1: CGPoint     // control point
    let p2: CGPoint     // end point

    func split(_ t: CGFloat) -> (Self, Self) {
        let ab = lerp(p0, p1, t)
        let bc = lerp(p1, p2, t)
        let p = lerp(ab, bc, t)

        return (Self(p0: p0, p1: ab, p2: p), Self(p0: p, p1: bc, p2: p2))
    }

    func subdivide(_ subdivide: Int) -> [Self] {
        var curves: [Self] = []
        curves.append(self)
        var subdivide = subdivide
        while subdivide > 0 {
            var divided: [Self] = []
            divided.reserveCapacity(curves.count * 2)
            curves.forEach {
                let c = $0.split(0.5)
                divided.append(c.0)
                divided.append(c.1)
            }
            curves = divided
            subdivide = subdivide - 1
        }
        return curves
    }

    var lengthOfPointSegments: CGFloat {
        let a = (p0 - p1).magnitude
        let b = (p1 - p2).magnitude
        let c = (p2 - p0).magnitude
        return (a + b + c)
    }

    func approximateLength(subdivide: Int = 0) -> CGFloat {
        var sumOfPointSegments = 0.0
        self.subdivide(subdivide).forEach {
            sumOfPointSegments += $0.lengthOfPointSegments
        }
        return sumOfPointSegments * 0.5
    }

    func interpolate(_ t: CGFloat) -> CGPoint {
        let t2 = t * t
        let u = 1.0 - t
        let u2 = u * u
        return (p0 * u2) + (p1 * u * t * 2) + (p2 * t2)
    }

    func interpolate(_ t: CGPoint) -> CGPoint {
        let t2 = t * t
        let u = CGPoint(x: 1.0 - t.x, y: 1.0 - t.y)
        let u2 = u * u
        return (p0 * u2) + (p1 * u * t * 2) + (p2 * t2)
    }

    func tangent(_ t: CGFloat) -> CGPoint {
        // B'(t) = 2*(1-t)(p1-p0) + 2*(p2-p1)*t
        let u = 1.0 - t
        return ((p1 - p0) * u + (p2 - p1) * t) * 2
    }

    func tangent(_ t: CGPoint) -> CGPoint {
        let u = CGPoint(x: 1.0 - t.x, y: 1.0 - t.y)
        return ((p1 - p0) * u + (p2 - p1) * t) * 2
    }

    var boundingBox: CGRect {
        var bbMin = CGPoint.minimum(p0, p2)
        var bbMax = CGPoint.minimum(p0, p2)

        if p1.x < bbMin.x || p1.x > bbMax.x || p1.y < bbMin.y || p1.y > bbMax.y {
            let p = (p0 - p1) / (p0 - p1 * 2 + p2)
            let t = CGPoint.minimum(.maximum(p, .zero), CGPoint(x: 1, y: 1))

            let q = interpolate(t)

            bbMin = .minimum(bbMin, q)
            bbMax = .maximum(bbMax, q)
        }
        return CGRect(x: bbMin.x, y: bbMin.y, width: bbMax.x - bbMax.x, height: bbMax.y - bbMin.y)
    }
}

struct CubicBezier {
    let p0: CGPoint     // start point
    let p1: CGPoint     // control point 1
    let p2: CGPoint     // control point 2
    let p3: CGPoint     // end point

    func split(_ t: CGFloat) -> (Self, Self) {
        let ab = lerp(p0, p1, t)
        let bc = lerp(p1, p2, t)
        let cd = lerp(p2, p3, t)

        let abbc = lerp(ab, bc, t)
        let bccd = lerp(bc, cd, t)

        let p = lerp(abbc, bccd, t)

        return (Self(p0: p0, p1: ab, p2: abbc, p3: p),
                Self(p0: p, p1: bccd, p2: cd, p3: p3))
    }

    func subdivide(_ subdivide: Int) -> [Self] {
        var curves: [Self] = []
        curves.append(self)
        var subdivide = subdivide
        while subdivide > 0 {
            var divided: [Self] = []
            divided.reserveCapacity(curves.count * 2)
            curves.forEach {
                let c = $0.split(0.5)
                divided.append(c.0)
                divided.append(c.1)
            }
            curves = divided
            subdivide = subdivide - 1
        }
        return curves
    }

    var lengthOfPointSegments: CGFloat {
        let a = (p0 - p1).magnitude
        let b = (p1 - p2).magnitude
        let c = (p2 - p3).magnitude
        let d = (p3 - p0).magnitude
        return (a + b + c + d)
    }

    func approximateLength(subdivide: Int = 0) -> CGFloat {
        var sumOfPointSegments = 0.0
        self.subdivide(subdivide).forEach {
            sumOfPointSegments += $0.lengthOfPointSegments
        }
        return sumOfPointSegments * 0.5
    }

    func interpolate(_ t: CGFloat) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t
        let u = 1.0 - t
        let u2 = u * u
        let u3 = u2 * u
        return (p0 * u3) + (p1 * t * u2 * 3) + (p2 * t2 * u * 3) + (p3 * t3)
    }

    func interpolate(_ t: CGPoint) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t
        let u = CGPoint(x: 1.0 - t.x, y: 1.0 - t.y)
        let u2 = u * u
        let u3 = u2 * u
        return (p0 * u3) + (p1 * t * u2 * 3) + (p2 * t2 * u * 3) + (p3 * t3)
    }

    func tangent(_ t: CGFloat) -> CGPoint {
        // dP(t) / dt =  -3(1-t)^2 * P0 + 3(1-t)^2 * P1 - 6t(1-t) * P1 - 3t^2 * P2 + 6t(1-t) * P2 + 3t^2 * P3 
        let t2 = t * t
        let u = 1.0 - t
        let u2 = u * u
        return (p0 * u2 * -3) + (p1 * u2 * 3) - (p1 * u * t * 6) - (p2 * t2 * 3) + (p2 * u * t * 6) + (p3 * u2 * 3)
    }

    func tangent(_ t: CGPoint) -> CGPoint {
        let t2 = t * t
        let u = CGPoint(x: 1.0 - t.x, y: 1.0 - t.y)
        let u2 = u * u
        return (p0 * u2 * -3) + (p1 * u2 * 3) - (p1 * u * t * 6) - (p2 * t2 * 3) + (p2 * u * t * 6) + (p3 * u2 * 3)
    }

    var boundingBox: CGRect {
        //X = At^3 + Bt^2 + Ct + D
        //where A,B,C,D: (D = p0)
        let a = p3 - p2 * 3 + p1 * 3 - p0
        let b = p2 * 3 - p1 * 6 + p0 * 3
        let c = p1 * 3 - p0 * 3
        let determinant = b * b - a * c * 4

        let extremes = {
            (a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat) -> [CGFloat] in
            if d < 0 { return [] }
            if a == 0 { return [ -c / b ] }
            if d == 0 { return [ -b / ( a * 2) ] }
            let s = sqrt(d)
            return [
                (s - b) / ( a * 2),
                -(s + b) / ( a * 2)
            ]
        }

        let curve = {
            (p0: CGFloat, p1: CGFloat, p2: CGFloat, p3: CGFloat, t: CGFloat) -> CGFloat in
            let t2 = t * t
            let t3 = t2 * t
            return (p3 - 3 * p2 + 3 * p1 - p0) * t3
            + (3 * p2 - 6 * p1 + 3 * p0) * t2
            + (3 * p1 - 3 * p0) * t
            + (p0)
        }

        var minX = min(p0.x, p2.x)
        var minY = min(p0.y, p2.y)
        var maxX = max(p0.x, p2.x)
        var maxY = max(p0.y, p2.y)

        extremes(a.x, b.x, c.x, determinant.x).forEach { t in
            if t > 0 && t < 1 {
                let x = curve(p0.x, p1.x, p2.x, p3.x, t)
                minX = min(x, minX)
                maxX = max(x, maxX)
            }
        }
        extremes(a.y, b.y, c.y, determinant.y).forEach { t in
            if t > 0 && t < 1 {
                let y = curve(p0.y, p1.y, p2.y, p3.y, t)
                minY = min(y, minY)
                maxY = max(y, maxY)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
