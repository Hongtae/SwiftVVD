//
//  File: Matrix3.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct Matrix3: Matrix, Hashable {
    public var m11, m12, m13: Scalar
    public var m21, m22, m23: Scalar
    public var m31, m32, m33: Scalar

    public var row1: Vector3 {
        get { Vector3(x: m11, y: m12, z: m13) }
        set (vector) { 
            m11 = vector.x
            m12 = vector.y
            m13 = vector.z
        }
    }

    public var row2: Vector3 {
        get { Vector3(x: m21, y: m22, z: m23) }
        set (vector) { 
            m21 = vector.x
            m22 = vector.y
            m23 = vector.z
        }
    }

    public var row3: Vector3 {
        get { Vector3(x: m31, y: m32, z: m33) }
        set (vector) { 
            m31 = vector.x
            m32 = vector.y
            m33 = vector.z
        }
    }

    public var column1: Vector3 {
        get { Vector3(x: m11, y: m21, z: m31) }
        set (vector) { 
            m11 = vector.x
            m21 = vector.y
            m31 = vector.z
        }
    }

    public var column2: Vector3 {
        get { Vector3(x: m12, y: m22, z: m32) }
        set (vector) { 
            m12 = vector.x
            m22 = vector.y
            m32 = vector.z
        }
    }

    public var column3: Vector3 {
        get { Vector3(x: m13, y: m23, z: m33) }
        set (vector) { 
            m13 = vector.x
            m23 = vector.y
            m33 = vector.z
        }
    }

    public subscript(row: Int) -> Vector3 {
        get {
            switch row {
            case 0: return self.row1
            case 1: return self.row2
            case 2: return self.row3
            default:
                assertionFailure("Index out of range")
                break
            }
            return .zero
        }
        set (vector) {
            switch row {
            case 0: self.row1 = vector
            case 1: self.row2 = vector
            case 2: self.row3 = vector
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    public subscript(row: Int, column: Int) -> Scalar {
        get {
            switch (row, column) {
            case (0, 0): return m11
            case (0, 1): return m12
            case (0, 2): return m13
            case (1, 0): return m21
            case (1, 1): return m22
            case (1, 2): return m23
            case (2, 0): return m31
            case (2, 1): return m32
            case (2, 2): return m33
            default:
                assertionFailure("Index out of range")
                break
            }
            return 0.0
        }
        set (value) {
            switch (row, column) {
            case (0, 0): m11 = value
            case (0, 1): m12 = value
            case (0, 2): m13 = value
            case (1, 0): m21 = value
            case (1, 1): m22 = value
            case (1, 2): m23 = value
            case (2, 0): m31 = value
            case (2, 1): m32 = value
            case (2, 2): m33 = value
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    public static let identity = Matrix3(1.0, 0.0, 0.0,
                                         0.0, 1.0, 0.0,
                                         0.0, 0.0, 1.0)

    public init(_ matrix: Self = .identity) {
        self = matrix
    }

    public init(_ m11: any BinaryFloatingPoint,
                _ m12: any BinaryFloatingPoint,
                _ m13: any BinaryFloatingPoint,
                _ m21: any BinaryFloatingPoint,
                _ m22: any BinaryFloatingPoint,
                _ m23: any BinaryFloatingPoint,
                _ m31: any BinaryFloatingPoint,
                _ m32: any BinaryFloatingPoint,
                _ m33: any BinaryFloatingPoint) {
        self.m11 = Scalar(m11)
        self.m12 = Scalar(m12)
        self.m13 = Scalar(m13)
        self.m21 = Scalar(m21)
        self.m22 = Scalar(m22)
        self.m23 = Scalar(m23)
        self.m31 = Scalar(m31)
        self.m32 = Scalar(m32)
        self.m33 = Scalar(m33)
    }

    public init(m11: any BinaryFloatingPoint,
                m12: any BinaryFloatingPoint,
                m13: any BinaryFloatingPoint,
                m21: any BinaryFloatingPoint,
                m22: any BinaryFloatingPoint,
                m23: any BinaryFloatingPoint,
                m31: any BinaryFloatingPoint,
                m32: any BinaryFloatingPoint,
                m33: any BinaryFloatingPoint) {
        self.init(m11, m12, m13, m21, m22, m23, m31, m32, m33)
    }

    public init(row1: Vector3, row2: Vector3, row3: Vector3) {
        self.init(row1.x, row1.y, row1.z,
                  row2.x, row2.y, row2.z,
                  row3.x, row3.y, row3.z)
    }

    public init(column1: Vector3, column2: Vector3, column3: Vector3) {
        self.init(column1.x, column2.x, column3.x,
                  column1.y, column2.y, column3.y,
                  column1.z, column2.z, column3.z)
    }

    public var determinant: Scalar {
           return m11 * m22 * m33 + m12 * m23 * m31 +
               m13 * m21 * m32 - m11 * m23 * m32 -
               m12 * m21 * m33 - m13 * m22 * m31
    }

    public var isDiagonal: Bool {
        m12 == 0.0 && m13 == 0.0 &&
        m21 == 0.0 && m23 == 0.0 &&
        m31 == 0.0 && m32 == 0.0
    }

    public func inverted() -> Self? {
        let d = self.determinant
        if d.isZero { return nil }
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

        return Matrix3(m11, m12, m13, 
                       m21, m22, m23,
                       m31, m32, m33)
    }

    public func transposed() -> Self {
        return Matrix3(row1: self.column1,
                       row2: self.column2,
                       row3: self.column3)
    }

    public func concatenating(_ m: Self) -> Self {
        let (row1, row2, row3) = (self.row1, self.row2, self.row3)
        let (col1, col2, col3) = (m.column1, m.column2, m.column3)
        let dot = Vector3.dot
        return Matrix3(dot(row1, col1), dot(row1, col2), dot(row1, col3),
                       dot(row2, col1), dot(row2, col2), dot(row2, col3),
                       dot(row3, col1), dot(row3, col2), dot(row3, col3))
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        return Matrix3(row1: lhs.row1 + rhs.row1,
                       row2: lhs.row2 + rhs.row2,
                       row3: lhs.row3 + rhs.row3)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        return Matrix3(row1: lhs.row1 - rhs.row1,
                       row2: lhs.row2 - rhs.row2,
                       row3: lhs.row3 - rhs.row3)
    }

    public static func * (lhs: Self, rhs: any BinaryFloatingPoint) -> Self {
        return Matrix3(row1: lhs.row1 * rhs, row2: lhs.row2 * rhs, row3: lhs.row3 * rhs)
    }

    public static func / (lhs: any BinaryFloatingPoint, rhs: Self) -> Self {
        return Matrix3(row1: Scalar(lhs) / rhs.row1,
                       row2: Scalar(lhs) / rhs.row2,
                       row3: Scalar(lhs) / rhs.row3)
    }
}

public extension Matrix3 {
    var half: Half3x3 {
        get { (self.row1.half3, self.row2.half3, self.row3.half3) }
        set(v) {
            self.row1.half3 = v.0
            self.row2.half3 = v.1
            self.row3.half3 = v.2
        }
    }

    var float: Float3x3 {
        get { (self.row1.float3, self.row2.float3, self.row3.float3) }
        set(v) {
            self.row1.float3 = v.0
            self.row2.float3 = v.1
            self.row3.float3 = v.2
        }
    }

    var double: Double3x3 {
        get { (self.row1.double3, self.row2.double3, self.row3.double3) }
        set(v) {
            self.row1.double3 = v.0
            self.row2.double3 = v.1
            self.row3.double3 = v.2
        }
    }

    init(_ m: Half3x3) {
        self.init(row1: Vector3(m.0), row2: Vector3(m.1), row3: Vector3(m.2))
    }

    init(_ m: Float3x3) {
        self.init(row1: Vector3(m.0), row2: Vector3(m.1), row3: Vector3(m.2))
    }

    init(_ m: Double3x3) {
        self.init(row1: Vector3(m.0), row2: Vector3(m.1), row3: Vector3(m.2))
    }
}

public extension Vector2 {
    // homogeneous transform
    func applying(_ m: Matrix3) -> Self {
        let v = Vector3(self.x, self.y, 1.0).applying(m)
        assert(abs(v.z) > .leastNonzeroMagnitude)
        return Self(v.x, v.y) * (1.0 / v.z)
    }

    mutating func apply(_ m: Matrix3) {
        self = self.applying(m)
    }
}

public extension Vector3 {
    func applying(_ m: Matrix3) -> Self {
        let x = Self.dot(self, m.column1)
        let y = Self.dot(self, m.column2)
        let z = Self.dot(self, m.column3)
        return Self(x, y, z) 
    }

    mutating func apply(_ m: Matrix3) {
        self = self.applying(m)
    }
}
