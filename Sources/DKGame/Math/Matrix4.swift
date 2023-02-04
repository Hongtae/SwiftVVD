//
//  File: Matrix4.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct Matrix4: Matrix {
    public var m11, m12, m13, m14: Scalar
    public var m21, m22, m23, m24: Scalar
    public var m31, m32, m33, m34: Scalar
    public var m41, m42, m43, m44: Scalar

    public var row1: Vector4 {
        get { Vector4(x: m11, y: m12, z: m13, w: m14) }
        set (vector) { 
            m11 = vector.x
            m12 = vector.y
            m13 = vector.z
            m14 = vector.w
        }
    }

    public var row2: Vector4 {
        get { Vector4(x: m21, y: m22, z: m23, w: m24) }
        set (vector) { 
            m21 = vector.x
            m22 = vector.y
            m23 = vector.z
            m24 = vector.w
        }
    }

    public var row3: Vector4 {
        get { Vector4(x: m31, y: m32, z: m33, w: m34) }
        set (vector) { 
            m31 = vector.x
            m32 = vector.y
            m33 = vector.z
            m34 = vector.w
        }
    }

    public var row4: Vector4 {
        get { Vector4(x: m41, y: m42, z: m43, w: m44) }
        set (vector) { 
            m41 = vector.x
            m42 = vector.y
            m43 = vector.z
            m44 = vector.w
        }
    }

    public var column1: Vector4 {
        get { Vector4(x: m11, y: m21, z: m31, w: m41) }
        set (vector) { 
            m11 = vector.x
            m21 = vector.y
            m31 = vector.z
            m41 = vector.w
        }
    }

    public var column2: Vector4 {
        get { Vector4(x: m12, y: m22, z: m32, w: m42) }
        set (vector) { 
            m12 = vector.x
            m22 = vector.y
            m32 = vector.z
            m42 = vector.w
        }
    }

    public var column3: Vector4 {
        get { Vector4(x: m13, y: m23, z: m33, w: m43) }
        set (vector) { 
            m13 = vector.x
            m23 = vector.y
            m33 = vector.z
            m43 = vector.w
        }
    }

    public var column4: Vector4 {
        get { Vector4(x: m14, y: m24, z: m34, w: m44) }
        set (vector) { 
            m14 = vector.x
            m24 = vector.y
            m34 = vector.z
            m44 = vector.w
        }
    }

    public subscript(row: Int) -> Vector4 {
        get {
            switch row {
            case 0: return self.row1
            case 1: return self.row2
            case 2: return self.row3
            case 3: return self.row4
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
            case 3: self.row4 = vector
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
            case (0, 3): return m14
            case (1, 0): return m21
            case (1, 1): return m22
            case (1, 2): return m23
            case (1, 3): return m24
            case (2, 0): return m31
            case (2, 1): return m32
            case (2, 2): return m33
            case (2, 3): return m34
            case (3, 0): return m41
            case (3, 1): return m42
            case (3, 2): return m43
            case (3, 3): return m44
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
            case (0, 3): m14 = value
            case (1, 0): m21 = value
            case (1, 1): m22 = value
            case (1, 2): m23 = value
            case (1, 3): m24 = value
            case (2, 0): m31 = value
            case (2, 1): m32 = value
            case (2, 2): m33 = value
            case (2, 3): m34 = value
            case (3, 0): m41 = value
            case (3, 1): m42 = value
            case (3, 2): m43 = value
            case (3, 3): m44 = value
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    public static let identity = Matrix4(1.0, 0.0, 0.0, 0.0,
                                         0.0, 1.0, 0.0, 0.0,
                                         0.0, 0.0, 1.0, 0.0,
                                         0.0, 0.0, 0.0, 1.0)

    public init(_ matrix: Self = .identity) {
        self = matrix
    }

    public init(_ m11: any BinaryFloatingPoint,
                _ m12: any BinaryFloatingPoint,
                _ m13: any BinaryFloatingPoint,
                _ m14: any BinaryFloatingPoint,
                _ m21: any BinaryFloatingPoint,
                _ m22: any BinaryFloatingPoint,
                _ m23: any BinaryFloatingPoint,
                _ m24: any BinaryFloatingPoint,
                _ m31: any BinaryFloatingPoint,
                _ m32: any BinaryFloatingPoint,
                _ m33: any BinaryFloatingPoint,
                _ m34: any BinaryFloatingPoint,
                _ m41: any BinaryFloatingPoint,
                _ m42: any BinaryFloatingPoint,
                _ m43: any BinaryFloatingPoint,
                _ m44: any BinaryFloatingPoint) {
        self.m11 = Scalar(m11)
        self.m12 = Scalar(m12)
        self.m13 = Scalar(m13)
        self.m14 = Scalar(m14)
        self.m21 = Scalar(m21)
        self.m22 = Scalar(m22)
        self.m23 = Scalar(m23)
        self.m24 = Scalar(m24)
        self.m31 = Scalar(m31)
        self.m32 = Scalar(m32)
        self.m33 = Scalar(m33)
        self.m34 = Scalar(m34)
        self.m41 = Scalar(m41)
        self.m42 = Scalar(m42)
        self.m43 = Scalar(m43)
        self.m44 = Scalar(m44)
    }

    public init(m11: any BinaryFloatingPoint,
                m12: any BinaryFloatingPoint,
                m13: any BinaryFloatingPoint,
                m14: any BinaryFloatingPoint,
                m21: any BinaryFloatingPoint,
                m22: any BinaryFloatingPoint,
                m23: any BinaryFloatingPoint,
                m24: any BinaryFloatingPoint,
                m31: any BinaryFloatingPoint,
                m32: any BinaryFloatingPoint,
                m33: any BinaryFloatingPoint,
                m34: any BinaryFloatingPoint,
                m41: any BinaryFloatingPoint,
                m42: any BinaryFloatingPoint,
                m43: any BinaryFloatingPoint,
                m44: any BinaryFloatingPoint) {
        self.init(m11, m12, m13, m14,
                  m21, m22, m23, m24,
                  m31, m32, m33, m34,
                  m41, m42, m43, m44)
    }

    public init(row1: Vector4, row2: Vector4, row3: Vector4, row4: Vector4) {
        self.init(row1.x, row1.y, row1.z, row1.w,
                  row2.x, row2.y, row2.z, row2.w,
                  row3.x, row3.y, row3.z, row3.w,
                  row4.x, row4.y, row4.z, row4.w)
    }

    public init(column1: Vector4, column2: Vector4, column3: Vector4, column4: Vector4) {
        self.init(column1.x, column2.x, column3.x, column4.x,
                  column1.y, column2.y, column3.y, column4.y,
                  column1.z, column2.z, column3.z, column4.z,
                  column1.w, column2.w, column3.w, column4.w)
    }

    public var determinant: Scalar {
        return m14 * m23 * m32 * m41 - m13 * m24 * m32 * m41 -
               m14 * m22 * m33 * m41 + m12 * m24 * m33 * m41 +
               m13 * m22 * m34 * m41 - m12 * m23 * m34 * m41 -
               m14 * m23 * m31 * m42 + m13 * m24 * m31 * m42 +
               m14 * m21 * m33 * m42 - m11 * m24 * m33 * m42 -
               m13 * m21 * m34 * m42 + m11 * m23 * m34 * m42 +
               m14 * m22 * m31 * m43 - m12 * m24 * m31 * m43 -
               m14 * m21 * m32 * m43 + m11 * m24 * m32 * m43 +
               m12 * m21 * m34 * m43 - m11 * m22 * m34 * m43 -
               m13 * m22 * m31 * m44 + m12 * m23 * m31 * m44 +
               m13 * m21 * m32 * m44 - m11 * m23 * m32 * m44 -
               m12 * m21 * m33 * m44 + m11 * m22 * m33 * m44
    }

    public var isDiagonal: Bool {
        m12 == 0.0 && m13 == 0.0 && m14 == 0.0 &&
        m21 == 0.0 && m23 == 0.0 && m24 == 0.0 &&
        m31 == 0.0 && m32 == 0.0 && m34 == 0.0 &&
        m41 == 0.0 && m42 == 0.0 && m43 == 0.0
    }

    public func inverted() -> Self? {
        let d = self.determinant
        if d.isZero { return nil }
        let inv = 1.0 / d

        let m11 = (self.m23 * self.m34 * self.m42 - self.m24 * self.m33 * self.m42 + self.m24 * self.m32 * self.m43 - self.m22 * self.m34 * self.m43 - self.m23 * self.m32 * self.m44 + self.m22 * self.m33 * self.m44) * inv
        let m12 = (self.m14 * self.m33 * self.m42 - self.m13 * self.m34 * self.m42 - self.m14 * self.m32 * self.m43 + self.m12 * self.m34 * self.m43 + self.m13 * self.m32 * self.m44 - self.m12 * self.m33 * self.m44) * inv
        let m13 = (self.m13 * self.m24 * self.m42 - self.m14 * self.m23 * self.m42 + self.m14 * self.m22 * self.m43 - self.m12 * self.m24 * self.m43 - self.m13 * self.m22 * self.m44 + self.m12 * self.m23 * self.m44) * inv
        let m14 = (self.m14 * self.m23 * self.m32 - self.m13 * self.m24 * self.m32 - self.m14 * self.m22 * self.m33 + self.m12 * self.m24 * self.m33 + self.m13 * self.m22 * self.m34 - self.m12 * self.m23 * self.m34) * inv
        let m21 = (self.m24 * self.m33 * self.m41 - self.m23 * self.m34 * self.m41 - self.m24 * self.m31 * self.m43 + self.m21 * self.m34 * self.m43 + self.m23 * self.m31 * self.m44 - self.m21 * self.m33 * self.m44) * inv
        let m22 = (self.m13 * self.m34 * self.m41 - self.m14 * self.m33 * self.m41 + self.m14 * self.m31 * self.m43 - self.m11 * self.m34 * self.m43 - self.m13 * self.m31 * self.m44 + self.m11 * self.m33 * self.m44) * inv
        let m23 = (self.m14 * self.m23 * self.m41 - self.m13 * self.m24 * self.m41 - self.m14 * self.m21 * self.m43 + self.m11 * self.m24 * self.m43 + self.m13 * self.m21 * self.m44 - self.m11 * self.m23 * self.m44) * inv
        let m24 = (self.m13 * self.m24 * self.m31 - self.m14 * self.m23 * self.m31 + self.m14 * self.m21 * self.m33 - self.m11 * self.m24 * self.m33 - self.m13 * self.m21 * self.m34 + self.m11 * self.m23 * self.m34) * inv
        let m31 = (self.m22 * self.m34 * self.m41 - self.m24 * self.m32 * self.m41 + self.m24 * self.m31 * self.m42 - self.m21 * self.m34 * self.m42 - self.m22 * self.m31 * self.m44 + self.m21 * self.m32 * self.m44) * inv
        let m32 = (self.m14 * self.m32 * self.m41 - self.m12 * self.m34 * self.m41 - self.m14 * self.m31 * self.m42 + self.m11 * self.m34 * self.m42 + self.m12 * self.m31 * self.m44 - self.m11 * self.m32 * self.m44) * inv
        let m33 = (self.m12 * self.m24 * self.m41 - self.m14 * self.m22 * self.m41 + self.m14 * self.m21 * self.m42 - self.m11 * self.m24 * self.m42 - self.m12 * self.m21 * self.m44 + self.m11 * self.m22 * self.m44) * inv
        let m34 = (self.m14 * self.m22 * self.m31 - self.m12 * self.m24 * self.m31 - self.m14 * self.m21 * self.m32 + self.m11 * self.m24 * self.m32 + self.m12 * self.m21 * self.m34 - self.m11 * self.m22 * self.m34) * inv
        let m41 = (self.m23 * self.m32 * self.m41 - self.m22 * self.m33 * self.m41 - self.m23 * self.m31 * self.m42 + self.m21 * self.m33 * self.m42 + self.m22 * self.m31 * self.m43 - self.m21 * self.m32 * self.m43) * inv
        let m42 = (self.m12 * self.m33 * self.m41 - self.m13 * self.m32 * self.m41 + self.m13 * self.m31 * self.m42 - self.m11 * self.m33 * self.m42 - self.m12 * self.m31 * self.m43 + self.m11 * self.m32 * self.m43) * inv
        let m43 = (self.m13 * self.m22 * self.m41 - self.m12 * self.m23 * self.m41 - self.m13 * self.m21 * self.m42 + self.m11 * self.m23 * self.m42 + self.m12 * self.m21 * self.m43 - self.m11 * self.m22 * self.m43) * inv
        let m44 = (self.m12 * self.m23 * self.m31 - self.m13 * self.m22 * self.m31 + self.m13 * self.m21 * self.m32 - self.m11 * self.m23 * self.m32 - self.m12 * self.m21 * self.m33 + self.m11 * self.m22 * self.m33) * inv

        return Matrix4(m11, m12, m13, m14,
                       m21, m22, m23, m24,
                       m31, m32, m33, m34,
                       m41, m42, m43, m44)
    }

    public func transposed() -> Self {
        return Matrix4(row1: self.column1,
                       row2: self.column2,
                       row3: self.column3,
                       row4: self.column4)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.row1 == rhs.row1 &&
               lhs.row2 == rhs.row2 &&
               lhs.row3 == rhs.row3 &&
               lhs.row4 == rhs.row4
    } 

    public static func + (lhs: Self, rhs: Self) -> Self {
        return Matrix4(row1: lhs.row1 + rhs.row1,
                       row2: lhs.row2 + rhs.row2,
                       row3: lhs.row3 + rhs.row3,
                       row4: lhs.row4 + rhs.row4)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        return Matrix4(row1: lhs.row1 - rhs.row1,
                       row2: lhs.row2 - rhs.row2,
                       row3: lhs.row3 - rhs.row3,
                       row4: lhs.row4 - rhs.row4)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        let row1 = lhs.row1, row2 = lhs.row2, row3 = lhs.row3, row4 = lhs.row4
        let col1 = rhs.column1, col2 = rhs.column2, col3 = rhs.column3, col4 = rhs.column4
        let dot = Vector4.dot
        return Matrix4(dot(row1, col1), dot(row1, col2), dot(row1, col3), dot(row1, col4),
                       dot(row2, col1), dot(row2, col2), dot(row2, col3), dot(row2, col4),
                       dot(row3, col1), dot(row3, col2), dot(row3, col3), dot(row3, col4),
                       dot(row4, col1), dot(row4, col2), dot(row4, col3), dot(row4, col4))
    }

    public static func * (lhs: Self, rhs: any BinaryFloatingPoint) -> Self {
        return Matrix4(row1: lhs.row1 * rhs,
                       row2: lhs.row2 * rhs,
                       row3: lhs.row3 * rhs,
                       row4: lhs.row4 * rhs)
    }
}

public extension Matrix4 {
    var half: Half4x4 {
        get { (self.row1.half4, self.row2.half4, self.row3.half4, self.row4.half4) }
        set(v) {
            self.row1.half4 = v.0
            self.row2.half4 = v.1
            self.row3.half4 = v.2
            self.row4.half4 = v.3
        }
    }

    var float: Float4x4 {
        get { (self.row1.float4, self.row2.float4, self.row3.float4, self.row4.float4) }
        set(v) {
            self.row1.float4 = v.0
            self.row2.float4 = v.1
            self.row3.float4 = v.2
            self.row4.float4 = v.3
        }
    }

    var double: Double4x4 {
        get { (self.row1.double4, self.row2.double4, self.row3.double4, self.row4.double4) }
        set(v) {
            self.row1.double4 = v.0
            self.row2.double4 = v.1
            self.row3.double4 = v.2
            self.row4.double4 = v.3
        }
    }

    init(_ m: Half4x4) {
        self.init(row1: Vector4(m.0), row2: Vector4(m.1), row3: Vector4(m.2), row4: Vector4(m.3))
    }

    init(_ m: Float4x4) {
        self.init(row1: Vector4(m.0), row2: Vector4(m.1), row3: Vector4(m.2), row4: Vector4(m.3))
    }

    init(_ m: Double4x4) {
        self.init(row1: Vector4(m.0), row2: Vector4(m.1), row3: Vector4(m.2), row4: Vector4(m.3))
    }
}

public extension Vector3 {
    // homogeneous transform
    func transformed(by m: Matrix4) -> Self {
        let v = Vector4(self.x, self.y, self.z, 1.0).transformed(by: m)
        assert(abs(v.w) > .leastNonzeroMagnitude)
        return Self(v.x, v.y, v.z) * (1.0 / v.w)
    }

    mutating func transform(by: Matrix4) {
        self = self.transformed(by: by)
    }
}

public extension Vector4 {
    func transformed(by m: Matrix4) -> Self {
        let x = Self.dot(self, m.column1)
        let y = Self.dot(self, m.column2)
        let z = Self.dot(self, m.column3)
        let w = Self.dot(self, m.column4)
        return Self(x, y, z, w)
    }

    mutating func transform(by: Matrix4) {
        self = self.transformed(by: by)
    }

    static func * (lhs: Self, rhs: Matrix4) -> Self {
        return lhs.transformed(by: rhs)
    }

    static func *= (lhs: inout Self, rhs: Matrix4) { lhs = lhs * rhs }
}
