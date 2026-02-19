//
//  File: ViewSpacing.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ViewSpacing: Sendable {
    public static let zero = ViewSpacing(top: 0, leading: 0, bottom: 0, trailing: 0)

    static let defaultSpacing: CGFloat = 8

    var top: CGFloat?
    var leading: CGFloat?
    var bottom: CGFloat?
    var trailing: CGFloat?

    public init() {
        self.top = nil
        self.leading = nil
        self.bottom = nil
        self.trailing = nil
    }

    init(top: CGFloat?, leading: CGFloat?, bottom: CGFloat?, trailing: CGFloat?) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public mutating func formUnion(_ other: ViewSpacing, edges: Edge.Set = .all) {
        self = self.union(other, edges: edges)
    }

    public func union(_ other: ViewSpacing, edges: Edge.Set = .all) -> ViewSpacing {
        var result = self
        if edges.contains(.top) {
            let s = self.top ?? Self.defaultSpacing
            let o = other.top ?? Self.defaultSpacing
            result.top = max(s, o)
        }
        if edges.contains(.leading) {
            let s = self.leading ?? Self.defaultSpacing
            let o = other.leading ?? Self.defaultSpacing
            result.leading = max(s, o)
        }
        if edges.contains(.bottom) {
            let s = self.bottom ?? Self.defaultSpacing
            let o = other.bottom ?? Self.defaultSpacing
            result.bottom = max(s, o)
        }
        if edges.contains(.trailing) {
            let s = self.trailing ?? Self.defaultSpacing
            let o = other.trailing ?? Self.defaultSpacing
            result.trailing = max(s, o)
        }
        return result
    }

    public func distance(to next: ViewSpacing, along axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal:
            let trailing = self.trailing ?? Self.defaultSpacing
            let leading = next.leading ?? Self.defaultSpacing
            return max(trailing, leading)
        case .vertical:
            let bottom = self.bottom ?? Self.defaultSpacing
            let top = next.top ?? Self.defaultSpacing
            return max(bottom, top)
        }
    }
}
