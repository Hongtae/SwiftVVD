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
        Vector3(Vector3(matrix3.m11, matrix3.m12, matrix3.m13).length,
                Vector3(matrix3.m21, matrix3.m22, matrix3.m23).length,
                Vector3(matrix3.m31, matrix3.m32, matrix3.m33).length)
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
 
    public init(scaleX x: any BinaryFloatingPoint,
                y: any BinaryFloatingPoint,
                z: any BinaryFloatingPoint) {
        self.matrix3 = .init(x, 0.0, 0.0,
                             0.0, y, 0.0,
                             0.0, 0.0, z)
    }

    public init(axisX x: Vector3, y: Vector3, z: Vector3) {
        self.matrix3 = .init(row1: x, row2: y, row3: z)
    }

    // Decompose by scale, rotate order.
    public func decompose(scale: inout Vector3, rotation: inout Quaternion) -> Bool {
        let s = self.scale
        if s.x * s.y * s.z == 0.0 { return false }

        let x = 1.0 / s.x
        let y = 1.0 / s.y
        let z = 1.0 / s.z
        let normalized = Matrix3(row1: self.matrix3.row1 * x,
                                 row2: self.matrix3.row2 * y,
                                 row3: self.matrix3.row3 * z)
        
        rotation = LinearTransform3(normalized).rotation
        scale = s
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
        return Self(self.matrix3 * t.matrix3)
    }

    public func concatenating(_ m: Matrix3) -> Self {
        return Self(self.matrix3 * m)
    }

    public func concatenating(_ q: Quaternion) -> Self {
        return Self(self.matrix3 * q.matrix3)
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

    public func rotated(angle: any BinaryFloatingPoint, axis: Vector3) -> Self {
        if angle.isZero == false {
            return self.rotated(by: Quaternion(angle: angle, axis: axis))
        }
        return self
    }

    public mutating func rotate(angle: any BinaryFloatingPoint, axis: Vector3) {
        if angle.isZero == false {
            self.rotate(by: Quaternion(angle: angle, axis: axis))
        }
    }

    public mutating func rotateX(_ r: any BinaryFloatingPoint) {
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

    public mutating func rotateY(_ r: any BinaryFloatingPoint) {
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

    public mutating func rotateZ(_ r: any BinaryFloatingPoint) {
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

    public mutating func scale(uniform s: any BinaryFloatingPoint) {
        self.scale(x: s, y: s, z: s)
    }

    public mutating func scale(x: any BinaryFloatingPoint,
                               y: any BinaryFloatingPoint,
                               z: any BinaryFloatingPoint) {
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
