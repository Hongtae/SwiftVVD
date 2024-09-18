//
//  File: Angle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct Angle {
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

extension Angle: Comparable {
    public static func < (lhs: Angle, rhs: Angle) -> Bool {
        lhs.radians < rhs.radians
    }
}

extension Angle: Animatable, _VectorMath {
    public typealias AnimatableData = Double

    public var animatableData: Double {
        get { radians }
        set { radians = newValue }
    }

    public static var zero: Angle { .init(radians: 0) }
}

public enum Axis: Int8, CaseIterable  {
    case horizontal
    case vertical

    public struct Set: OptionSet {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }

        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)
    }
}
