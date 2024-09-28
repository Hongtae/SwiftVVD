//
//  File: AffineTransform2.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

public struct AffineTransform2: Hashable, Sendable {
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

    public static let identity: Self = .init(origin: .zero)

    public init(_ t: Self = .identity) {
        self.matrix2 = t.matrix2
        self.translation = t.translation
    }

    public init(origin: Vector2) {
        self.matrix2 = .identity
        self.translation = origin
    }

    public init(basis: Matrix2, origin: Vector2 = .zero) {
        self.matrix2 = basis
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
        return Self(basis: matrix2, origin: origin)
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public func translated(by offset: Vector2) -> Self {
        Self(basis: matrix2, origin: self.translation + offset)        
    }

    public mutating func translate(by offset: Vector2) {
        self = self.translated(by: offset)
    }

    public func translated<T: BinaryFloatingPoint>(x: T, y: T) -> Self {
        self.translated(by: Vector2(x, y))
    }

    public mutating func translate<T: BinaryFloatingPoint>(x: T, y: T) {
        self = self.translated(x: x, y: y)
    }

    public func rotated(by angle: some BinaryFloatingPoint) -> Self {
        let a = Scalar(angle)
        let cosR = cos(a)
        let sinR = sin(a)
        let matrix = Matrix2(cosR, sinR, -sinR, cosR)
        let t = translation.applying(matrix)
        return Self(basis: self.matrix2.concatenating(matrix), origin: t)
    }

    public mutating func rotate(by angle: some BinaryFloatingPoint) {
        self = self.rotated(by: angle)
    }

    public func scaled<T: BinaryFloatingPoint>(x: T, y: T) -> Self {
        var matrix = self.matrix2
        matrix.column1 *= Scalar(x)
        matrix.column2 *= Scalar(y)
        let t = translation * Vector2(x, y)
        return Self(basis: matrix, origin: t)
    }

    public mutating func scale<T: BinaryFloatingPoint>(x: T, y: T) {
        self = self.scaled(x: x, y: y)
    }

    public func scaled(by s: some BinaryFloatingPoint) -> Self {
        self.scaled(x: s, y: s)
    }

    public mutating func scale(by s: some BinaryFloatingPoint) {
        self = self.scaled(by: s)
    }

    public func scaled(by v: Vector2) -> Self {
        self.scaled(x: v.x, y: v.y)
    }

    public mutating func scale(by v: Vector2) {
        self = self.scaled(by: v)
    }

    public func applying(_ m: Matrix2) -> Self {
        Self(basis: matrix2.concatenating(m),
             origin: translation.applying(m))
    }

    public mutating func apply(_ m: Matrix2) {
        self = self.applying(m)
    }

    public func concatenating(_ t: Self) -> Self {
        Self(basis: matrix2.concatenating(t.matrix2),
             origin: translation.applying(t.matrix2) + t.translation)
    }

    public mutating func concatenate(_ t: Self) {
        self.matrix2.concatenate(t.matrix2)
        self.translation = self.translation.applying(t.matrix2) + t.translation
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        lhs.concatenating(rhs)
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs.concatenate(rhs)
    }

    public static func * (lhs: Self, rhs: Matrix2) -> Self {
        lhs.applying(rhs)
    }

    public static func *= (lhs: inout Self, rhs: Matrix2) {
        lhs.apply(rhs)
    }
}

public extension AffineTransform2 {
    var linearTransform: LinearTransform2 {
        get { LinearTransform2(self.matrix2) }
        set(t) { self.matrix2 = t.matrix2 }
    }

    init(linear: LinearTransform2, origin: Vector2 = .zero) {
        self.matrix2 = linear.matrix2
        self.translation = origin
    }

    func applying(_ t: LinearTransform2) -> Self {
        self.applying(t.matrix2)
    }

    mutating func apply(_ t: LinearTransform2) {
        self.apply(t.matrix2)
    }

    static func * (lhs: Self, rhs: LinearTransform2) -> Self {
        lhs.applying(rhs)
    }

    static func *= (lhs: inout Self, rhs: LinearTransform2) {
        lhs.apply(rhs)
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
