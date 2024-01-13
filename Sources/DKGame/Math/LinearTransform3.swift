//
//  File: LinearTransform3.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LinearTransform3: Hashable {
    public typealias Vector = Vector3

    public var matrix3: Matrix3

    public static let identity: LinearTransform3 = .init(Matrix3.identity)

    public var rotation: Quaternion {
        var x = sqrt(max(0.0, 1 + matrix3.m11 - matrix3.m22 - matrix3.m33)) * 0.5
        var y = sqrt(max(0.0, 1 - matrix3.m11 + matrix3.m22 - matrix3.m33)) * 0.5
        var z = sqrt(max(0.0, 1 - matrix3.m11 - matrix3.m22 + matrix3.m33)) * 0.5
        let w = sqrt(max(0.0, 1 + matrix3.m11 + matrix3.m22 + matrix3.m33)) * 0.5
        x = copysign(x, matrix3.m23 - matrix3.m32)
        y = copysign(y, matrix3.m31 - matrix3.m13)
        z = copysign(z, matrix3.m12 - matrix3.m21)

        return Quaternion(x, y, z, w)
    }

    public var scale: Vector3 {
        Vector3(matrix3.row1.magnitude,
                matrix3.row2.magnitude,
                matrix3.row3.magnitude)
    }

    public init(_ t: Self = .identity) {
        self.matrix3 = t.matrix3
    }

    public init(_ q: Quaternion) {
        self.matrix3 = q.matrix3
    }

    public init(_ m: Matrix3) {
        self.matrix3 = m
    }
 
    public init<T: BinaryFloatingPoint>(scaleX x: T, y: T, z: T) {
        self.matrix3 = .init(x, 0.0, 0.0,
                             0.0, y, 0.0,
                             0.0, 0.0, z)
    }

    public init(axisX x: Vector3, y: Vector3, z: Vector3) {
        self.matrix3 = .init(row1: x, row2: y, row3: z)
    }

    // Decompose by scale, rotate order.
    // See the following sources:
    //  https://opensource.apple.com/source/WebCore/WebCore-514/platform/graphics/transforms/TransformationMatrix.cpp
    //  https://github.com/g-truc/glm/blob/master/glm/gtx/matrix_decompose.inl
    public func decompose(scale: inout Vector3, rotation: inout Quaternion) -> Bool {
        if abs(matrix3.determinant) < .ulpOfOne { return false }

        var row = [matrix3.row1, matrix3.row2, matrix3.row3]
        var skewYZ, skewXZ, skewXY: Scalar

        // get scale-x and normalize row-1
        scale.x = row[0].magnitude
        row[0] = row[0] / scale.x

        // xy shear
        skewXY = Vector3.dot(row[0], row[1])
        row[1] = row[1] + row[0] * -skewXY

        // get scale-y, normalize row-2
        scale.y = row[1].magnitude
        row[1] = row[1] / scale.y
        skewXY /= scale.y

        // xz, yz shear
        skewXZ = Vector3.dot(row[0], row[2])
        row[2] = row[2] + row[0] * -skewXZ
        skewYZ = Vector3.dot(row[1], row[2])
        row[2] = row[2] + row[1] * -skewYZ

        // get scale-z, normalize row-3
        scale.z = row[2].magnitude
        row[2] = row[2] / scale.z
        skewXZ /= scale.z
        skewYZ /= scale.z

        //let shear = Vector3(skewYZ, skewXZ, skewXY)

        // check coordindate system flip
        let pdum3 = Vector3.cross(row[1], row[2])
        if Vector3.dot(row[0], pdum3) < .zero {
            scale *= -1.0
            row[0] *= -1.0
            row[1] *= -1.0
            row[2] *= -1.0
        }

        let t = row[0].x + row[1].y + row[2].z
        if t > .zero {
            var root = sqrt(t + 1.0)
            rotation.w = 0.5 * root
            root = 0.5 / root
            rotation.x = root * (row[1].z - row[2].y)
            rotation.y = root * (row[2].x - row[0].z)
            rotation.z = root * (row[0].y - row[1].x)
        } else {
            var i = 0
            if row[1].y > row[0].x { i = 1 }
            if row[2].z > row[i][i] { i = 2 }
            let j = (i + 1) % 3
            let k = (j + 1) % 3

            var root = sqrt(row[i][i] - row[j][j] - row[k][k] + 1.0)
            rotation[i] = 0.5 * root
            root = 0.5 / root
            rotation[j] = root * (row[i][j] + row[j][i])
            rotation[k] = root * (row[i][k] + row[k][i])
            rotation.w = root * (row[j][k] - row[k][j])
        }
        return true
    }

    public func inverted() -> Self {
        let matrix = self.matrix3.inverted() ?? .identity
        return Self(matrix)
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public func concatenating(_ t: Self) -> Self {
        return Self(self.matrix3.concatenating(t.matrix3))
    }

    public func concatenating(_ m: Matrix3) -> Self {
        return Self(self.matrix3.concatenating(m))
    }

    public func concatenating(_ q: Quaternion) -> Self {
        return Self(self.matrix3.concatenating(q.matrix3))
    }

    public mutating func concatenate(_ t: Self) {
        self = self.concatenating(t)
    }

    public mutating func concatenate(_ m: Matrix3) {
        self = self.concatenating(m)
    }

    public mutating func concatenate(_ q: Quaternion) {
        self = self.concatenating(q)
    }

    public func rotated(by q: Quaternion) -> Self {
        self.concatenating(q)
    }

    public mutating func rotate(by q: Quaternion) {
        self.concatenate(q)
    }

    public func rotated(angle: some BinaryFloatingPoint, axis: Vector3) -> Self {
        if angle.isZero == false {
            return self.rotated(by: Quaternion(angle: angle, axis: axis))
        }
        return self
    }

    public mutating func rotate(angle: some BinaryFloatingPoint, axis: Vector3) {
        if angle.isZero == false {
            self.rotate(by: Quaternion(angle: angle, axis: axis))
        }
    }

    public mutating func rotateX(_ r: some BinaryFloatingPoint) {
        // X - Axis:
        // |1  0    0   |
        // |0  cos  sin |
        // |0 -sin  cos |
        let r = Scalar(r)
        let cosR = cos(r)
        let sinR = sin(r)
        let m = Matrix3(1.0, 0.0, 0.0,
                        0.0, cosR, sinR,
                        0.0, -sinR, cosR)
        self.matrix3 *= m
    }

    public mutating func rotateY(_ r: some BinaryFloatingPoint) {
        // Y - Axis:
        // |cos  0 -sin |
        // |0    1  0   |
        // |sin  0  cos |
        let r = Scalar(r)
        let cosR = cos(r)
        let sinR = sin(r)
        let m = Matrix3(cosR, 0.0, -sinR,
                        0.0, 1.0, 0.0,
                        sinR, 0.0, cosR)
        self.matrix3 *= m
    }

    public mutating func rotateZ(_ r: some BinaryFloatingPoint) {
        // Z - Axis:
        // |cos  sin 0  |
        // |-sin cos 0  |
        // |0    0   1  |
        let r = Scalar(r)
        let cosR = cos(r)
        let sinR = sin(r)
        let m = Matrix3(cosR, sinR, 0.0,
                        -sinR, cosR, 0.0,
                        0.0, 0.0, 1.0)
        self.matrix3 *= m
    }

    public mutating func scale(byVector v: Vector3) {
        self.scale(x: v.x, y: v.y, z: v.z)
    }

    public mutating func scale(uniform s: some BinaryFloatingPoint) {
        self.scale(x: s, y: s, z: s)
    }

    public mutating func scale<T: BinaryFloatingPoint>(x: T, y: T, z: T) {
        // | X 0 0 |
        // | 0 Y 0 |
        // | 0 0 Z |
        self.matrix3.column1 *= x
        self.matrix3.column2 *= y
        self.matrix3.column3 *= z
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return lhs.concatenating(rhs)
    }

    public static func * (lhs: Self, rhs: Matrix3) -> Self {
        return lhs.concatenating(rhs)
    }

    public static func * (lhs: Self, rhs: Quaternion) -> Self {
        return lhs.concatenating(rhs)
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs = lhs * rhs
    }

    public static func *= (lhs: inout Self, rhs: Matrix3) {
        lhs = lhs * rhs
    }

    public static func *= (lhs: inout Self, rhs: Quaternion) {
        lhs = lhs * rhs
    }
}

public extension Vector3 {
    func applying(_ t: LinearTransform3) -> Vector3 {
        self.applying(t.matrix3)
    }

    mutating func apply(_ t: LinearTransform3) {
        self = self.applying(t)
    }
}
