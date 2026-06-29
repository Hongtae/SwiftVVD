//
//  File: ColorMatrix.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//


/*

 | R' |     | r1 r2 r3 r4 r5 |   | R |
 | G' |     | g1 g2 g3 g4 g5 |   | G |
 | B' |  =  | b1 b2 b3 b4 b5 | * | B |
 | A' |     | a1 a2 a3 a4 a5 |   | A |
 | 1  |     | 0  0  0  0  1  |   | 1 |

  R' = r1 ✕ R + r2 ✕ G + r3 ✕ B + r4 ✕ A + r5
  G' = g1 ✕ R + g2 ✕ G + g3 ✕ B + g4 ✕ A + g5
  B' = b1 ✕ R + b2 ✕ G + b3 ✕ B + b4 ✕ A + b5
  A' = a1 ✕ R + a2 ✕ G + a3 ✕ B + a4 ✕ A + a5

 */

public struct ColorMatrix: Equatable, Sendable {

    public var r1: Float
    public var r2: Float
    public var r3: Float
    public var r4: Float
    public var r5: Float

    public var g1: Float
    public var g2: Float
    public var g3: Float
    public var g4: Float
    public var g5: Float

    public var b1: Float
    public var b2: Float
    public var b3: Float
    public var b4: Float
    public var b5: Float

    public var a1: Float
    public var a2: Float
    public var a3: Float
    public var a4: Float
    public var a5: Float

    public init() {
        self.r1 = 1
        self.r2 = 0
        self.r3 = 0
        self.r4 = 0
        self.r5 = 0
        self.g1 = 0
        self.g2 = 1
        self.g3 = 0
        self.g4 = 0
        self.g5 = 0
        self.b1 = 0
        self.b2 = 0
        self.b3 = 1
        self.b4 = 0
        self.b5 = 0
        self.a1 = 0
        self.a2 = 0
        self.a3 = 0
        self.a4 = 1
        self.a5 = 0
    }

    static var identity: ColorMatrix { ColorMatrix() }

    static var zero: ColorMatrix {
        var cm = ColorMatrix()
        cm.r1 = 0
        cm.g2 = 0
        cm.b3 = 0
        cm.a4 = 0
        return cm
    }

    static func constantColor(_ color: Color) -> ColorMatrix {
        var cm = ColorMatrix.zero
        cm.r5 = Float(color.provider.red)
        cm.g5 = Float(color.provider.green)
        cm.b5 = Float(color.provider.blue)
        cm.a5 = Float(color.provider.alpha)
        return cm
    }

    func concatenating(_ m: Self) -> Self {
        typealias V = (Float, Float, Float, Float, Float)
        let dot = { (v1: V, v2: V) -> Float in
            v1.0 * v2.0 + v1.1 * v2.1 + v1.2 * v2.2 + v1.3 * v2.3 + v1.4 * v2.4
        }

        let row1: V = (self.r1, self.r2, self.r3, self.r4, self.r5)
        let row2: V = (self.g1, self.g2, self.g3, self.g4, self.g5)
        let row3: V = (self.b1, self.b2, self.b3, self.b4, self.b5)
        let row4: V = (self.a1, self.a2, self.a3, self.a4, self.a5)

        let col1: V = (m.r1, m.g1, m.b1, m.a1, 0)
        let col2: V = (m.r2, m.g2, m.b2, m.a2, 0)
        let col3: V = (m.r3, m.g3, m.b3, m.a3, 0)
        let col4: V = (m.r4, m.g4, m.b4, m.a4, 0)
        let col5: V = (m.r5, m.g5, m.b5, m.a5, 1)

        var matrix = ColorMatrix()

        matrix.r1 = dot(row1, col1)
        matrix.r2 = dot(row1, col2)
        matrix.r3 = dot(row1, col3)
        matrix.r4 = dot(row1, col4)
        matrix.r5 = dot(row1, col5)

        matrix.g1 = dot(row2, col1)
        matrix.g2 = dot(row2, col2)
        matrix.g3 = dot(row2, col3)
        matrix.g4 = dot(row2, col4)
        matrix.g5 = dot(row2, col5)

        matrix.b1 = dot(row3, col1)
        matrix.b2 = dot(row3, col2)
        matrix.b3 = dot(row3, col3)
        matrix.b4 = dot(row3, col4)
        matrix.b5 = dot(row3, col5)

        matrix.a1 = dot(row4, col1)
        matrix.a2 = dot(row4, col2)
        matrix.a3 = dot(row4, col3)
        matrix.a4 = dot(row4, col4)
        matrix.a5 = dot(row4, col5)

        return matrix
    }
}

public struct _ColorMatrix: Equatable, Codable, Sendable {
    public var m11: Float
    public var m12: Float
    public var m13: Float
    public var m14: Float
    public var m15: Float

    public var m21: Float
    public var m22: Float
    public var m23: Float
    public var m24: Float
    public var m25: Float

