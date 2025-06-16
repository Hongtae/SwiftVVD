//
//  File: VectorMath.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public protocol _VectorMath: Animatable {
}

extension _VectorMath {
    @inlinable public var magnitude: Double {
        get { return animatableData.magnitudeSquared.squareRoot() }
    }
    @inlinable public mutating func negate() {
        animatableData = .zero - animatableData
    }
    @inlinable prefix public static func - (operand: Self) -> Self {
        var result = operand
        result.negate()
        return result
    }
    @inlinable public static func += (lhs: inout Self, rhs: Self) {
        lhs.animatableData += rhs.animatableData
    }
    @inlinable public static func + (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result += rhs
        return result
    }
    @inlinable public static func -= (lhs: inout Self, rhs: Self) {
        lhs.animatableData -= rhs.animatableData
    }
    @inlinable public static func - (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result -= rhs
        return result
    }
    @inlinable public static func *= (lhs: inout Self, rhs: Double) {
        lhs.animatableData.scale(by: rhs)
    }
    @inlinable public static func * (lhs: Self, rhs: Double) -> Self {
        var result = lhs
        result *= rhs
        return result
    }
    @inlinable public static func /= (lhs: inout Self, rhs: Double) {
        lhs *= 1 / rhs
    }
    @inlinable public static func / (lhs: Self, rhs: Double) -> Self {
        var result = lhs
        result /= rhs
        return result
    }
}
