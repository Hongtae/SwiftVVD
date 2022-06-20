//
//  File: Vector3.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Vector3: Vector {

    public var x : Scalar
    public var y : Scalar
    public var z : Scalar

    public static let zero = Vector3(0.0, 0.0, 0.0)

    subscript(index: Int) -> Scalar {
        get {
            switch index {
            case 0: return self.x
            case 1: return self.y
            case 2: return self.z
            default:
                assertionFailure("Index out of range")
                break
            }
            return .zero
        }
        set (value) {
            switch index {
            case 0: self.x = value
            case 1: self.y = value
            case 2: self.z = value
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    public init() {
        self = .zero
    }

    public init(_ x: Scalar, _ y: Scalar, _ z: Scalar) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(x: Scalar, y: Scalar, z: Scalar) {
        self.init(x, y, z)
    }

    public static func dot(_ v1: Vector3, _ v2: Vector3) -> Scalar {
        return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
    }

    public static func cross(_ v1: Vector3, _ v2: Vector3) -> Vector3 {
        return Vector3(x: v1.y * v2.z - v1.z * v2.y,
                       y: v1.z * v2.x - v1.x * v2.z,
                       z: v1.x * v2.y - v1.y * v2.x)
    }

    public func rotated(x radian: Scalar) -> Vector3 {
        if radian.isZero  { return self }
        let c = cos(radian)
        let s = sin(radian)
        
        let y = self.y * c - self.z * s
        let z = self.y * s + self.z * c
        return Vector3(self.x, y, z)
    }

    public func rotated(y radian: Scalar) -> Vector3 {
        if radian.isZero { return self }
        let c = cos(radian)
        let s = sin(-radian)

        let x = self.x * c - self.z * s
        let z = self.x * s + self.z * c
        return Vector3(x, self.y, z)
    }

    public func rotated(z radian: Scalar) -> Vector3 {
        if radian.isZero { return self }
        let c = cos(radian)
        let s = sin(radian)

        let x = self.x * c - self.y * s
        let y = self.x * s + self.y * c
        return Vector3(x, y, self.z)
    }

    public mutating func rotate(x radian: Scalar) {
        self = self.rotated(x: radian)
    }

    public mutating func rotate(y radian: Scalar) {
        self = self.rotated(y: radian)
    }

    public mutating func rotate(z radian: Scalar) {
        self = self.rotated(z: radian)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    public static prefix func - (lhs: Self) -> Self {
        return Self(-lhs.x, -lhs.y, -lhs.z)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    public static func * (lhs: Self, rhs: Scalar) -> Self {
        return Self(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x * rhs.x, lhs.y * rhs.y, lhs.z * rhs.z)
    }

    public static func minimum(_ lhs: Self, _ rhs: Self) -> Self {
        return Self(min(lhs.x, rhs.x), min(lhs.y, rhs.y), min(lhs.z, rhs.z))
    }

    public static func maximum(_ lhs: Self, _ rhs: Self) -> Self {
        return Self(max(lhs.x, rhs.x), max(lhs.y, rhs.y), max(lhs.z, rhs.z))
    }
}

public extension Vector3 {
    var half3: Half3 {
        get {
            (Float16(self.x), Float16(self.y), Float16(self.z))
        }
        set(v) {
            self.x = Scalar(v.0)
            self.y = Scalar(v.1)
            self.z = Scalar(v.2)
        }
    }

    var float3: Float3 {
        get {
            (Float32(self.x), Float32(self.y), Float32(self.z))
        }
        set(v) {
            self.x = Scalar(v.0)
            self.y = Scalar(v.1)
            self.z = Scalar(v.2)
        }
    }

    var double3: Double3 {
        get {
            (Float64(self.x), Float64(self.y), Float64(self.z))
        }
        set(v) {
            self.x = Scalar(v.0)
            self.y = Scalar(v.1)
            self.z = Scalar(v.2)
        }
    }
}
