//
//  File: Plane.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct Plane {
    public var a: Scalar
    public var b: Scalar
    public var c: Scalar
    public var d: Scalar

    public subscript(index: Int) -> Scalar {
        get {
            switch index {
            case 0: return self.a
            case 1: return self.b
            case 2: return self.c
            case 3: return self.d
            default:
                assertionFailure("Index out of range")
                break
            }
            return .zero
        }
        set (value) {
            switch index {
            case 0: self.a = value
            case 1: self.b = value
            case 2: self.c = value
            case 3: self.d = value
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    public init() {
        self.a = 0.0
        self.b = 0.0
        self.c = 0.0
        self.d = 0.0
    }

    public init(_ a: Scalar, _ b: Scalar, _ c: Scalar, _ d: Scalar) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
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
        Vector4.dot(self.vector4, Vector4(v, 1))
    }

    public func dot(_ v: Vector4) -> Scalar {
        Vector4.dot(self.vector4, v)
    }

    public var normal: Vector3 { Vector3(a, b, c) }
    public var vector4: Vector4 { Vector4(a, b, c, d) }

    public func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar {
        let distance = self.dot(origin)
        if distance == .zero { return .zero } // connected to the plane.

        let dir = direction.normalized()
        let denom = Vector3.dot(self.normal, dir)

        if abs(denom) > .ulpOfOne { // epsilon
            let t = -distance / denom
            if t >= .zero {
                return t
            }
        }
        return -1.0
    }
}
