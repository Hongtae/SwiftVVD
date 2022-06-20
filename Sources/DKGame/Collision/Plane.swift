//
//  File: Plane.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct Plane {
    public let a: Scalar
    public let b: Scalar
    public let c: Scalar
    public let d: Scalar

    public init() {
        self.a = 0.0
        self.b = 0.0
        self.c = 0.0
        self.d = 0.0
    }

    // plane from triangle
    public init(_ v1: Vector3, _ v2: Vector3, _ v3: Vector3) {
        let n = Vector3.cross(v2 - v1, v3 - v1).normalized()
        self.a = n.x
        self.b = n.y
        self.c = n.z
        self.d = -Vector3.dot(n, v1)
    }

    // plane from normal, point
    public init(normal n: Vector3, point p: Vector3) {
        self.a = n.x
        self.b = n.y
        self.c = n.z
        self.d = -Vector3.dot(n, p)
    }

    public func dot(_ v: Vector3) -> Scalar {
        return a * v.x + b * v.y + c * v.z + d
    }

    public func dot(_ v: Vector4) -> Scalar {
        return a * v.x + b * v.y + c * v.z + d * v.w
    }

    public var normal: Vector3 { Vector3(a, b, c) }

    public func rayTest(start rayBegin: Vector3, direction: Vector3) -> Vector3? {
        let len = self.dot(rayBegin)
        if len == 0 { return rayBegin } // connected to the plane.

        let dir = direction.normalized()
        let denom = Vector3.dot(self.normal, dir)

        if abs(denom) > .ulpOfOne { // epsilon
            let t = -len / denom
            if t >= 0.0 {
                return rayBegin + dir * t
            }
        }
        return nil
    }
}