    public var m31: Float
    public var m32: Float
    public var m33: Float
    public var m34: Float
    public var m35: Float

    public var m41: Float
    public var m42: Float
    public var m43: Float
    public var m44: Float
    public var m45: Float

    @inlinable public init() {
        self.m11 = 1
        self.m12 = 0
        self.m13 = 0
        self.m14 = 0
        self.m15 = 0
        self.m21 = 0
        self.m22 = 1
        self.m23 = 0
        self.m24 = 0
        self.m25 = 0
        self.m31 = 0
        self.m32 = 0
        self.m33 = 1
        self.m34 = 0
        self.m35 = 0
        self.m41 = 0
        self.m42 = 0
        self.m43 = 0
        self.m44 = 1
        self.m45 = 0
    }

    public init(color: Color, in environment: EnvironmentValues) {
        self.init()
        let resolved = color.resolve(in: environment)
        self.m11 = resolved.linearRed
        self.m22 = resolved.linearGreen
        self.m33 = resolved.linearBlue
        self.m44 = resolved.opacity
    }

    init(_ matrix: ColorMatrix) {
        self.m11 = matrix.r1
        self.m12 = matrix.r2
        self.m13 = matrix.r3
        self.m14 = matrix.r4
        self.m15 = matrix.r5
        self.m21 = matrix.g1
        self.m22 = matrix.g2
        self.m23 = matrix.g3
        self.m24 = matrix.g4
        self.m25 = matrix.g5
        self.m31 = matrix.b1
        self.m32 = matrix.b2
        self.m33 = matrix.b3
        self.m34 = matrix.b4
        self.m35 = matrix.b5
        self.m41 = matrix.a1
        self.m42 = matrix.a2
        self.m43 = matrix.a3
        self.m44 = matrix.a4
        self.m45 = matrix.a5
    }

    var colorMatrix: ColorMatrix {
        var matrix = ColorMatrix()
        matrix.r1 = m11
        matrix.r2 = m12
        matrix.r3 = m13
        matrix.r4 = m14
        matrix.r5 = m15
        matrix.g1 = m21
        matrix.g2 = m22
        matrix.g3 = m23
        matrix.g4 = m24
        matrix.g5 = m25
        matrix.b1 = m31
        matrix.b2 = m32
        matrix.b3 = m33
        matrix.b4 = m34
        matrix.b5 = m35
        matrix.a1 = m41
        matrix.a2 = m42
        matrix.a3 = m43
        matrix.a4 = m44
        matrix.a5 = m45
        return matrix
    }

    public static func * (a: _ColorMatrix, b: _ColorMatrix) -> _ColorMatrix {
        _ColorMatrix(a.colorMatrix.concatenating(b.colorMatrix))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(m11)
        try container.encode(m12)
        try container.encode(m13)
        try container.encode(m14)
        try container.encode(m15)
        try container.encode(m21)
        try container.encode(m22)
        try container.encode(m23)
        try container.encode(m24)
        try container.encode(m25)
        try container.encode(m31)
        try container.encode(m32)
        try container.encode(m33)
        try container.encode(m34)
        try container.encode(m35)
        try container.encode(m41)
        try container.encode(m42)
        try container.encode(m43)
        try container.encode(m44)
        try container.encode(m45)
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.m11 = try container.decode(Float.self)
        self.m12 = try container.decode(Float.self)
        self.m13 = try container.decode(Float.self)
        self.m14 = try container.decode(Float.self)
        self.m15 = try container.decode(Float.self)
        self.m21 = try container.decode(Float.self)
        self.m22 = try container.decode(Float.self)
        self.m23 = try container.decode(Float.self)
        self.m24 = try container.decode(Float.self)
        self.m25 = try container.decode(Float.self)
        self.m31 = try container.decode(Float.self)
        self.m32 = try container.decode(Float.self)
        self.m33 = try container.decode(Float.self)
        self.m34 = try container.decode(Float.self)
        self.m35 = try container.decode(Float.self)
        self.m41 = try container.decode(Float.self)
        self.m42 = try container.decode(Float.self)
        self.m43 = try container.decode(Float.self)
        self.m44 = try container.decode(Float.self)
        self.m45 = try container.decode(Float.self)
    }
}

extension Color {
    public func applying(_ m: ColorMatrix) -> Color {
        let r = Float(provider.red)
        let g = Float(provider.green)
        let b = Float(provider.blue)
        let a = Float(provider.alpha)

        let r1 = m.r1 * r + m.r2 * g + m.r3 * b + m.r4 * a + m.r5
        let g1 = m.g1 * r + m.g2 * g + m.g3 * b + m.g4 * a + m.g5
        let b1 = m.b1 * r + m.b2 * g + m.b3 * b + m.b4 * a + m.b5
        let a1 = m.a1 * r + m.a2 * g + m.a3 * b + m.a4 * a + m.a5

        return Color(red: Double(r1),
                     green: Double(g1),
                     blue: Double(b1),
                     opacity: Double(a1))
    }
}
