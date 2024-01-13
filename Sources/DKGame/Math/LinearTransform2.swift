//
//  File: LinearTransform2.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LinearTransform2: Hashable {
    public typealias Vector = Vector2

    public var matrix2: Matrix2

    public static let identity: Self = .init(Matrix2.identity)

    public init(_ t: Self = .identity) {
        self.matrix2 = t.matrix2
    }

    public init(_ matrix: Matrix2) {
        self.matrix2 = matrix
    }

    public init(rotationAngle r: Scalar) {
        self.matrix2 = .identity
        self = self.rotated(by: r)
    }

    public init<T: BinaryFloatingPoint>(scaleX x: T, y: T) {
        self.matrix2 = .init(x, 0.0, 0.0, y)
    }

    public init(axisX x: Vector2, y: Vector2) {
        self.matrix2 = .init(row1: x, row2: y)
    }

    public func rotated(by angle: some BinaryFloatingPoint) -> Self {
        // Rotate
        // | cos  sin|
        // |-sin  cos|
        let a = Scalar(angle)
        let cosR = cos(a)
        let sinR = sin(a)

        let matrix = Matrix2(cosR, sinR, -sinR, cosR)
        return Self(self.matrix2.concatenating(matrix))
    }

    public mutating func rotate(by angle: some BinaryFloatingPoint) {
        self = self.rotated(by: angle)
    }

    public func scaled<T: BinaryFloatingPoint>(x: T, y: T) -> Self {
        // Scale
        // |X  0|
        // |0  Y|
        var matrix = self.matrix2
        matrix.column1 *= Scalar(x)
        matrix.column2 *= Scalar(y)
        return Self(matrix)
    }

    public mutating func scale<T: BinaryFloatingPoint>(x: T, y: T) {
        self = self.scaled(x: x, y: y)
    }

    public func scaled(by s: some BinaryFloatingPoint) -> Self {
        return self.scaled(x: s, y: s)
    }

    public mutating func scale(by s: some BinaryFloatingPoint) {
        self = self.scaled(by: s)
    }

    public func scaled(by v: Vector2) -> Self {
        return self.scaled(x: v.x, y: v.y)
    }

    public mutating func scale(by v: Vector2) {
        self = self.scaled(by: v)
    }

    public func squeezed(by s: some BinaryFloatingPoint) -> Self {
        // Squeeze
        // |S  0  |
        // |0  1/S|
        let s2 = 1.0 / Scalar(s)
        var matrix = self.matrix2
        matrix.column1 *= s
        matrix.column2 *= s2
        return Self(matrix)
    }

    public mutating func squeeze(by s: some BinaryFloatingPoint) {
        self = self.squeezed(by: s)
    }

    public func verticalFlipped() -> Self {
        // Vertical flip
        // |1  0|
        // |0 -1|
        var matrix = self.matrix2
        matrix.column2 *= -1.0
        return Self(matrix)
    }

    public mutating func verticalFlip() {
        self = self.verticalFlipped()
    }

    public func horizontalFlipped() -> Self {
        // Horizontal flip
        // |-1  0|
        // | 0  1|
        var matrix = self.matrix2
        matrix.column1 *= -1.0
        return Self(matrix)
    }

    public mutating func horizontalFlip() {
        self = self.horizontalFlipped()
    }

    public func verticalSheared(by s: some BinaryFloatingPoint) -> Self {
        // Vertical Shear
        // |1  0|
        // |S  1|
        var matrix = self.matrix2
        matrix.column1 += matrix.column2 * s
        return Self(matrix)
    }

    public mutating func verticalShear(by s: some BinaryFloatingPoint) {
        self = self.verticalSheared(by: s)
    }

    public func horizontalSheared(by s: some BinaryFloatingPoint) -> Self {
        // Horizontal Shear
        // |1  S|
        // |0  1|
        var matrix = self.matrix2
        matrix.column2 += matrix.column1 * s
        return Self(matrix)
    }

    public mutating func horizontalShear(by s: some BinaryFloatingPoint) {
        self = self.horizontalSheared(by: s)
    }

    public func inverted() -> Self {
        let matrix = self.matrix2.inverted() ?? .identity
        return Self(matrix)
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public func concatenating(_ m: Matrix2) -> Self {
        return Self(self.matrix2.concatenating(m))
    }

    public mutating func concatenate(_ m: Matrix2) {
        self = self.concatenating(m)
    }

    public func concatenating(_ t: Self) -> Self {
        return Self(self.matrix2.concatenating(t.matrix2))
    }

    public mutating func concatenate(_ t: Self) {
        self = self.concatenating(t)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return lhs.concatenating(rhs)
    }

    public static func * (lhs: Self, rhs: Matrix2) -> Self {
        return lhs.concatenating(rhs)
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs = lhs * rhs
    }

    public static func *= (lhs: inout Self, rhs: Matrix2) {
        lhs = lhs * rhs
    }
}

public extension Vector2 {
    func applying(_ t: LinearTransform2) -> Vector2 {
        self.applying(t.matrix2)
    }

    mutating func apply(_ t: LinearTransform2) {
        self.apply(t.matrix2)
    }
}
