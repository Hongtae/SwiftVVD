//
//  File: Bezier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
    a * (1.0 - t) + b * t
}

struct QuadraticBezier {
    let p0: CGPoint
    let p1: CGPoint
    let p2: CGPoint

    func split(_ t: Double) -> (Self, Self) {
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

    var lengthOfPointSegments: Double {
        let a = (p0 - p1).magnitude
        let b = (p1 - p2).magnitude
        let c = (p2 - p0).magnitude
        return (a + b + c)
    }

    func approximateLength(subdivide: Int = 0) -> Double {
        var sumOfPointSegments = 0.0
        self.subdivide(subdivide).forEach {
            sumOfPointSegments += $0.lengthOfPointSegments
        }
        return sumOfPointSegments * 0.5
    }

    func interpolate(_ t: Double) -> CGPoint {
        let t2 = t * t
        let u = 1.0 - t
        let u2 = u * u
        return (p0 * u2) + (p1 * u * t * 2) + (p2 * t2)
    }
}

struct CubicBezier {
    let p0: CGPoint
    let p1: CGPoint
    let p2: CGPoint
    let p3: CGPoint

    func split(_ t: Double) -> (Self, Self) {
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

    var lengthOfPointSegments: Double {
        let a = (p0 - p1).magnitude
        let b = (p1 - p2).magnitude
        let c = (p2 - p3).magnitude
        let d = (p3 - p0).magnitude
        return (a + b + c + d)
    }

    func approximateLength(subdivide: Int = 0) -> Double {
        var sumOfPointSegments = 0.0
        self.subdivide(subdivide).forEach {
            sumOfPointSegments += $0.lengthOfPointSegments
        }
        return sumOfPointSegments * 0.5
    }

    func interpolate(_ t: Double) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t
        let u = 1.0 - t
        let u2 = u * u
        let u3 = u2 * u
        return (p0 * u3) + (p1 * t * u2 * 3) + (p2 * t2 * u * 3) + (p3 * t3)
    }
}
