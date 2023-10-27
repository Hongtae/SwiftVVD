//
//  File: ViewProjection.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ViewTransform {
    public let matrix: Matrix3
    public let position: Vector3

    public var matrix3: Matrix3 { matrix }
    public var matrix4: Matrix4 {
        Matrix4(matrix.m11, matrix.m12, matrix.m13, 0.0,
                matrix.m21, matrix.m22, matrix.m23, 0.0,
                matrix.m31, matrix.m32, matrix.m33, 0.0,
                position.x, position.y, position.z, 1.0)
    }

    public var direction: Vector3 {
        let v = matrix.column3
        return Vector3(-v.x, -v.y, -v.z).normalized()
    }

    public var up: Vector3 {
        let v = matrix.column2
        return Vector3(v.x, v.y, v.z).normalized()
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
        self.position = Vector3(tX, tY, tZ)
    }
}

public struct ProjectionTransform {
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

    public static func setOrthographicLH(left l: Scalar,
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

    public static func setOrthographicRH(left l: Scalar,
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

    public static func setOrthographic(left l: Scalar,
                                       right r: Scalar,
                                       bottom b: Scalar,
                                       top t: Scalar,
                                       near n: Scalar,
                                       far f: Scalar) -> ProjectionTransform {
        if leftHanded {
            return setOrthographicLH(left: l, right: r, bottom: b, top: t, near: n, far: f)
        }
        return setOrthographicRH(left: l, right: r, bottom: b, top: t, near: n, far: f)
    }
}

public struct ViewFrustum {

    public let view: ViewTransform
    public let projection: ProjectionTransform
    public var matrix: Matrix4 {
        view.matrix4.concatenating(projection.matrix)
    }

    public let near: Vector4
    public let far: Vector4
    public let left: Vector4
    public let right: Vector4
    public let top: Vector4
    public let bottom: Vector4

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

        let makePlane = { (v1: Vector3, v2: Vector3, v3: Vector3)->Vector4 in
            let n = Vector3.cross(v2 - v1, v3 - v1).normalized()
            return Vector4(n, -Vector3.dot(n, v1))
        }

        // far      (4,5,6,7)
        // near     (0,1,2,3)
        // top      (0,4,7,3)
        // bottom   (1,5,6,2)
        // left     (2,3,7,6)
        // right    (0,1,5,4)

        if ProjectionTransform.leftHanded {
            self.far = makePlane(vec[5], vec[7], vec[4])
            self.near = makePlane(vec[2], vec[0], vec[3])
            self.top = makePlane(vec[0], vec[7], vec[3])
            self.bottom = makePlane(vec[2], vec[5], vec[1])
            self.left = makePlane(vec[3], vec[6], vec[2])
            self.right = makePlane(vec[1], vec[4], vec[0])
        } else {
            self.far = makePlane(vec[4], vec[7], vec[5])
            self.near = makePlane(vec[3], vec[0], vec[2])
            self.top = makePlane(vec[3], vec[7], vec[0])
            self.bottom = makePlane(vec[1], vec[5], vec[2])
            self.left = makePlane(vec[2], vec[6], vec[3])
            self.right = makePlane(vec[0], vec[4], vec[1])
        }
    }

    public func isSphereInside(center: Vector3, radius: Scalar) -> Bool {
        if radius < 0  { return false }
        let center = Vector4(center, 1)
        if Vector4.dot(self.near, center)   < -radius { return false }
        if Vector4.dot(self.far, center)    < -radius { return false }
        if Vector4.dot(self.left, center)   < -radius { return false }
        if Vector4.dot(self.right, center)  < -radius { return false }
        if Vector4.dot(self.top, center)    < -radius { return false }
        if Vector4.dot(self.bottom, center) < -radius { return false }
        return true
    }

    public func isPointInside(_ point: Vector3) -> Bool {
        isSphereInside(center: point, radius: 0)
    }
}
