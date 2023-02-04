//
//  File: LinearTransform2.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LinearTransform2: VectorTransformer {
    public typealias Vector = Vector2

    public var matrix2: Matrix2

    public static let identity: Self = .init(Matrix2.identity)

    public init(_ t: Self = .identity) {
        self.matrix2 = t.matrix2
    }

    public init(_ matrix: Matrix2) {
        self.matrix2 = matrix
    }

    public init(rotation: Scalar) {
        self.matrix2 = .identity
        self = self.rotated(by: rotation)
    }

    public init(scaleX: any BinaryFloatingPoint,
                scaleY: any BinaryFloatingPoint) {
        self.matrix2 = .init(scaleX, 0.0, 0.0, scaleY)
    }

    public init(axisX: Vector2, axisY: Vector2) {
        self.matrix2 = .init(row1: axisX, row2: axisY)
    }

    public func rotated(by angle: any BinaryFloatingPoint) -> Self {
        // Rotate
        // | cos  sin|
        // |-sin  cos|
        let a = Scalar(angle)
        let cosR = cos(a)
        let sinR = sin(a)

        let matrix = Matrix2(cosR, sinR, -sinR, cosR)
        return Self(self.matrix2 * matrix)
    }

    public mutating func rotate(by angle: any BinaryFloatingPoint) {
        self = self.rotated(by: angle)
    }

    public func scaled(x: any BinaryFloatingPoint,
                       y: any BinaryFloatingPoint) -> Self {
        // Scale
        // |X  0|
        // |0  Y|
        var matrix = self.matrix2
        matrix.column1 *= Scalar(x)
        matrix.column2 *= Scalar(y)
        return Self(matrix)
    }

    public mutating func scale(x: any BinaryFloatingPoint,
                               y: any BinaryFloatingPoint) {
        self = self.scaled(x: x, y: y)
    }

    public func scaled(by s: any BinaryFloatingPoint) -> Self {
        return self.scaled(x: s, y: s)
    }

    public mutating func scale(by s: any BinaryFloatingPoint) {
        self = self.scaled(by: s)
    }

    public func scaled(by v: Vector2) -> Self {
        return self.scaled(x: v.x, y: v.y)
    }

    public mutating func scale(by v: Vector2) {
        self = self.scaled(by: v)
    }

    public func squeezed(by s: any BinaryFloatingPoint) -> Self {
        // Squeeze
        // |S  0  |
        // |0  1/S|
        let s2 = 1.0 / Scalar(s)
        var matrix = self.matrix2
        matrix.column1 *= s
        matrix.column2 *= s2
        return Self(matrix)
    }

    public mutating func squeeze(by s: any BinaryFloatingPoint) {
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

    public func verticalSheared(by s: any BinaryFloatingPoint) -> Self {
        // Vertical Shear
        // |1  0|
        // |S  1|
        var matrix = self.matrix2
        matrix.column1 += matrix.column2 * s
        return Self(matrix)
    }

    public mutating func verticalShear(by s: any BinaryFloatingPoint) {
        self = self.verticalSheared(by: s)
    }

    public func horizontalSheared(by s: any BinaryFloatingPoint) -> Self {
        // Horizontal Shear
        // |1  S|
        // |0  1|
        var matrix = self.matrix2
        matrix.column2 += matrix.column1 * s
        return Self(matrix)
    }

    public mutating func horizontalShear(by s: any BinaryFloatingPoint) {
        self = self.horizontalSheared(by: s)
    }

    public func inverted() -> Self {
        let matrix = self.matrix2.inverted() ?? .identity
        return Self(matrix)
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public func transformed(by m: Matrix2) -> Self {
        return Self(self.matrix2 * m)
    }

    public mutating func transform(by m: Matrix2) {
        self = self.transformed(by: m)
    }

    public func transformed(by t: LinearTransform2) -> Self {
        return Self(self.matrix2 * t.matrix2)
    }

    public mutating func transform(by t: LinearTransform2) {
        self = self.transformed(by: t)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.matrix2 == rhs.matrix2
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return lhs.transformed(by: rhs)
    }

    public static func * (lhs: Self, rhs: Matrix2) -> Self {
        return lhs.transformed(by: rhs)
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs = lhs * rhs
    }

    public static func *= (lhs: inout Self, rhs: Matrix2) {
        lhs = lhs * rhs
    }

    public static func * (lhs: Vector2, rhs: Self) -> Vector2 {
        return lhs * rhs.matrix2
    }

    public static func *= (lhs: inout Vector2, rhs: Self) {
        lhs = lhs * rhs
    }
}
