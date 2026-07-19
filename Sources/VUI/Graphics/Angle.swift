//
//  File: Angle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct Angle: Sendable, Hashable, Codable {
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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        radians = try container.decode(Double.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(radians)
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
        get { radians * 128.0 }
        set { radians = newValue / 128.0 }
    }

    public static var zero: Angle { .init(radians: 0) }
}

public enum Axis: Int8, CaseIterable, Sendable, CustomStringConvertible {
    case horizontal
    case vertical

    var otherAxis: Axis {
        self == .horizontal ? .vertical : .horizontal
    }

    var perpendicularEdges: (min: Edge, max: Edge) {
        self == .vertical ? (.top, .bottom) : (.leading, .trailing)
    }

    init(edge: Edge) {
        switch edge {
        case .top, .bottom:
            self = .vertical
        case .leading, .trailing:
            self = .horizontal
        }
    }

    public var description: String {
        switch self {
        case .horizontal: "horizontal"
        case .vertical: "vertical"
        }
    }

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }

        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)

        init(_ axis: Axis) {
            self = axis == .horizontal ? .horizontal : .vertical
        }

        static var both: Set { [.horizontal, .vertical] }

        func contains(_ axis: Axis) -> Bool {
            contains(Set(axis))
        }

        func isOrthogonal(to other: Set) -> Bool {
            rawValue ^ other.rawValue == Self.both.rawValue
        }
    }
}
