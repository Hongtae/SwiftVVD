//
//  File: ViewProjection.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ViewTransform: Hashable {
    private let matrix: Matrix3
    private let t: Vector3

    public var matrix3: Matrix3 { matrix }
    public var matrix4: Matrix4 {
        Matrix4(matrix.m11, matrix.m12, matrix.m13, 0.0,
                matrix.m21, matrix.m22, matrix.m23, 0.0,
                matrix.m31, matrix.m32, matrix.m33, 0.0,
                t.x, t.y, t.z, 1.0)
    }

    public var direction: Vector3 {
        (-matrix.column3).normalized()
    }

    public var up: Vector3 {
        matrix.column2.normalized()
    }

    public var position: Vector3 {
        (-t).applying(matrix.inverted()!)
    }

    public var transform: AffineTransform3 {
        .init(linear: matrix, origin: t)
    }

    public func concatenating(_ other: Self) -> Self {
        return Self(self.matrix.concatenating(other.matrix),
                    self.t.applying(other.matrix) + other.t)
    }

    public mutating func concatenate(_ t: Self) {
        self = self.concatenating(t)
    }

    public init(_ m: Matrix3, _ t: Vector3) {
        self.matrix = m
        self.t = t
    }

    public init(_ t: AffineTransform3) {
        self.matrix = t.matrix3
        self.t = t.translation
    }

    public init(position pos: Vector3, direction dir: Vector3, up: Vector3) {
        assert(dir.length > .zero)
        assert(up.length > .zero)

        let axisZ = -dir.normalized()
        let axisX = Vector3.cross(up, axisZ).normalized()
        let axisY = Vector3.cross(axisZ, axisX).normalized()

        let tX = -Vector3.dot(axisX, pos)
        let tY = -Vector3.dot(axisY, pos)
        let tZ = -Vector3.dot(axisZ, pos)

        self.matrix = Matrix3(axisX.x, axisY.x, axisZ.x,
                              axisX.y, axisY.y, axisZ.y,
                              axisX.z, axisY.z, axisZ.z)
        self.t = Vector3(tX, tY, tZ)
    }
}

public struct ProjectionTransform: Hashable {
    public let matrix: Matrix4

    public var isPerspective: Bool  { matrix.m44 != 1.0 }
    public var isOrthographic: Bool { matrix.m44 == 1.0 }

    static let leftHanded = false

    public static func perspectiveLH(aspect: Scalar,
                                     fov: Scalar,
                                     near nz: Scalar,
                                     far fz: Scalar) -> ProjectionTransform {
        assert(aspect > .zero)
        assert(fov > .zero)
        assert(nz > .zero)
        assert(fz > nz)

        let f = 1.0 / tan(fov * 0.5)

        return ProjectionTransform(
            matrix: Matrix4(f / aspect, 0.0, 0.0, 0.0,
                            0.0, f, 0.0, 0.0,
                            0.0, 0.0, fz / (fz - nz), 1.0,
                            0.0, 0.0, -(fz * nz) / (fz - nz), 0.0))
    }

    public static func perspectiveRH(aspect: Scalar,
                                     fov: Scalar,
                                     near nz: Scalar,
                                     far fz: Scalar) -> ProjectionTransform {
        assert(aspect > .zero)
        assert(fov > .zero)
        assert(nz > .zero)
        assert(fz > nz)

        let f = 1.0 / tan(fov * 0.5)

        return ProjectionTransform(
            matrix: Matrix4(f / aspect, 0.0, 0.0, 0.0,
                            0.0, f, 0.0, 0.0,
                            0.0, 0.0, fz / (nz - fz), -1.0,
                            0.0, 0.0, -(fz * nz) / (fz - nz), 0.0))
    }

    public static func perspective(aspect: Scalar,
                                   fov: Scalar,
                                   near nz: Scalar,
                                   far fz: Scalar) -> ProjectionTransform {
        if leftHanded {
            return perspectiveLH(aspect: aspect, fov: fov, near: nz, far: fz)
        }
        return perspectiveRH(aspect: aspect, fov: fov, near: nz, far: fz)
    }

    public static func orthographicLH(left l: Scalar,
                                      right r: Scalar,
                                      bottom b: Scalar,
                                      top t: Scalar,
                                      near n: Scalar,
                                      far f: Scalar) -> ProjectionTransform {
        return ProjectionTransform(
            matrix: Matrix4(2.0 / (r - l), 0.0, 0.0, 0.0,
                            0.0, 2.0 / (t - b), 0.0, 0.0,
                            0.0, 0.0, 1.0 / (f - n), 0.0,
                            -(r + l) / (r - l), -(t + b) / (t - b), -n / (f - n), 1.0))
    }

    public static func orthographicRH(left l: Scalar,
                                      right r: Scalar,
                                      bottom b: Scalar,
                                      top t: Scalar,
                                      near n: Scalar,
                                      far f: Scalar) -> ProjectionTransform {
        return ProjectionTransform(
            matrix: Matrix4(2.0 / (r - l), 0.0, 0.0, 0.0,
                            0.0, 2.0 / (t - b), 0.0, 0.0,
                            0.0, 0.0, -1.0 / (f - n), 0.0,
                            -(r + l) / (r - l), -(t + b) / (t - b), -n / (f - n), 1.0))
    }

