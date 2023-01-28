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

    public var r1: Float = 1
    public var r2: Float = 0
    public var r3: Float = 0
    public var r4: Float = 0
    public var r5: Float = 0

    public var g1: Float = 0
    public var g2: Float = 1
    public var g3: Float = 0
    public var g4: Float = 0
    public var g5: Float = 0

    public var b1: Float = 0
    public var b2: Float = 0
    public var b3: Float = 1
    public var b4: Float = 0
    public var b5: Float = 0

    public var a1: Float = 0
    public var a2: Float = 0
    public var a3: Float = 0
    public var a4: Float = 1
    public var a5: Float = 0

    public init() {
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
