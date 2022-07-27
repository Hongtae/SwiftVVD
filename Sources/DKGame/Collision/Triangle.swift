//
//  File: Sphere.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct Triangle {
    public let p0: Vector3
    public let p1: Vector3
    public let p2: Vector3

    public init(_ p0: Vector3, _ p1: Vector3, _ p2: Vector3) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
    }

    public var area: Scalar {
        let ab = p1 - p0
        let ac = p2 - p0
        return Vector3.cross(ab, ac).length * Scalar(0.5)
    }

    public var aabb: AABB {
        let minimum = Vector3.minimum(p0, Vector3.minimum(p1, p2))
        let maximum = Vector3.maximum(p0, Vector3.maximum(p1, p2))
        return AABB(min: minimum, max: maximum)
    }

    /// RayTestResult: ray intersection test result with t,u,v
    /// parameter t: the distance from ray-origin to the triangle plane
    ///              intersection point p = ray-origin + ray-dir * t
    /// parameter u,v: barycentric coordinates of intersection point inside the triangle.
    ///                w = 1 - u - v.
    public typealias RayTestResult = (t: Scalar, u: Scalar, v: Scalar)

    public func rayIntersectionTestFront(rayOrigin origin: Vector3, dir: Vector3) -> RayTestResult? {
        // intersection algorithm based on Tomas Akenine-Möller
        // ray test with front face of triangle.
        // if intersected, return value t,u,v where t is the distance
        // to the plane in which the triangle lies, and u,v represents 
        // barycentric coordinates inside the triangle.

        let edge1 = p1 - p0
        let edge2 = p2 - p0
        // calculate determinant
        let p = Vector3.cross(dir, edge2)
        let det = Vector3.dot(edge1, p)

        // if determinant is near zero, ray lies in plane of triangle
        if det < .ulpOfOne {
            return nil
        }

        // calculate distance from p0 to ray origin
        let s = origin - p0
        // calculate U parameter and test bounds
        let u = Vector3.dot(s, p)
        if u < .zero || u > det {
            return nil
        }

        let q = Vector3.cross(s, edge1)
        // calculate V parameter and test bounds
        let v = Vector3.dot(dir, q)
        if v < .zero || u + v > det {
            return nil
        }

        // calculate t, (distance from origin, intersects triangle)
        let t = Vector3.dot(edge2, q)
        let invDet = Scalar(1.0) / det
        return RayTestResult(t: t * invDet, u: u * invDet, v: v * invDet)
    }

    public func rayIntersectionTestFrontAndBack(rayOrigin origin: Vector3, dir: Vector3) -> RayTestResult? {
        // intersection algorithm based on Tomas Akenine-Möller
        // ray test with both faces (without culling) of triangle.
        // if intersected, return value with t,u,v where t is the distance
        // to the plane in which the triangle lies, and u,v represents 
        // barycentric coordinates inside the triangle.

        let edge1 = p1 - p0
        let edge2 = p2 - p0
        // calculate determinant
        let p = Vector3.cross(dir, edge2)
        let det = Vector3.dot(edge1, p)

        // if determinant is near zero, ray lies in plane of triangle
        if det > -.ulpOfOne && det < .ulpOfOne {
            return nil
        }

        let invDet = Scalar(1.0) / det

        // calculate distance from p0 to ray origin
        let s = origin - p0
        // calculate U parameter and test bounds
        let u = Vector3.dot(s, p) * invDet
        if u < .zero || u > Scalar(1.0) {
            return nil
        }

        let q = Vector3.cross(s, edge1)
        // calculate V parameter and test bounds
        let v = Vector3.dot(dir, q) * invDet
        if v < .zero || u + v > Scalar(1.0) {
            return nil
        }

        // calculate t, (distance from origin, intersects triangle)
        let t = Vector3.dot(edge2, q) * invDet
        return RayTestResult(t: t, u: u, v: v)
    }
}
