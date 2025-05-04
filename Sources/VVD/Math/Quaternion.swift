//
//  File: Quaternion.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Quaternion: Vector, Hashable, Sendable {
    public var x: Scalar
    public var y: Scalar
    public var z: Scalar
    public var w: Scalar

    public static var components: Int { 4 }
    public subscript(index: Int) -> Scalar {
        get {
            switch index {
            case 0: return self.x
            case 1: return self.y
            case 2: return self.z
            case 3: return self.w
            default:
                fatalError("Index out of range")
            }
        }
        set (value) {
            switch index {
            case 0: self.x = value
            case 1: self.y = value
            case 2: self.z = value
            case 3: self.w = value
            default:
                fatalError("Index out of range")
            }
        }
    }

    public static let zero = Quaternion(0.0, 0.0, 0.0, 0.0)
    public static let identity = Quaternion(0.0, 0.0, 0.0, 1.0)

    public init(_ quat: Self = .identity) {
        self = quat
    }

    public init<T: BinaryFloatingPoint>(_ x: T, _ y: T, _ z: T, _ w: T) {
        self.x = Scalar(x)
        self.y = Scalar(y)
        self.z = Scalar(z)
        self.w = Scalar(w)
    }

    public init<T: BinaryFloatingPoint>(x: T, y: T, z: T, w: T) {
        self.init(x, y, z, w)
    }

    public init(angle: some BinaryFloatingPoint, axis: Vector3) {
        self.init(0, 0, 0, 1)
        if axis.length > 0.0 {
            let u = axis.normalized()
            let a = Scalar(angle) * 0.5
            let sinR = sin(a)

            self.x = sinR * u.x
            self.y = sinR * u.y
            self.z = sinR * u.z
            self.w = cos(a)
        }
    }

    public init<T: BinaryFloatingPoint>(pitch: T, yaw: T, roll: T) {
        let p = Scalar(pitch) * 0.5
        let y = Scalar(yaw) * 0.5
        let r = Scalar(roll) * 0.5

        let sinP = sin(p)
        let cosP = cos(p)
        let sinY = sin(y)
        let cosY = cos(y)
        let sinR = sin(r)
        let cosR = cos(r)

        self.x = cosR * sinP * cosY + sinR * cosP * sinY
        self.y = cosR * cosP * sinY - sinR * sinP * cosY
        self.z = sinR * cosP * cosY - cosR * sinP * sinY
        self.w = cosR * cosP * cosY + sinR * sinP * sinY

        self.normalize()
    }

    public init(from: Vector3, to: Vector3, t: some BinaryFloatingPoint) {
        self.init(0, 0, 0, 1)
        let len1 = from.length
        let len2 = to.length
        if len1 > 0.0 && len2 > 0.0 {
            let axis = Vector3.cross(from, to)
            let angle = acos(Vector3.dot(from.normalized(), to.normalized())) * Scalar(t)

            self.init(angle: angle, axis: axis)
        }
    }

    public init(_ vector: Vector4) {
        self.init(vector.x, vector.y, vector.z, vector.w)
    }

    public var roll: Scalar { atan2(2 * (x * y + w * z), w * w + x * x - y * y - z * z) }

    public var pitch: Scalar { atan2(2 * (y * z + w * x), w * w - x * x - y * y + z * z) }

    public var yaw: Scalar { asin(-2 * (x * z - w * y)) }

    public var angle: Scalar {
        let lengthSq = x * x + y * y + z * z + w * w
        if lengthSq > 0.0 && abs(w) < 1.0 {
            return 2.0 * acos(w)
        }
        return 0.0
    }

    public var axis: Vector3 {
        let lengthSq = x * x + y * y + z * z + w * w
        if lengthSq > 0.0 {
            let inv = 1.0 / sqrt(lengthSq)
            return Vector3(x: x * inv, y: y * inv, z: z * inv)
        }
        return Vector3(x: 1.0, y: 0.0, z: 0.0)
    }

    public var vector4: Vector4 { Vector4(x, y, z, w) }

    public var matrix3: Matrix3 {
        var mat = Matrix3.identity
        mat.m11 = 1.0 - 2.0 * (y * y + z * z)
        mat.m12 = 2.0 * (x * y + z * w)
        mat.m13 = 2.0 * (x * z - y * w)

        mat.m21 = 2.0 * (x * y - z * w)
        mat.m22 = 1.0 - 2.0 * (x * x + z * z)
        mat.m23 = 2.0 * (y * z + x * w)

        mat.m31 = 2.0 * (x * z + y * w)
        mat.m32 = 2.0 * (y * z - x * w)
        mat.m33 = 1.0 - 2.0 * (x * x + y * y)
        return mat
    }

    public var matrix4: Matrix4 {
        var mat = Matrix4.identity
        mat.m11 = 1.0 - 2.0 * (y * y + z * z)
        mat.m12 = 2.0 * (x * y + z * w)
        mat.m13 = 2.0 * (x * z - y * w)

        mat.m21 = 2.0 * (x * y - z * w)
        mat.m22 = 1.0 - 2.0 * (x * x + z * z)
        mat.m23 = 2.0 * (y * z + x * w)

        mat.m31 = 2.0 * (x * z + y * w)
        mat.m32 = 2.0 * (y * z - x * w)
        mat.m33 = 1.0 - 2.0 * (x * x + y * y)
        return mat
    }

    public static func dot(_ q1: Quaternion, _ q2: Quaternion) -> Scalar {
        return q1.x * q2.x + q1.y * q2.y + q1.z * q2.z + q1.w * q2.w
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z, lhs.w + rhs.w)
    }

    public static prefix func - (lhs: Self) -> Self {
        return Self(-lhs.x, -lhs.y, -lhs.z, -lhs.w)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        return Self(rhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z, lhs.w - rhs.w)
    }

    public static func * (lhs: Self, rhs: some BinaryFloatingPoint) -> Self {
        return Self(lhs.x * Scalar(rhs), lhs.y * Scalar(rhs), lhs.z * Scalar(rhs), lhs.w * Scalar(rhs))
    }

    public static func * (lhs: some BinaryFloatingPoint, rhs: Self) -> Self {
        return Self(Scalar(lhs) * rhs.x, Scalar(lhs) * rhs.y, Scalar(lhs) * rhs.z, Scalar(lhs) * rhs.w)
    }

    public static func * (lhs: Quaternion, rhs: Quaternion) -> Quaternion {
        lhs.concatenating(rhs)
    }

    public static func / (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x / rhs.x, lhs.y / rhs.y, lhs.z / rhs.z, lhs.w / rhs.w)
    }

    public static func / (lhs: some BinaryFloatingPoint, rhs: Self) -> Self {
        return Self(Scalar(lhs) / rhs.x, Scalar(lhs) / rhs.y, Scalar(lhs) / rhs.z, Scalar(lhs) / rhs.w)
    }

    public static func slerp(_ q1: Quaternion,
                             _ q2: Quaternion,
                             t: some BinaryFloatingPoint) -> Quaternion {
        var cosHalfTheta = Self.dot(q1, q2)
        let flip = cosHalfTheta < 0.0
        if flip { cosHalfTheta = -cosHalfTheta }

        if cosHalfTheta >= 1.0 { return q1 }    // q1 = q2 or q1 = -q2

        let halfTheta = acos(cosHalfTheta)
        let oneOverSinHalfTheta = 1.0 / sin(halfTheta)

        let t1 = Scalar(t)
        let t2 = 1.0 - t1

        let ratio1 = sin(halfTheta * t2) * oneOverSinHalfTheta
        var ratio2 = sin(halfTheta * t1) * oneOverSinHalfTheta

        if flip { ratio2 = -ratio2 }

        return q1 * ratio1 + q2 * ratio2
    }

    public static func interpolate(_ q1: Quaternion,
                                   _ q2: Quaternion,
                                   _ t: some BinaryFloatingPoint) -> Quaternion {
        return slerp(q1, q2, t: t)
    }

    public func conjugated() -> Quaternion {
        Quaternion(-x, -y, -z, w)
    }

    public mutating func conjugate() {
        self = self.conjugated()
    }

    public func inverted() -> Quaternion {
        let n = self.lengthSquared
        if n > 0.0 {
            return self.conjugated() / n
        }
        return self
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public func concatenating(_ q: Quaternion) -> Quaternion {
        let x = q.w * self.x + q.x * self.w + q.y * self.z - q.z * self.y
        let y = q.w * self.y + q.y * self.w + q.z * self.x - q.x * self.z
        let z = q.w * self.z + q.z * self.w + q.x * self.y - q.y * self.x
        let w = q.w * self.w - q.x * self.x - q.y * self.y - q.z * self.z
        return Quaternion(x, y, z, w)
    }

    public mutating func concatenate(_ q: Quaternion) {
        self = self.concatenating(q)
    }

    public static func minimum(_ lhs: Self, _ rhs: Self) -> Self {
        return Self(min(lhs.x, rhs.x), min(lhs.y, rhs.y), min(lhs.z, rhs.z), min(lhs.w, rhs.w))
    }

    public static func maximum(_ lhs: Self, _ rhs: Self) -> Self {
        return Self(max(lhs.x, rhs.x), max(lhs.y, rhs.y), max(lhs.z, rhs.z), max(lhs.w, rhs.w))
    }
}

public extension Vector3 {
    func rotated(angle: some BinaryFloatingPoint, axis: Vector3) -> Vector3 {
        if angle.isZero { return self }
        return self.rotated(by: Quaternion(angle: angle, axis: axis))
    }

    mutating func rotate(angle: some BinaryFloatingPoint, axis: Vector3) {
        self = self.rotated(angle: angle, axis: axis)
    }

    func rotated(by q: Quaternion) -> Vector3 {
        let vec = Vector3(q.x, q.y, q.z)
        var uv = Self.cross(vec, self)
        var uuv = Self.cross(vec, uv)
        uv *= (2.0 * q.w)
        uuv *= 2.0
        return self + uv + uuv
    }

    mutating func rotate(by q: Quaternion) {
        self = self.rotated(by: q)
    }

    func applying(_ q: Quaternion) -> Vector3 {
        return self.rotated(by: q)
    }

    mutating func apply(_ q: Quaternion) {
        self.rotate(by: q)
    }
}
