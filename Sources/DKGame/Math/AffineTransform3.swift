//
//  File: AffineTransform3.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct AffineTransform3: Hashable {
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

    public var linearTransform: LinearTransform3 {
        get { LinearTransform3(self.matrix3) }
        set(t) { self.matrix3 = t.matrix3 }
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

    public init(linear: Matrix3, origin: Vector3) {
        self.matrix3 = linear
        self.translation = origin
    }

    public init(linear: LinearTransform3, origin: Vector3) {
        self.matrix3 = linear.matrix3
        self.translation = origin
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
        return Self(linear: matrix, origin: origin)
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public func translated(by offset: Vector3) -> Self {
        // | 1 0 0 0 |
        // | 0 1 0 0 |
        // | 0 0 1 0 |
        // | X Y Z 1 |
        return Self(linear: matrix3, origin: self.translation + offset)
    }

    public mutating func translate(by offset: Vector3) {
        self = self.translated(by: offset)
    }

    public func translated<T: BinaryFloatingPoint>(x: T, y: T, z: T) -> Self {
        return self.translated(by: Vector3(x, y, z))
    }

    public mutating func translate<T: BinaryFloatingPoint>(x: T, y: T, z: T) {
        self = self.translated(x: x, y: y, z: z)
    }

    public func concatenating(_ t: LinearTransform3) -> Self {
        return Self(linear: matrix3 * t.matrix3,
                    origin: translation.applying(t.matrix3))
    }

    public mutating func concatenate(_ t: LinearTransform3) {
        self = self.concatenating(t)
    }

    public func concatenating(_ t: Self) -> Self {
        return Self(linear: matrix3 * t.matrix3,
                    origin: translation.applying(t.matrix3) + t.translation)
    }

    public mutating func concatenate(_ t: Self) {
        self = self.concatenating(t)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return lhs.concatenating(rhs)
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs = lhs * rhs
    }

    public static func * (lhs: Self, rhs: LinearTransform3) -> Self {
        return lhs.concatenating(rhs)
    }

    public static func *= (lhs: inout Self, rhs: LinearTransform3) {
        lhs = lhs * rhs
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
