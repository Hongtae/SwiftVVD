//
//  File: Vector2.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Vector2: Vector, Hashable, Sendable {
    public var x : Scalar
    public var y : Scalar

    public static let zero = Vector2(0.0, 0.0)

    public static var components: Int { 2 }
    
    public subscript(index: Int) -> Scalar {
        get {
            switch index {
            case 0: return self.x
            case 1: return self.y
            default:
                fatalError("Index out of range")
            }
        }
        set (value) {
            switch index {
            case 0: self.x = value
            case 1: self.y = value
            default:
                fatalError("Index out of range")
            }
        }
    }

    public init(_ vector: Self = .zero) {
        self = vector
    }
    
    public init<T: BinaryFloatingPoint>(_ x: T, _ y: T) {
        self.x = Scalar(x)
        self.y = Scalar(y)
    }

    public init<T: BinaryFloatingPoint>(x: T, y: T) {
        self.init(x, y)
    }

    public static func dot(_ v1: Vector2, _ v2: Vector2) -> Scalar {
        return v1.x * v2.x + v1.y * v2.y
    }

    public static func cross(_ v1: Vector2, _ v2: Vector2) -> Scalar {
        return v1.x * v2.y - v1.y * v2.x
    }

    public func rotated(by angle: some BinaryFloatingPoint) -> Self {
        // Rotate
        // | cos  sin|
        // |-sin  cos|
        let a = Scalar(angle)
        let cosR = cos(a)
        let sinR = sin(a)
        return Self(x * cosR - y * sinR, x * sinR + y * cosR)
    }

    public mutating func rotate(by angle: some BinaryFloatingPoint) {
        self = self.rotated(by: angle)
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x + rhs.x, lhs.y + rhs.y)
    }

    public static prefix func - (lhs: Self) -> Self {
        return Self(-lhs.x, -lhs.y)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    public static func * (lhs: Self, rhs: some BinaryFloatingPoint) -> Self {
        return Self(lhs.x * Scalar(rhs), lhs.y * Scalar(rhs))
    }

    public static func * (lhs: some BinaryFloatingPoint, rhs: Self) -> Self {
        return Self(Scalar(lhs) * rhs.x, Scalar(lhs) * rhs.y)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x * rhs.x, lhs.y * rhs.y)
    }

    public static func / (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x / rhs.x, lhs.y / rhs.y)
    }

    public static func / (lhs: some BinaryFloatingPoint, rhs: Self) -> Self {
        return Self(Scalar(lhs) / rhs.x, Scalar(lhs) / rhs.y)
    }

    public static func minimum(_ lhs: Self, _ rhs: Self) -> Self {
        return Self(min(lhs.x, rhs.x), min(lhs.y, rhs.y))
    }

    public static func maximum(_ lhs: Self, _ rhs: Self) -> Self {
        return Self(max(lhs.x, rhs.x), max(lhs.y, rhs.y))
    }
}

public extension Vector2 {
    var half2: Half2 {
        get { (Float16(self.x), Float16(self.y)) }
        set(v) {
            self.x = Scalar(v.0)
            self.y = Scalar(v.1)
        }
    }

    var float2: Float2 {
        get { (Float32(self.x), Float32(self.y)) }
        set(v) {
            self.x = Scalar(v.0)
            self.y = Scalar(v.1)
        }
    }

    var double2: Double2 {
        get { (Float64(self.x), Float64(self.y)) }
        set(v) {
            self.x = Scalar(v.0)
            self.y = Scalar(v.1)
        }
    }

    init(_ v: Half2) {
        self.x = Scalar(v.0)
        self.y = Scalar(v.1)
    }

    init(_ v: Float2) {
        self.x = Scalar(v.0)
        self.y = Scalar(v.1)
    }
    
    init(_ v: Double2) {
        self.x = Scalar(v.0)
        self.y = Scalar(v.1)
    }
}
