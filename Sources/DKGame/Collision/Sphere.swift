//
//  File: Sphere.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Sphere {
    public let center: Vector3
    public let radius: Scalar

    public init() {
        self.center = .zero
        self.radius = -Scalar.greatestFiniteMagnitude
    }

    public init(center: Vector3, radius: Scalar) {
        self.center = center
        self.radius = radius
    }

    public var isValid: Bool { radius >= 0.0 }

    // bigger sphere, union of s1, s2 merged sphere.
    public static func union(_ s1: Self, _ s2: Self) -> Self? {
        if s1.isValid && s2.isValid {
            let distance = (s1.center - s2.center).length
            if s1.radius - s2.radius >= distance {
                // s1 includes s2
                return s1
            } else if s2.radius - s1.radius >= distance {
                // s2 includes s1
                return s2
            } else {
                // new sphere's radius: distance between two sphere centers + each radius/2
                let r = (distance + s1.radius + s2.radius) * 0.5

                // new sphere's center: move from s2 to s1 with offset (new sphere's radius - radius of s2)
                let center = (s1.center - s2.center).normalized() * (r - s2.radius) + s2.center
                return Sphere(center: center, radius: r)
            }

        } else if s1.isValid {
            return s1
        } else if s2.isValid {
            return s2
        }
        // both are invalid.
        return nil
    }

    // smaller sphere, intersection between s1, s2.
    public static func intersection(_ s1: Self, _ s2: Self) -> Self? {
        if s1.isValid && s2.isValid {
            let distance = (s1.center - s2.center).length
            if distance <= s1.radius + s2.radius {
                let radius = (s1.radius + s2.radius - distance) * 0.5
                let center = s1.center + (s1.center - s2.center).normalized() * (s1.radius - radius)

                return Sphere(center: center, radius: radius)
            }
        }
        return nil
    }

    public func isPointInside(_ pos: Vector3) -> Bool {
        return (pos - center).lengthSquared <= (radius * radius)
    }

    public var volume: Scalar {
        if self.isValid {
            // 4/3 PI * R cubed
            return (4.0 / 3.0) * radius * radius * radius * Scalar.pi
        }
        return 0.0
    }

    public func rayTest(start: Vector3, direction dir: Vector3) -> Vector3? {
        if self.isValid {
            let l = self.center - start  // from ray begin to sphere center
            let d = dir.normalized()
            
            let s = Vector3.dot(l, d)
            let s2 = s * s
            let l2 = Vector3.dot(l, l)  // l-vector length^2
            let r2 = self.radius * self.radius

            if s < 0 && l2 > r2 {
                // sphere located behind of ray-begin, no-intersection
                return nil
            }

            let m2 = l2 - s2  // calculate intersect length
            if m2 > r2 {
                // intersect length^2 is bigger than radius^2, no-intersection
                return nil
            }

            var t: Scalar = 0.0
            let q = sqrt(r2 - m2)
            if l2 > r2 {
                // ray begins outside of sphere, length of intersection (t = s-q)
                t = s - q
            } else {
                // ray begins inside of sphere, length of intersection (t = s+q)
                t = s + q
            }

            if t >= 0.0 {
                return start + d * t
            }
        }
        return nil
    }
}
