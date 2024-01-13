//
//  File: AffineTransform2.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct AffineTransform2: Hashable {
    public typealias Vector = Vector2

    public var matrix2: Matrix2
    public var translation: Vector2

    public var matrix3: Matrix3 {
        get {
            Matrix3(matrix2.m11, matrix2.m12, 0.0,
                    matrix2.m21, matrix2.m22, 0.0,
                    translation.x, translation.y, 1.0)
        }
        set (m) {
            self.matrix2 = .init(m.m11, m.m12, m.m21, m.m22)
            self.translation = .init(m.m31, m.m32)
        }
    }

    public var linearTransform: LinearTransform2 {
        get { LinearTransform2(self.matrix2) }
        set(t) { self.matrix2 = t.matrix2 }
    }

    public static let identity: Self = .init(origin: .zero)

    public init(_ t: Self = .identity) {
        self.matrix2 = t.matrix2
        self.translation = t.translation
    }

    public init(origin: Vector2) {
        self.matrix2 = .identity
        self.translation = origin
    }

    public init(linear: Matrix2, origin: Vector2 = .zero) {
        self.matrix2 = linear
        self.translation = origin
    }

    public init(linear: LinearTransform2, origin: Vector2 = .zero) {
        self.matrix2 = linear.matrix2
        self.translation = origin
    }

    public init(axisX x: Vector2, y: Vector2, origin: Vector2 = .zero) {
        self.matrix2 = .init(row1: x, row2: y)
        self.translation = origin
    }

    public init<T: BinaryFloatingPoint>(x: T, y: T) {
        self.matrix2 = .identity
        self.translation = .init(x, y)
    }

    public init(_ m: Matrix3) {
        self.matrix2 = .init(m.m11, m.m12, m.m21, m.m22)
        self.translation = .init(m.m31, m.m32)
    }

    public func inverted() -> Self {
        let matrix = self.matrix2.inverted() ?? .identity
        let origin = (-translation).applying(matrix)
        return Self(linear: matrix2, origin: origin)
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public func translated(by offset: Vector2) -> Self {
        // Translate
        // |1  0  0|
        // |0  1  0|
        // |X  Y  1|
        return Self(linear: matrix2, origin: self.translation + offset)        
    }

    public mutating func translate(by offset: Vector2) {
        self = self.translated(by: offset)
    }

    public func translated<T: BinaryFloatingPoint>(x: T, y: T) -> Self {
        return self.translated(by: Vector2(x, y))
    }

    public mutating func translate<T: BinaryFloatingPoint>(x: T, y: T) {
        self = self.translated(x: x, y: y)
    }

    public func concatenating(_ t: LinearTransform2) -> Self {
        return Self(linear: matrix2.concatenating(t.matrix2),
                    origin: translation.applying(t.matrix2))
    }

    public mutating func concatenate(_ t: LinearTransform2) {
        self = self.concatenating(t)
    }

    public func concatenating(_ t: Self) -> Self {
        return Self(linear: matrix2.concatenating(t.matrix2),
                    origin: translation.applying(t.matrix2) + t.translation)
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

    public static func * (lhs: Self, rhs: LinearTransform2) -> Self {
        return lhs.concatenating(rhs)
    }

    public static func *= (lhs: inout Self, rhs: LinearTransform2) {
        lhs = lhs * rhs
    }
}

public extension Vector2 {
    func applying(_ t: AffineTransform2) -> Vector2 {
        self.applying(t.matrix2) + t.translation
    }

    mutating func apply(_ t: AffineTransform2) {
        self = self.applying(t)
    }
}
