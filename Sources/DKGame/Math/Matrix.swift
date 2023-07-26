//
//  File: Matrix.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public protocol Matrix: Equatable {
    associatedtype Vector

    mutating func invert()
    func inverted() -> Self?

    mutating func transpose()
    func transposed() -> Self

    mutating func concatenate(_: Self)
    func concatenating(_: Self) -> Self

    var determinant: Scalar { get }

    subscript(row: Int, column: Int) -> Scalar { get set }
    subscript(row: Int) -> Self.Vector { get set }

    static var identity: Self { get }

    static func + (_: Self, _: Self) -> Self
    static func - (_: Self, _: Self) -> Self
    static func * (_: Self, _: Self) -> Self
    static func * (_: Self, _: any BinaryFloatingPoint) -> Self
    static func / (_: any BinaryFloatingPoint, _: Self) -> Self
    static func / (_: Self, _: any BinaryFloatingPoint) -> Self

    static func += (_: inout Self, _: Self)
    static func -= (_: inout Self, _: Self)
    static func *= (_: inout Self, _: Self)
    static func *= (_: inout Self, _: any BinaryFloatingPoint)
    static func /= (_: inout Self, _: any BinaryFloatingPoint)
}

public extension Matrix {
    mutating func invert()      { self = self.inverted() ?? self }
    mutating func transpose()   { self = self.transposed() }
    mutating func concatenate(_ m: Self) { self = self.concatenating(m) }

    static func != (lhs: Self, rhs: Self) -> Bool { return !(lhs == rhs) }

    static func / (lhs: Self, rhs: any BinaryFloatingPoint) -> Self {
        lhs * (Scalar(1) / Scalar(rhs))
    }
    static func * (lhs : Self, rhs: Self) -> Self {
        lhs.concatenating(rhs)
    }
    static func += (lhs: inout Self, rhs: Self)       { lhs = lhs + rhs }
    static func -= (lhs: inout Self, rhs: Self)       { lhs = lhs - rhs }
    static func *= (lhs: inout Self, rhs: Self)       { lhs = lhs * rhs }
    static func *= (lhs: inout Self, rhs: any BinaryFloatingPoint) {
        lhs = lhs * rhs
    }
    static func /= (lhs: inout Self, rhs: any BinaryFloatingPoint) {
        lhs = lhs / rhs
    }
}
