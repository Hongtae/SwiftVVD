//
//  File: Velocity.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _Velocity<Value>: Equatable where Value: Equatable {
    public var valuePerSecond: Value
    @inlinable public init(valuePerSecond: Value) {
        self.valuePerSecond = valuePerSecond
    }
}

extension _Velocity: Sendable where Value: Sendable {
}

extension _Velocity: Comparable where Value: Comparable {
    public static func < (lhs: _Velocity<Value>, rhs: _Velocity<Value>) -> Bool {
        lhs.valuePerSecond < rhs.valuePerSecond
    }
}

extension _Velocity: Hashable where Value: Hashable {
}

extension _Velocity: Animatable where Value: Animatable {
    public typealias AnimatableData = Value.AnimatableData
    public var animatableData: _Velocity<Value>.AnimatableData {
        @inlinable get { return valuePerSecond.animatableData }
        @inlinable set { valuePerSecond.animatableData = newValue }
    }
}

extension _Velocity: AdditiveArithmetic where Value: AdditiveArithmetic {
    @inlinable public init() {
        self.init(valuePerSecond: .zero)
    }
    @inlinable public static var zero: _Velocity<Value> {
        .init(valuePerSecond: .zero)
    }
    @inlinable public static func += (lhs: inout Self, rhs: Self) {
        lhs.valuePerSecond += rhs.valuePerSecond
    }
    @inlinable public static func -= (lhs: inout Self, rhs: Self) {
        lhs.valuePerSecond -= rhs.valuePerSecond
    }
    @inlinable public static func + (lhs: Self, rhs: Self) -> Self {
        var r = lhs
        r += rhs
        return r
    }
    @inlinable public static func - (lhs: Self, rhs: Self) -> Self {
        var r = lhs
        r -= rhs
        return r
    }
}

extension _Velocity: VectorArithmetic where Value: VectorArithmetic {
    @inlinable public mutating func scale(by rhs: Double) {
        valuePerSecond.scale(by: rhs)
    }
    @inlinable public var magnitudeSquared: Double {
        valuePerSecond.magnitudeSquared
    }
}
