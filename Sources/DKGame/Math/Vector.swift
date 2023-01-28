//
//  File: Vector.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public protocol Vector: Hashable {
    associatedtype Scalar: BinaryFloatingPoint
    
    var length: Scalar { get }
    var lengthSquared: Scalar { get }

    static var zero: Self { get }

    func normalized()->Self
    mutating func normalize()

    static func dot(_:Self, _:Self) -> Scalar

    static prefix func - (_: Self) -> Self
 
    static func + (_: Self, _: Self) -> Self
    static func - (_: Self, _: Self) -> Self
    static func * (_: Self, _: Self) -> Self
    static func * (_: Self, _: any BinaryFloatingPoint) -> Self
 
    static func += (_: inout Self, _: Self)
    static func -= (_: inout Self, _: Self)
    static func *= (_: inout Self, _: Self)
    static func *= (_: inout Self, _: any BinaryFloatingPoint)

    static func == (_: Self, _: Self) -> Bool
    static func != (_: Self, _: Self) -> Bool

    static func minimum(_: Self, _: Self) -> Self
    static func maximum(_: Self, _: Self) -> Self

    static func interpolate(_: Self, _: Self, _: any BinaryFloatingPoint) -> Self
}

public extension Vector {
    var length: Scalar              { self.lengthSquared.squareRoot() }
    var lengthSquared: Scalar       { Self.dot(self, self) }

    var magnitude: Scalar           { self.length }
    var magnitudeSquared: Scalar    { self.lengthSquared }

    func dot(_ v: Self) -> Scalar   { Self.dot(self, v) }

    func normalized()->Self {
        let lengthSq = self.lengthSquared
        if lengthSq.isZero == false {
            return self * (1.0 / lengthSq.squareRoot())
        }
        return self
    }    

    mutating func normalize() {
        self = self.normalized()
    }

    static func lerp(_ lhs: Self, _ rhs: Self, _ t: any BinaryFloatingPoint) -> Self {
        let t = Scalar(t)
        return lhs * (1.0 - t) + rhs * t
    }

    static func interpolate(_ lhs: Self, _ rhs: Self, _ t: any BinaryFloatingPoint) -> Self {
        lerp(lhs, rhs, t)
    }

    static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
    static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }
    static func *= (lhs: inout Self, rhs: any BinaryFloatingPoint) { lhs = lhs * rhs }
    static func != (lhs: Self, rhs: Self) -> Bool { return !(lhs == rhs) }
}