    public static func orthographic(left l: Scalar,
                                    right r: Scalar,
                                    bottom b: Scalar,
                                    top t: Scalar,
                                    near n: Scalar,
                                    far f: Scalar) -> ProjectionTransform {
        if leftHanded {
            return orthographicLH(left: l, right: r, bottom: b, top: t, near: n, far: f)
        }
        return orthographicRH(left: l, right: r, bottom: b, top: t, near: n, far: f)
    }

    public init(matrix: Matrix4) {
        self.matrix = matrix
    }
}

public struct ViewFrustum {

    public let view: ViewTransform
    public let projection: ProjectionTransform
    public var matrix: Matrix4 {
        view.matrix4.concatenating(projection.matrix)
    }

    public let near: Plane
    public let far: Plane
    public let left: Plane
    public let right: Plane
    public let top: Plane
    public let bottom: Plane

    public init(view: ViewTransform, projection: ProjectionTransform) {
        self.view = view
        self.projection = projection

        //////////////////////////////////////
        //    frustum planes
        //
        //         7+-------+4
        //         /|  far /|
        //        / |     / | (z: 1.0)
        //       /  |    /  |
        //      /  6+---/---+5
        //     /   /   /   /
        //   3+-------+0  /
        //    |  /    |  /
        //    | /     | /
        //    |/ near |/ (z: 0.0)
        //   2+-------+1
        //

        var vec: [Vector3] = [
            Vector3( 1, 1, 0),  // near right top
            Vector3( 1,-1, 0),  // near right bottom
            Vector3(-1,-1, 0),  // near left bottom
            Vector3(-1, 1, 0),  // near left top
            Vector3( 1, 1, 1),  // far right top
            Vector3( 1,-1, 1),  // far right bottom
            Vector3(-1,-1, 1),  // far left bottom
            Vector3(-1, 1, 1),  // far left top
        ]

        let matrix = view.matrix4.concatenating(projection.matrix)
            .inverted() ?? .identity

        vec = vec.map { $0.applying(matrix) }

        // far      (4,5,6,7)
        // near     (0,1,2,3)
        // top      (0,4,7,3)
        // bottom   (1,5,6,2)
        // left     (2,3,7,6)
        // right    (0,1,5,4)

        if ProjectionTransform.leftHanded {
            self.far = Plane(vec[5], vec[7], vec[4])
            self.near = Plane(vec[2], vec[0], vec[3])
            self.top = Plane(vec[0], vec[7], vec[3])
            self.bottom = Plane(vec[2], vec[5], vec[1])
            self.left = Plane(vec[3], vec[6], vec[2])
            self.right = Plane(vec[1], vec[4], vec[0])
        } else {
            self.far = Plane(vec[4], vec[7], vec[5])
            self.near = Plane(vec[3], vec[0], vec[2])
            self.top = Plane(vec[3], vec[7], vec[0])
            self.bottom = Plane(vec[1], vec[5], vec[2])
            self.left = Plane(vec[2], vec[6], vec[3])
            self.right = Plane(vec[0], vec[4], vec[1])
        }
    }

    public func isSphereInside(_ sphere: Sphere) -> Bool {
        if sphere.radius < 0  { return false }
        let center = Vector4(sphere.center, 1)
        if self.near.dot(center)   < -sphere.radius { return false }
        if self.far.dot(center)    < -sphere.radius { return false }
        if self.left.dot(center)   < -sphere.radius { return false }
        if self.right.dot(center)  < -sphere.radius { return false }
        if self.top.dot(center)    < -sphere.radius { return false }
        if self.bottom.dot(center) < -sphere.radius { return false }
        return true
    }

    public func isPointInside(_ point: Vector3) -> Bool {
        isSphereInside(Sphere(center: point, radius: 0))
    }

    public func isAABBInside(_ aabb: AABB) -> Bool {
        if aabb.isNull { return false }

        let planes = [
            self.near,
            self.far,
            self.left,
            self.right,
            self.top,
            self.bottom
        ]
        let minMax = [
            aabb.min, aabb.max
        ]
        for i in 0..<6 {
            let plane = planes[i]
            var bx = plane.a > .zero ? 1 : 0
            var by = plane.b > .zero ? 1 : 0
            var bz = plane.c > .zero ? 1 : 0

            var d = plane.dot(Vector3(minMax[bx].x, minMax[by].y, minMax[bz].z))
            if d < .zero {
                return false
            }

            bx = 1 - bx
            by = 1 - by
            bz = 1 - bz
            d = plane.dot(Vector3(minMax[bx].x, minMax[by].y, minMax[bz].z))
            if d <= .zero {
                return true  // intersects
            }
        }
        // inside
        return true
    }
}

extension ViewFrustum: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.view == rhs.view && lhs.projection == rhs.projection
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(view)
        hasher.combine(projection)
    }
}
