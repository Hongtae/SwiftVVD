//
//  File: Vector4.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Vector4: Vector {

    public var x : Scalar
    public var y : Scalar
    public var z : Scalar
    public var w : Scalar

    public static let zero = Vector4(0.0, 0.0, 0.0, 0.0)

    subscript(index: Int) -> Scalar {
        get {
            switch index {
            case 0: return self.x
            case 1: return self.y
            case 2: return self.z
            case 3: return self.w
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
            case 3: self.w = value
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    public init() {
        self = .zero
    }

    public init(_ x: Scalar, _ y: Scalar, _ z: Scalar, _ w: Scalar) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public init(x: Scalar, y: Scalar, z: Scalar, w: Scalar) {
        self.init(x, y, z, w)
    }

    public static func dot(_ lhs: Vector4, _ rhs: Vector4) -> Scalar {
    	return (lhs.x * rhs.x) + (lhs.y * rhs.y) + (lhs.z * rhs.z) + (lhs.w * rhs.w)
    }

    public static func cross(_ v1: Vector4, _ v2: Vector4, _ v3: Vector4) -> Vector4 {
        let x =   v1.y * (v2.z * v3.w - v3.z * v2.w) - v1.z * (v2.y * v3.w - v3.y * v2.w) + v1.w * (v2.y * v3.z - v2.z * v3.y)
        let y = -(v1.x * (v2.z * v3.w - v3.z * v2.w) - v1.z * (v2.x * v3.w - v3.x * v2.w) + v1.w * (v2.x * v3.z - v3.x * v2.z))
        let z =   v1.x * (v2.y * v3.w - v3.y * v2.w) - v1.y * (v2.x * v3.w - v3.x * v2.w) + v1.w * (v2.x * v3.y - v3.x * v2.y)
        let w = -(v1.x * (v2.y * v3.z - v3.y * v2.z) - v1.y * (v2.x * v3.z - v3.x * v2.z) + v1.z * (v2.x * v3.y - v3.x * v2.y))  
        return Vector4(x, y, z, w)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z && lhs.w == rhs.w
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z, lhs.w + rhs.w)
    }

    public static prefix func - (lhs: Self) -> Self {
        return Self(-lhs.x, -lhs.y, -lhs.z, -lhs.w)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z, lhs.w - rhs.w)
    }

    public static func * (lhs: Self, rhs: Scalar) -> Self {
        return Self(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs, lhs.w * rhs)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x * rhs.x, lhs.y * rhs.y, lhs.z * rhs.z, lhs.w * rhs.w)
    }

    public static func minimum(_ lhs: Self, _ rhs: Self) -> Self {
        return Self(min(lhs.x, rhs.x), min(lhs.y, rhs.y), min(lhs.z, rhs.z), min(lhs.w, rhs.w))
    }

    public static func maximum(_ lhs: Self, _ rhs: Self) -> Self {
        return Self(max(lhs.x, rhs.x), max(lhs.y, rhs.y), max(lhs.z, rhs.z), max(lhs.w, rhs.w))
    }
}

public extension Vector4 {
    var half4: Half4 {
        get {
            (Float16(self.x), Float16(self.y), Float16(self.z), Float16(self.w))
        }
        set(v) {
            self.x = Scalar(v.0)
            self.y = Scalar(v.1)
            self.z = Scalar(v.2)
            self.w = Scalar(v.3)
        }
    }

    var float4: Float4 {
        get {
            (Float32(self.x), Float32(self.y), Float32(self.z), Float32(self.w))
        }
        set(v) {
            self.x = Scalar(v.0)
            self.y = Scalar(v.1)
            self.z = Scalar(v.2)
            self.w = Scalar(v.3)
        }
    }

    var double4: Double4 {
        get {
            (Float64(self.x), Float64(self.y), Float64(self.z), Float64(self.w))
        }
        set(v) {
            self.x = Scalar(v.0)
            self.y = Scalar(v.1)
            self.z = Scalar(v.2)
            self.w = Scalar(v.3)
        }
    }
}
