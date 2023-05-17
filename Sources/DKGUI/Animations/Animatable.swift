//
//  File: Animatable.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public protocol VectorArithmetic: AdditiveArithmetic {
    mutating func scale(by rhs: Double)
    var magnitudeSquared: Double { get }
}

public protocol Animatable {
    associatedtype AnimatableData : VectorArithmetic
    var animatableData: Self.AnimatableData { get set }
}

extension Animatable where Self: VectorArithmetic {
    public var animatableData: Self { fatalError() }
}

extension Animatable where Self.AnimatableData == EmptyAnimatableData {
    public var animatableData: EmptyAnimatableData { .init() }
}

public struct AnimatablePair<First, Second>: VectorArithmetic where First: VectorArithmetic, Second: VectorArithmetic {
    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public static var zero: AnimatablePair<First, Second> {
        AnimatablePair<First, Second>(.zero, .zero)
    }

    public static func += (lhs: inout AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) {
        lhs = lhs + rhs
    }

    public static func -= (lhs: inout AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) {
        lhs = lhs - rhs
    }

    public static func + (lhs: AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) -> AnimatablePair<First, Second> {
        return AnimatablePair<First, Second>(lhs.first + rhs.first, lhs.second + rhs.second)
    }

    public static func - (lhs: AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) -> AnimatablePair<First, Second> {
        return AnimatablePair<First, Second>(lhs.first - rhs.first, lhs.second - rhs.second)
    }

    public mutating func scale(by rhs: Double) {
        self.first.scale(by: rhs)
        self.second.scale(by: rhs)
    }

    public var magnitudeSquared: Double {
        self.first.magnitudeSquared + self.second.magnitudeSquared
    }
}

extension AnimatablePair: Equatable {
    public static func == (a: AnimatablePair<First, Second>, b: AnimatablePair<First, Second>) -> Bool {
        return a.first == b.first && a.second == b.second
    }
}

extension AnimatablePair: Sendable where First: Sendable, Second: Sendable {
}

private extension VectorArithmetic {
    @inline(__always)
    func add(_ rhs: any VectorArithmetic) -> Self {
        assert(rhs is Self)
        return self + (rhs as! Self)
    }
    @inline(__always)
    func subtract(_ rhs: any VectorArithmetic) -> Self {
        assert(rhs is Self)
        return self - (rhs as! Self)
    }
    @inline(__always)
    func isEqual(to rhs: any VectorArithmetic) -> Bool {
        if let v = rhs as? Self {
            return self == v
        }
        return false
    }
}

public struct _AnyAnimatableData: VectorArithmetic {

    private struct _Zero: VectorArithmetic {
        static func += (_: inout Self, _: Self)     { fatalError() }
        static func -= (_: inout Self, _: Self)     { fatalError() }
        static func + (_: Self, _: Self) -> Self    { fatalError() }
        static func - (_: Self, _: Self) -> Self    { fatalError() }
        static func == (_: Self, _: Self) -> Bool   { fatalError() }
        static var zero: Self { Self() }
        func scale(by: Double) { }
        var magnitudeSquared: Double { 0 }
    }

    var value: any VectorArithmetic

    init(_ value: any VectorArithmetic) {
        self.value = value
    }

    public static var zero: Self {
        Self(_Zero.zero)
    }

    public static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }

    public static func -= (lhs: inout Self, rhs: Self) {
        lhs = lhs - rhs
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        if lhs.value is _Zero { return Self(rhs) }
        if rhs.value is _Zero { return Self(lhs) }
        return Self(lhs.add(rhs))
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        if lhs.value is _Zero {
            var v = rhs.value
            v.scale(by: -1)
            return Self(v)
        }
        if rhs.value is _Zero { return Self(lhs) }
        return Self(lhs.subtract(rhs))
    }

    public mutating func scale(by rhs: Double) {
        self.value.scale(by: rhs)
    }

    public var magnitudeSquared: Double {
        self.value.magnitudeSquared
    }

    public static func == (a: Self, b: Self) -> Bool {
        if a.value is _Zero { return b.magnitudeSquared == 0 }
        if b.value is _Zero { return a.magnitudeSquared == 0 }
        return a.value.isEqual(to: b.value)
    }
}
