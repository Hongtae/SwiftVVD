//
//  File: Vector.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol Vector {
    var length: Scalar { get }
    var lengthSquared: Scalar { get }

    static var zero: Self { get }

    func normalized()->Self
    mutating func normalize()

    static func dot(_:Self, _:Self) -> Scalar

    static prefix func - (_: Self) -> Self
 
    static func + (_:Self, _:Self) -> Self
    static func - (_:Self, _:Self) -> Self
    static func * (_:Self, _:Self) -> Self
    static func * (_:Self, _:Scalar) -> Self
 
    static func += (_:inout Self, _:Self)
    static func -= (_:inout Self, _:Self)
    static func *= (_:inout Self, _:Self)
    static func *= (_:inout Self, _:Scalar)

    static func == (_:Self, _:Self) -> Bool
    static func != (_:Self, _:Self) -> Bool

    static func minimum(_:Self, _:Self) -> Self
    static func maximum(_:Self, _:Self) -> Self
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

    static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
    static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }
    static func *= (lhs: inout Self, rhs: Scalar) { lhs = lhs * rhs }
    static func != (lhs: Self, rhs: Self) -> Bool { return !(lhs == rhs) }
}
