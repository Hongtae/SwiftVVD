//
//  File: AABB.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct AABB {
    public var min: Vector3
    public var max: Vector3

    public var center: Vector3 { (min + max) * 0.5 }
    public var extents: Vector3 { (max - min) }
    public var isNull: Bool { max.x < min.x || max.y < min.y || max.z < min.z }

    public static let null = AABB(min: Vector3(Scalar.greatestFiniteMagnitude,
                                               Scalar.greatestFiniteMagnitude,
                                               Scalar.greatestFiniteMagnitude),
                                  max: Vector3(-Scalar.greatestFiniteMagnitude,
                                               -Scalar.greatestFiniteMagnitude,
                                               -Scalar.greatestFiniteMagnitude))

    public init() {
        self = Self.null
    }

    public init(min: Vector3, max: Vector3) {
        self.min = min
        self.max = max
    }

    public init(center: Vector3, halfExtents: Vector3) {
        self.min = center - halfExtents
        self.max = center + halfExtents
    }

    public mutating func expand(_ point: Vector3) {
        if self.isNull {
            min = Vector3.minimum(min, point)
            max = Vector3.maximum(max, point)
        } else {
            min = point
            max = point
        }
    }

    public mutating func expand(_ points: Vector3...) {
        for pt in points {
            self.expand(pt)
        }
    }

    public func applying(_ transform: Matrix3) -> AABB {
        if self.isNull { return .null }
        var aabb = AABB()
        let verts: [Vector3] = [
            Vector3(self.min.x, self.min.y, self.min.z),
            Vector3(self.max.x, self.min.y, self.min.z),
            Vector3(self.min.x, self.max.y, self.min.z),
            Vector3(self.max.x, self.max.y, self.min.z),
            Vector3(self.min.x, self.min.y, self.max.z),
            Vector3(self.max.x, self.min.y, self.max.z),
            Vector3(self.min.x, self.max.y, self.max.z),
            Vector3(self.max.x, self.max.y, self.max.z),
        ]
        verts.forEach { aabb.expand($0.applying(transform)) }
        return aabb
    }

    public func applying(_ transform: Matrix4) -> AABB {
        if self.isNull { return .null }
        var aabb = AABB()
        let verts: [Vector3] = [
            Vector3(self.min.x, self.min.y, self.min.z),
            Vector3(self.max.x, self.min.y, self.min.z),
            Vector3(self.min.x, self.max.y, self.min.z),
            Vector3(self.max.x, self.max.y, self.min.z),
            Vector3(self.min.x, self.min.y, self.max.z),
            Vector3(self.max.x, self.min.y, self.max.z),
            Vector3(self.min.x, self.max.y, self.max.z),
            Vector3(self.max.x, self.max.y, self.max.z),
        ]
        verts.forEach { aabb.expand($0.applying(transform, w: 1.0)) }
        return aabb
    }

    public mutating func apply(_ transform: Matrix3) {
        self = self.applying(transform)
    }

    public mutating func apply(_ transform: Matrix4) {
        self = self.applying(transform)
    }

    public func intersection(_ other: AABB) -> AABB {
        if self.isNull || other.isNull {
            return .null
        }
        return .init(min: Vector3.maximum(self.min, other.min),
                     max: Vector3.minimum(self.max, other.max))
    }

    public func combining(_ other: AABB) -> AABB {
        var aabb = self
        aabb.combine(other)
        return aabb
    }

    public mutating func combine(_ other: AABB) {
        if other.isNull == false {
            if self.isNull {
                self.min = other.min
                self.max = other.max
            } else {
                self.min = Vector3.minimum(self.min, other.min)
                self.max = Vector3.maximum(self.max, other.max)
            }
        }
    }

    public func intersects(_ other: AABB) -> Bool {
        intersection(other).isNull == false
    }

    public func rayTest(rayOrigin origin: Vector3, direction dir: Vector3) -> Scalar {
        // algorithm based on: http://www.codercorner.com/RayAABB.cpp
        // Original code by Andrew Woo, from "Graphics Gems", Academic Press, 1990

        var inside = true
        var maxT = Vector3(-1, -1, -1)
        var coord = Vector3.zero

        for i in 0...2 {
            if origin[i] < self.min[i] {
                coord[i] = self.min[i]
                inside = false
                if dir[i] != .zero {
                    maxT[i] = (self.min[i] - origin[i]) / dir[i]
                }
            } else if origin[i] > self.max[i] {
                coord[i] = self.max[i]
                inside = false
                if dir[i] != .zero {
                    maxT[i] = (self.max[i] - origin[i]) / dir[i]
                }
            }
        }
        if inside {
            return .zero
        }
        // calculate maxT to find intersection point.
        var plane = 0
        if maxT.y > maxT[plane] { plane = 1 }   // plane of axis Y
        if maxT.z > maxT[plane] { plane = 2 }   // plane of axis Z

        if maxT[plane] < .zero {
            return -1.0
        }

        for i in 0...2 {
            if i != plane {
                coord[i] = origin[i] + maxT[plane] * dir[i]

                // if coord[i] < self.min[i] - .ulpOfOne || coord[i] > self.max[i] + .ulpOfOne {
                //     return -1.0
                // }

                if coord[i] < self.min[i] || coord[i] > self.max[i] {
                    return -1.0
                }
            }
        }
        return (coord - origin).magnitude
    }

    public func overlapTest(_ plane: Plane) -> Bool {
        if isNull { return false }

        var vmin = Vector3(), vmax = Vector3()
        for n in 0...2 {
            if plane[n] > .zero {
                vmin[n] = self.min[n]
                vmax[n] = self.max[n]
            } else {
                vmin[n] = self.max[n]
                vmax[n] = self.max[n]
            }
        }
        if plane.dot(vmax) < .zero { return false } // box is below plane
        if plane.dot(vmin) > .zero { return false } // box is above plane
        return true
    }

    public func overlapTest(_ tri: Triangle) -> Bool {
        // algorithm based on Tomas Möller
        // https://cs.lth.se/tomas-akenine-moller/
        // https://fileadmin.cs.lth.se/cs/Personal/Tomas_Akenine-Moller/code/

        if isNull { return false }

        // use separating axis theorem to test overlap between triangle and box 
        // need to test for overlap in these directions: 
        // 1) the {x,y,z}-directions (actually, since we use the AABB of the triangle 
        //    we do not even need to test these) 
        // 2) normal of the triangle 
        // 3) crossproduct(edge from tri, {x,y,z}-directin) 
        //    this gives 3x3=9 more tests 

        let boxcenter = self.center
        let boxhalfsize = self.extents * 0.5

        let axisTest = { (a: Scalar, b: Scalar, fa: Scalar, fb: Scalar,
                          v1: Vector3, v2: Vector3, idx1: Int, idx2: Int) in
            let p1 = a * v1[idx1] + b * v1[idx2]
            let p2 = a * v2[idx1] + b * v2[idx2]
            let min, max : Scalar
            if p1 > p2 {
                min = p2
                max = p1
            } else {
                min = p1
                max = p2
            }
            let rad = fa * boxhalfsize[idx1] + fb * boxhalfsize[idx2]
            if min > rad || max < -rad { return false }
            return true
        }

        // move everything so that the boxcenter is in (0,0,0)
        let v0 = tri.p0 - boxcenter
        let v1 = tri.p1 - boxcenter
        let v2 = tri.p2 - boxcenter

        let _X = 0, _Y = 1, _Z = 2
        let axisTest_X01 = { a, b, fa, fb in axisTest(a, -b, fa, fb, v0, v2, _Y, _Z) }
        let axisTest_X2  = { a, b, fa, fb in axisTest(a, -b, fa, fb, v0, v1, _Y, _Z) }
        let axisTest_Y02 = { a, b, fa, fb in axisTest(-a, b, fa, fb, v0, v2, _X, _Z) }
        let axisTest_Y1  = { a, b, fa, fb in axisTest(-a, b, fa, fb, v0, v1, _X, _Z) }
        let axisTest_Z12 = { a, b, fa, fb in axisTest(a, -b, fa, fb, v1, v2, _X, _Y) }
        let axisTest_Z0  = { a, b, fa, fb in axisTest(a, -b, fa, fb, v0, v1, _X, _Y) }

        // compute triangle edges
        let e0 = v1 - v0      // tri edge 0
        let e1 = v2 - v1      // tri edge 1
        let e2 = v0 - v2      // tri edge 2

        // Bullet 3:  
        //  test the 9 tests first (this was faster)

        var fex = abs(e0.x)
        var fey = abs(e0.y)
        var fez = abs(e0.z)
        if axisTest_X01(e0.z, e0.y, fez, fey) == false { return false }
        if axisTest_Y02(e0.z, e0.x, fez, fex) == false { return false }
        if axisTest_Z12(e0.y, e0.x, fey, fex) == false { return false }

        fex = abs(e1.x)
        fey = abs(e1.y)
        fez = abs(e1.z)
        if axisTest_X01(e1.z, e1.y, fez, fey) == false { return false }
        if axisTest_Y02(e1.z, e1.x, fez, fex) == false { return false }
        if axisTest_Z0(e1.y, e1.x, fey, fex) == false  { return false }

        fex = abs(e2.x)
        fey = abs(e2.y)
        fez = abs(e2.z)
        if axisTest_X2(e2.z, e2.y, fez, fey) == false  { return false }
        if axisTest_Y1(e2.z, e2.x, fez, fex) == false  { return false }
        if axisTest_Z12(e2.y, e2.x, fey, fex) == false { return false }

        // Bullet 1: 
        //  first test overlap in the {x,y,z}-directions 
        //  find min, max of the triangle each direction, and test for overlap in 
        //  that direction -- this is equivalent to testing a minimal AABB around 
        //  the triangle against the AABB 

        let findMinMax = { (x0: Scalar, x1: Scalar, x2: Scalar) in
            (Swift.min(x0, x1, x2), Swift.max(x0, x1, x2))
        }

        // test in X-direction
        var (min, max) = findMinMax(v0.x, v1.x, v2.x)
        if min > boxhalfsize.x || max < -boxhalfsize.x { return false }

        // test in Y-direction
        (min, max) = findMinMax(v0.y, v1.y, v2.y)
        if min > boxhalfsize.y || max < -boxhalfsize.y { return false }

        // test in Z-direction
        (min, max) = findMinMax(v0.z, v1.z, v2.z)
        if min > boxhalfsize.z || max < -boxhalfsize.z { return false }

        // Bullet 2: 
        //  test if the box intersects the plane of the triangle 
        //  compute plane equation of triangle: normal*x+d=0 
        let planeBoxOverlap = {
            (normal: Vector3, vert: Vector3, maxbox: Vector3) in
            var vmin = Vector3(), vmax = Vector3()
            for q in 0...2 {
                let v = vert[q]
                if normal[q] > .zero {
                    vmin[q] = -maxbox[q] - v
                    vmax[q] = maxbox[q] - v
                } else {
                    vmin[q] = maxbox[q] - v
                    vmax[q] = -maxbox[q] - v
                }
            }
            if Vector3.dot(normal, vmin) > .zero { return false }
            if Vector3.dot(normal, vmax) >= .zero { return true }
            return false
        }
        let normal = Vector3.cross(e0, e1)
        if planeBoxOverlap(normal, v0, boxhalfsize) == false { return false }
        // box and triangle overlaps
        return true
    }

    public func overlapTest(_ aabb: AABB) -> Bool {
        intersection(aabb).isNull == false
    }
}
