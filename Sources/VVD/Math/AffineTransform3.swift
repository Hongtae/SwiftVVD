//
//  File: AffineTransform3.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

public struct AffineTransform3: Hashable, Sendable {
    public typealias Vector = Vector3

    public var matrix3: Matrix3
    public var translation: Vector3

    public var matrix4: Matrix4 {
        get {
            Matrix4(matrix3.m11, matrix3.m12, matrix3.m13, 0.0,
                    matrix3.m21, matrix3.m22, matrix3.m23, 0.0,
                    matrix3.m31, matrix3.m32, matrix3.m33, 0.0,
                    translation.x, translation.y, translation.z, 1.0)            
        }
        set(m) {
            self.matrix3 = .init(m.m11, m.m12, m.m13,
                                 m.m21, m.m22, m.m23,
                                 m.m31, m.m32, m.m33)
            self.translation = .init(m.m41, m.m42, m.m43)
        }
    }

    public static let identity: Self = .init(origin: .zero)

    public init(_ t: Self = .identity) {
        self.matrix3 = t.matrix3
        self.translation = t.translation
    }

    public init(origin: Vector3) {
        self.matrix3 = .identity
        self.translation = origin
    }

    public init(basis: Matrix3, origin: Vector3) {
        self.matrix3 = basis
        self.translation = origin
    }

    public init(matrix4 m: Matrix4) {
        self.matrix3 = .init(m.m11, m.m12, m.m13,
                             m.m21, m.m22, m.m23,
                             m.m31, m.m32, m.m33)
        self.translation = .init(m.m41, m.m42, m.m43)
    }

    public init(axisX x: Vector3, y: Vector3, z: Vector3, origin: Vector3) {
        self.matrix3 = .init(row1: x, row2: y, row3: z)
        self.translation = origin
    }

    public init<T: BinaryFloatingPoint>(x: T, y: T, z: T) {
        self.matrix3 = .identity
        self.translation = .init(x, y, z)
    }

    public func inverted() -> Self {
        let matrix = self.matrix3.inverted() ?? .identity
        let origin = (-translation).applying(matrix)
        return Self(basis: matrix, origin: origin)
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public func translated(by offset: Vector3) -> Self {
        Self(basis: matrix3, origin: self.translation + offset)
    }

    public mutating func translate(by offset: Vector3) {
        self = self.translated(by: offset)
    }

    public func translated<T: BinaryFloatingPoint>(x: T, y: T, z: T) -> Self {
        self.translated(by: Vector3(x, y, z))
    }

    public mutating func translate<T: BinaryFloatingPoint>(x: T, y: T, z: T) {
        self = self.translated(x: x, y: y, z: z)
    }

    public func rotated(by q: Quaternion) -> Self {
        let matrix = self.matrix3.concatenating(q.matrix3)
        let t = translation.applying(q)
        return Self(basis: matrix, origin: t)
    }

    public mutating func rotate(by q: Quaternion) {
        self = self.rotated(by: q)
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

    public func scaled(by v: Vector3) -> Self {
        scaled(x: v.x, y: v.y, z: v.z)
    }

    public func scaled(uniform s: some BinaryFloatingPoint) -> Self {
        scaled(x: s, y: s, z: s)
    }

    public func scaled<T: BinaryFloatingPoint>(x: T, y: T, z: T) -> Self {
        let c1 = self.matrix3.column1 * x
        let c2 = self.matrix3.column2 * y
        let c3 = self.matrix3.column3 * z
        let t = self.translation * Vector3(x, y, z)
        return Self(basis: Matrix3(column1: c1, column2: c2, column3: c3),
                    origin: t)
    }

    public mutating func scale(byVector v: Vector3) {
        self.scale(x: v.x, y: v.y, z: v.z)
    }

    public mutating func scale(uniform s: some BinaryFloatingPoint) {
        self.scale(x: s, y: s, z: s)
    }

    public mutating func scale<T: BinaryFloatingPoint>(x: T, y: T, z: T) {
        self.matrix3.column1 *= x
        self.matrix3.column2 *= y
        self.matrix3.column3 *= z
        self.translation *= Vector3(x, y, z)
    }

    public func applying(_ m: Matrix3) -> Self {
        Self(basis: matrix3.concatenating(m),
             origin: translation.applying(m))
    }

    public mutating func apply(_ m: Matrix3) {
        self = self.applying(m)
    }

    public func concatenating(_ t: Self) -> Self {
        Self(basis: matrix3.concatenating(t.matrix3),
             origin: translation.applying(t.matrix3) + t.translation)
    }

    public mutating func concatenate(_ t: Self) {
        self.matrix3.concatenate(t.matrix3)
        self.translation = self.translation.applying(t.matrix3) + t.translation
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        lhs.concatenating(rhs)
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs.concatenate(rhs)
    }

    public static func * (lhs: Self, rhs: Matrix3) -> Self {
        lhs.applying(rhs)
    }

    public static func *= (lhs: inout Self, rhs: Matrix3) {
        lhs.apply(rhs)
    }
}

public extension AffineTransform3 {
    var linearTransform: LinearTransform3 {
        get { LinearTransform3(self.matrix3) }
        set(t) { self.matrix3 = t.matrix3 }
    }

    init(linear: LinearTransform3, origin: Vector3) {
        self.matrix3 = linear.matrix3
        self.translation = origin
    }

    func applying(_ t: LinearTransform3) -> Self {
        self.applying(t.matrix3)
    }

    mutating func apply(_ t: LinearTransform3) {
        self.apply(t.matrix3)
    }

    static func * (lhs: Self, rhs: LinearTransform3) -> Self {
        lhs.applying(rhs)
    }

    static func *= (lhs: inout Self, rhs: LinearTransform3) {
        lhs.apply(rhs)
    }
}

public extension Vector3 {
    func applying(_ t: AffineTransform3) -> Vector3 {
        self.applying(t.matrix3) + t.translation
    }

    mutating func apply(_ t: AffineTransform3) {
        self = self.applying(t)
    }
}
