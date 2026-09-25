//
//  File: Edge.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public enum Edge: Int8, CaseIterable, Equatable, Hashable, RawRepresentable {
    case top
    case leading
    case bottom
    case trailing
}

public enum HorizontalEdge: Int8, CaseIterable, Codable, Equatable, Hashable, RawRepresentable {
    case leading
    case trailing

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8

        public init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        public static let leading = Set(rawValue: 1)
        public static let trailing = Set(rawValue: 2)
        public static let all: Set = [.leading, .trailing]

        public init(_ edge: HorizontalEdge) {
            switch edge {
            case .leading:
                self = .leading
            case .trailing:
                self = .trailing
            }
        }
    }
}

public enum VerticalEdge: Int8, CaseIterable, Codable, Equatable, Hashable, RawRepresentable {
    case top
    case bottom

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8

        public init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        public static let top = Set(rawValue: 1)
        public static let bottom = Set(rawValue: 2)
        public static let all: Set = [.top, .bottom]

        public init(_ edge: VerticalEdge) {
            switch edge {
            case .top:
                self = .top
            case .bottom:
                self = .bottom
            }
        }
    }
}

extension Edge {
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) {self.rawValue = rawValue }

        public static let top = Set(rawValue: 1)
        public static let leading = Set(rawValue: 2)
        public static let bottom = Set(rawValue: 4)
        public static let trailing = Set(rawValue: 8)

        public static let all: Set = [.top, .leading, .bottom, .trailing]
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]

        public init(_ e: Edge) {
            switch e {
            case .top:      self = .top
            case .leading:  self = .leading
            case .bottom:   self = .bottom
            case .trailing: self = .trailing
            }
        }
    }
}

extension Edge {
    public enum Corner: Int8, CaseIterable, Hashable, Sendable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing

        public struct Set: OptionSet, Hashable, Sendable {
            public let rawValue: Int8

            public init(rawValue: Int8) {
                self.rawValue = rawValue
            }

            public static let none: Set = []
            public static let topLeading = Set(rawValue: 1)
            public static let topTrailing = Set(rawValue: 2)
            public static let bottomLeading = Set(rawValue: 4)
            public static let bottomTrailing = Set(rawValue: 8)
            public static let all: Set = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
            public static let leading: Set = [.topLeading, .bottomLeading]
            public static let trailing: Set = [.topTrailing, .bottomTrailing]
            public static let bottom: Set = [.bottomLeading, .bottomTrailing]
            public static let top: Set = [.topLeading, .topTrailing]

            public init(_ corner: Corner) {
                self.init(rawValue: 1 << corner.rawValue)
            }

            public func contains(_ corner: Corner) -> Bool {
                contains(Set(corner))
            }
        }
    }
}

public struct EdgeInsets: Equatable, Animatable, _VectorMath {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    @inlinable public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    @inlinable public init() {
        self.top = 0
        self.leading = 0
        self.bottom = 0
        self.trailing = 0
    }

    @usableFromInline
    init(_all: CGFloat) {
        self.top = _all
        self.leading = _all
        self.bottom = _all
        self.trailing = _all
    }

    public typealias AnimatableData = AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>
    public var animatableData: AnimatableData {
        @inlinable get {
            .init(top, .init(leading, .init(bottom, trailing)))
        }
        @inlinable set {
            let top = newValue[].0
            let leading = newValue[].1[].0
            let (bottom, trailing) = newValue[].1[].1[]
            self = .init(
                top: top, leading: leading, bottom: bottom, trailing: trailing)
        }
    }
}

extension Edge: Sendable {    
}

extension EdgeInsets: Sendable {
}

extension EdgeInsets {
    public func inset(by corners: RectangleCornerInsets, edges: Edge.Set = .all) -> EdgeInsets {
        var result = self
        if edges.contains(.top) {
            result.top += max(corners.topLeading.height, corners.topTrailing.height)
        }
        if edges.contains(.leading) {
            result.leading += max(corners.topLeading.width, corners.bottomLeading.width)
        }
        if edges.contains(.bottom) {
            result.bottom += max(corners.bottomLeading.height, corners.bottomTrailing.height)
        }
        if edges.contains(.trailing) {
            result.trailing += max(corners.topTrailing.width, corners.bottomTrailing.width)
        }
        return result
    }

    func `in`(_ edges: Edge.Set) -> EdgeInsets {
        EdgeInsets(
            top: edges.contains(.top) ? top : 0,
            leading: edges.contains(.leading) ? leading : 0,
            bottom: edges.contains(.bottom) ? bottom : 0,
            trailing: edges.contains(.trailing) ? trailing : 0
        )
    }

    func adding(_ other: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: top + other.top,
            leading: leading + other.leading,
            bottom: bottom + other.bottom,
            trailing: trailing + other.trailing
        )
    }

    func xFlipIfRightToLeft(layoutDirection: () -> LayoutDirection) -> EdgeInsets {
        guard layoutDirection() == .rightToLeft else {
            return self
        }
        return EdgeInsets(
            top: top,
            leading: trailing,
            bottom: bottom,
            trailing: leading
        )
    }

    var originOffset: CGSize {
        CGSize(width: leading, height: top)
    }
}
