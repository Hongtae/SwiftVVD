//
//  File: VectorMath.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol VectorArithmetic: AdditiveArithmetic {
    mutating func scale(by rhs: Double)
    var magnitudeSquared: Double { get }
}

extension VectorArithmetic {
    public func scaled(by rhs: Double) -> Self {
        var result = self
        result.scale(by: rhs)
        return result
    }

    public mutating func interpolate(towards other: Self, amount: Double) {
        var result = other
        result -= self
        result.scale(by: amount)
        result += self
        self = result
    }

    public func interpolated(towards other: Self, amount: Double) -> Self {
        var result = self
        result.interpolate(towards: other, amount: amount)
        return result
    }
}

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
