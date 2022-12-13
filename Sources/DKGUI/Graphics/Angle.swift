//
//  File: Angle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct Angle: Sendable {
    public var radians: Double
    public var degrees: Double {
        get { radians * 180.0 / .pi }
        set { radians = newValue * .pi / 180.0 }
    }
    public init() { radians = 0.0 }
    public init(radians: Double) { self.radians = radians }
    public init(degrees: Double) { self.radians = degrees * .pi / 180.0 }

    public static func radians(_ radians: Double) -> Angle {
        .init(radians: radians)
    }

    public static func degrees(_ degrees: Double) -> Angle {
        .init(degrees: degrees)
    }
}

extension Angle: Hashable, Comparable {
    public static func < (lhs: Angle, rhs: Angle) -> Bool {
        lhs.radians < rhs.radians
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.radians)
    }

    public static func == (a: Angle, b: Angle) -> Bool {
        a.radians == b.radians
    }
}

extension Double: VectorArithmetic {
    public mutating func scale(by rhs: Double) {
        self = self * rhs
    }

    public var magnitudeSquared: Double {
        self
    }
}

extension Angle: Animatable {
    public typealias AnimatableData = Double

    public var animatableData: Double {
        get { 0.0 }
        set { _ = newValue }
    }

    public static var zero: Angle { .init(radians: 0) }
}
