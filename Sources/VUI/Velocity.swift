//
//  File: Velocity.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _Velocity<Value>: Equatable where Value: Equatable {
    public var valuePerSecond: Value
    @inlinable public init(valuePerSecond: Value) {
        self.valuePerSecond = valuePerSecond
    }

    func map<NewValue>(_ transform: (Value) -> NewValue) -> _Velocity<NewValue>
        where NewValue: Equatable {
        _Velocity<NewValue>(valuePerSecond: transform(valuePerSecond))
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

struct VelocitySampler<Value: VectorArithmetic> {
    private static var minimumDistinctSampleInterval: TimeInterval {
        .ulpOfOne
    }

    private var sample1: (value: Value, time: TimeInterval)?
    private var sample2: (value: Value, time: TimeInterval)?
    private var sample3: (value: Value, time: TimeInterval)?
    private(set) var lastTime: TimeInterval?
    private var previousSampleWeight: Double = 0.75

    var isEmpty: Bool {
        sample1 == nil
    }

    init() {
    }

    mutating func addSample(_ value: Value, time: TimeInterval) {
        guard lastTime.map({ time >= $0 }) ?? true else {
            return
        }

        let sample = (value: value, time: time)
        if let lastTime, time - lastTime < Self.minimumDistinctSampleInterval {
            sample1 = sample
            self.lastTime = time
            return
        }

        sample3 = sample2
        sample2 = sample1
        sample1 = sample
        lastTime = time
    }

    mutating func reset() {
        self = VelocitySampler()
    }

    var velocity: _Velocity<Value> {
        guard
            let sample1,
            let sample2,
            let currentVelocity = Self.velocity(from: sample1, relativeTo: sample2)
        else {
            return .zero
        }

        guard
            let sample3,
            let previousVelocity = Self.velocity(from: sample2, relativeTo: sample3)
        else {
            return currentVelocity
        }

        return Self.mix(currentVelocity, previousVelocity, by: previousSampleWeight)
    }

    private static func velocity(
        from sample: (value: Value, time: TimeInterval),
        relativeTo previous: (value: Value, time: TimeInterval)
    ) -> _Velocity<Value>? {
        let deltaTime = sample.time - previous.time
        guard deltaTime > 0 else {
            return nil
        }
        var valuePerSecond = sample.value - previous.value
        valuePerSecond.scale(by: 1 / deltaTime)
        return _Velocity(valuePerSecond: valuePerSecond)
    }

    private static func mix(
        _ first: _Velocity<Value>,
        _ second: _Velocity<Value>,
        by fraction: Double
    ) -> _Velocity<Value> {
        var result = second - first
        result.scale(by: fraction)
        result += first
        return result
    }
}

struct AnimatableVelocitySampler<Value: Animatable> {
    var base: VelocitySampler<Value.AnimatableData>

    init() {
        self.base = VelocitySampler()
    }

    init(base: VelocitySampler<Value.AnimatableData>) {
        self.base = base
    }

    mutating func addSample(_ value: Value, time: TimeInterval) {
        base.addSample(value.animatableData, time: time)
    }

    func velocity(_ value: Value) -> Value {
        var result = value
        result.animatableData = base.velocity.valuePerSecond
        return result
    }
}
