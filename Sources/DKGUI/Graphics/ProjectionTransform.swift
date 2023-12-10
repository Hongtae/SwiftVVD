//
//  File: ProjectionTransform.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ProjectionTransform: Equatable, Sendable {
    public var m11: CGFloat
    public var m12: CGFloat
    public var m13: CGFloat
    public var m21: CGFloat
    public var m22: CGFloat
    public var m23: CGFloat
    public var m31: CGFloat
    public var m32: CGFloat
    public var m33: CGFloat

    public init() {
        (m11, m12, m13) = (1.0, 0.0, 0.0)
        (m21, m22, m23) = (0.0, 1.0, 0.0)
        (m31, m32, m33) = (0.0, 0.0, 1.0)
    }

    public init(_ m: CGAffineTransform) {
        (m11, m12, m13) = (m.a, m.b, 0.0)
        (m21, m22, m23) = (m.c, m.d, 0.0)
        (m31, m32, m33) = (m.tx, m.ty, 1.0)
    }

    public var isIdentity: Bool {
        return m11 == 1.0 && m12 == 0.0 && m13 == 0.0 &&
               m21 == 0.0 && m22 == 1.0 && m23 == 0.0 &&
               m31 == 0.0 && m32 == 0.0 && m33 == 1.0
    }

    public var isAffine: Bool {
        return m31 != 0.0 || m32 != 0.0
    }

    public var determinant: CGFloat {
        m11 * m22 * m33 + m12 * m23 * m31 +
        m13 * m21 * m32 - m11 * m23 * m32 -
        m12 * m21 * m33 - m13 * m22 * m31
    }

    public mutating func invert() -> Bool {
        let d = self.determinant
        if d.isZero {
            return false
        }
        let inv = 1.0 / d
        let m11 = (self.m22 * self.m33 - self.m23 * self.m32) * inv
        let m12 = (self.m13 * self.m32 - self.m12 * self.m33) * inv
        let m13 = (self.m12 * self.m23 - self.m13 * self.m22) * inv
        let m21 = (self.m23 * self.m31 - self.m21 * self.m33) * inv
        let m22 = (self.m11 * self.m33 - self.m13 * self.m31) * inv
        let m23 = (self.m13 * self.m21 - self.m11 * self.m23) * inv
        let m31 = (self.m21 * self.m32 - self.m22 * self.m31) * inv
        let m32 = (self.m12 * self.m31 - self.m11 * self.m32) * inv
        let m33 = (self.m11 * self.m22 - self.m12 * self.m21) * inv

        self.m11 = m11
        self.m12 = m12
        self.m13 = m13
        self.m21 = m21
        self.m22 = m22
        self.m23 = m23
        self.m31 = m31
        self.m32 = m32
        self.m33 = m33
        return true
    }

    public func inverted() -> ProjectionTransform {
        var matrix = self
        _ = matrix.invert()
        return matrix
    }

    public func concatenating(_ rhs: ProjectionTransform) -> ProjectionTransform {
        let row1 = (self.m11, self.m12, self.m13)
        let row2 = (self.m21, self.m22, self.m23)
        let row3 = (self.m31, self.m32, self.m33)
        let col1 = (rhs.m11, rhs.m21, rhs.m31)
        let col2 = (rhs.m12, rhs.m22, rhs.m32)
        let col3 = (rhs.m13, rhs.m23, rhs.m33)
        let dot = {(lhs: (CGFloat, CGFloat, CGFloat),
                    rhs: (CGFloat, CGFloat, CGFloat)) -> CGFloat in
            lhs.0 * rhs.0 + lhs.1 * rhs.1 + lhs.2 * rhs.2
        }
        var mat = ProjectionTransform()
        mat.m11 = dot(row1, col1)
        mat.m12 = dot(row1, col2)
        mat.m13 = dot(row1, col3)
        mat.m21 = dot(row2, col1)
        mat.m22 = dot(row2, col2)
        mat.m23 = dot(row2, col3)
        mat.m31 = dot(row3, col1)
        mat.m32 = dot(row3, col2)
        mat.m33 = dot(row3, col3)
        return mat
    }
}

extension CGPoint {
    public func applying(_ m: ProjectionTransform) -> CGPoint {
        let dot = { (x: CGFloat, y: CGFloat, z: CGFloat) -> CGFloat in
            self.x * x + self.y * y + z
        }
        let x = dot(m.m11, m.m21, m.m31)
        let y = dot(m.m12, m.m22, m.m32)
        let z = dot(m.m13, m.m23, m.m33)
        assert(abs(z) > CGFloat.leastNonzeroMagnitude)
        return CGPoint(x: x / z, y: y / z )
    }
}
