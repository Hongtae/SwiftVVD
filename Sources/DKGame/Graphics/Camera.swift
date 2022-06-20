//
//  File: Camera.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

/// A 3D camera class.
///
///    +z is inner direction of actual frustum, (-1:front, +1:back)
///    but this class set up -z is inner. (right handed)
///    coordinate system will be converted as right-handed after
///    transform applied. CCW (counter-clock-wise) is front-face.
///
///    coordinates transformed as below:
///
///          +Y
///           |
///           |
///           |_______ +X
///           /
///          /
///         /
///        +Z 
///
///

public struct Camera {

    private var viewMatrix: Matrix4
    private var projectionMatrix: Matrix4

    private var frustumNear: Plane
    private var frustumFar: Plane
    private var frustumLeft: Plane
    private var frustumRight: Plane
    private var frustumTop: Plane
    private var frustumBottom: Plane

    public init() {
        self.viewMatrix = .identity
        self.projectionMatrix = .identity

        self.frustumNear = .init()
        self.frustumFar = .init()
        self.frustumLeft = .init()
        self.frustumRight = .init()
        self.frustumTop = .init()
        self.frustumBottom = .init()
    }

    public var view: Matrix4 {
        get { viewMatrix }
        set(m) {
            viewMatrix = m
            self.updateFrustum()
        }
    }

    public var projection: Matrix4 {
        get { projectionMatrix }
        set(m) {
            projectionMatrix = m
            self.updateFrustum()
        }
    }

    public var viewProjectionMatrix: Matrix4 { viewMatrix * projectionMatrix }
    public var viewPosition: Vector3 {
        let v = viewMatrix.row4
        let m = Matrix3(
            viewMatrix.m11, viewMatrix.m12, viewMatrix.m13,
            viewMatrix.m21, viewMatrix.m22, viewMatrix.m23,
            viewMatrix.m31, viewMatrix.m32, viewMatrix.m33)
        return Vector3(-v.x, -v.y, -v.z) * (m.inverted() ?? Matrix3.identity)
    }

    public var viewDirection: Vector3 {
        let v = viewMatrix.column3
        return Vector3(-v.x, -v.y, -v.z).normalized()
    }

    public var viewUp: Vector3 {
        let v = viewMatrix.column2
        return Vector3(v.x, v.y, v.z).normalized()
    }

    public mutating func setView(position pos: Vector3, direction dir: Vector3, up: Vector3) {
        assert(dir.length > 0.0)
        assert(up.length > 0.0)

        let axisZ = -dir.normalized()
        let axisX = Vector3.cross(up, axisZ).normalized()
        let axisY = Vector3.cross(axisZ, axisX).normalized()

        let tX = -Vector3.dot(axisX, pos)
        let tY = -Vector3.dot(axisY, pos)
        let tZ = -Vector3.dot(axisZ, pos)

        self.view = Matrix4(
            axisX.x, axisY.x, axisZ.x, 0.0,
            axisX.y, axisY.y, axisZ.y, 0.0,
            axisX.z, axisY.z, axisZ.z, 00,
            tX, tY, tZ, 1.0)
    }

    public mutating func setViewProjection(view: Matrix4, projection proj: Matrix4) {
        self.viewMatrix = view
        self.projectionMatrix = proj
        self.updateFrustum()
    }

    public mutating func setPerspective(aspect: Scalar, fov: Scalar, near nz: Scalar, far fz: Scalar) {
        assert(aspect > 0.0)
        assert(fov > 0.0)
        assert(nz > 0.0)
        assert(fz > 0.0)
        assert(fz > nz)

        let f = 1.0 / tan(fov * 0.5)
        self.projection = Matrix4(
            f / aspect, 0.0, 0.0, 0.0,
            0.0, f, 0.0, 0.0,
            0.0, 0.0, (fz + nz) / (nz - fz), -1.0,
            0.0, 0.0, (2.0 * fz * nz) / (nz - fz), 0.0)
    }

    public mutating func setOrthographics(width: Scalar, height: Scalar, near nz: Scalar, far fz: Scalar) {
        assert(width > 0.0)
        assert(height > 0.0)
        assert(fz > nz)

        self.projection = Matrix4(
            2.0 / width, 0.0, 0.0, 0.0,
            0.0, 2.0 / height, 0.0, 0.0,
            0.0, 0.0, 2.0 / (nz - fz), 0.0,
            0.0, 0.0, (fz + nz) / (nz - fz), 1.0)
    }

    public var isPerspective: Bool  { projectionMatrix.m44 != 1.0 }
    public var isOrthographic: Bool { projectionMatrix.m44 == 1.0 }

    public func isPointInside(_ point: Vector3) -> Bool {
        isSphereInside(point, 0)
    }

    public func isSphereInside(_ center: Vector3, _ radius: Scalar) -> Bool {
        if radius < 0                           { return false }
        if frustumNear.dot(center)   < -radius  { return false }
        if frustumFar.dot(center)    < -radius  { return false }
        if frustumLeft.dot(center)   < -radius  { return false }
        if frustumRight.dot(center)  < -radius  { return false }
        if frustumTop.dot(center)    < -radius  { return false }
        if frustumBottom.dot(center) < -radius  { return false }
        return true
    }

    private mutating func updateFrustum() {

        //////////////////////////////////////
        //    frustum planes
        //
        //         7+-------+4
        //         /|  far /|
        //        / |     / |
        //       /  |    /  |
        //      /  6+---/---+5 
        //     /   /   /   / 
        //   3+-------+0  /
        //    |  /    |  /
        //    | /     | /
        //    |/ near |/
        //   2+-------+1
        //

        var vec: [Vector3] = [
            Vector3( 1,  1, -1),    // near right top
            Vector3( 1, -1, -1),    // near right bottom
            Vector3(-1, -1, -1),    // near left bottom
            Vector3(-1,  1, -1),    // near left top
            Vector3( 1,  1,  1),    // far right top
            Vector3( 1, -1,  1),    // far right bottom
            Vector3(-1, -1,  1),    // far left bottom
            Vector3(-1,  1,  1),    // far left top
        ]

        var mat = self.viewMatrix * self.projectionMatrix
        mat = mat.inverted() ?? .identity

        for i in 0..<8 {
            vec[i].transform(by: mat)
        }
        // far		(4,5,6,7)
        // near		(0,1,2,3)
        // top		(0,4,7,3)
        // bottom	(1,5,6,2)
        // right	(0,1,5,4)
        // left		(2,3,7,6)

        frustumFar =    Plane(vec[4], vec[7], vec[5])
        frustumNear =   Plane(vec[3], vec[0], vec[2])
        frustumTop =    Plane(vec[3], vec[7], vec[0])
        frustumBottom = Plane(vec[1], vec[5], vec[2])
        frustumLeft =   Plane(vec[2], vec[6], vec[3])
        frustumRight =  Plane(vec[0], vec[4], vec[1])
    }
}
