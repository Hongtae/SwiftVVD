//
//  File: ViewSpacing.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ViewSpacing: Sendable {
    public static let zero = ViewSpacing()

    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat

    public init() {
        self.init(top: 0, leading: 0, bottom: 0, trailing: 0)
    }

    init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public mutating func formUnion(_ other: ViewSpacing, edges: Edge.Set = .all) {
        self = self.union(other, edges: edges)
    }

    public func union(_ other: ViewSpacing, edges: Edge.Set = .all) -> ViewSpacing {
        var top = self.top
        var leading = self.leading
        var bottom = self.bottom
        var trailing = self.trailing

        if edges.contains(.top) { top = max(top, other.top) }
        if edges.contains(.leading) { leading = max(leading, other.leading) }
        if edges.contains(.bottom) { bottom = max(bottom, other.bottom) }
        if edges.contains(.trailing) { trailing = max(trailing, other.trailing) }

        return ViewSpacing(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    public func distance(to next: ViewSpacing, along axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal:
            return max(self.trailing, next.leading)
        case .vertical:
            return max(self.bottom, next.top)
        }
    }
}
