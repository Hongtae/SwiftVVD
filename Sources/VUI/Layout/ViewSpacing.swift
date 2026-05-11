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
    static let text = ViewSpacing(textVerticalSpacing: true)

    var top: CGFloat?
    var leading: CGFloat?
    var bottom: CGFloat?
    var trailing: CGFloat?
    var zeroEdges: Edge.Set
    var textVerticalSpacing: Bool

    public init() {
        self.top = nil
        self.leading = nil
        self.bottom = nil
        self.trailing = nil
        self.zeroEdges = []
        self.textVerticalSpacing = false
    }

    init(top: CGFloat?,
         leading: CGFloat?,
         bottom: CGFloat?,
         trailing: CGFloat?,
         zeroEdges: Edge.Set = [],
         textVerticalSpacing: Bool = false) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
        self.zeroEdges = zeroEdges
        self.textVerticalSpacing = textVerticalSpacing
        if top == 0 { self.zeroEdges.insert(.top) }
        if leading == 0 { self.zeroEdges.insert(.leading) }
        if bottom == 0 { self.zeroEdges.insert(.bottom) }
        if trailing == 0 { self.zeroEdges.insert(.trailing) }
    }

    init(textVerticalSpacing: Bool) {
        self.top = nil
        self.leading = nil
        self.bottom = nil
        self.trailing = nil
        self.zeroEdges = []
        self.textVerticalSpacing = textVerticalSpacing
    }

    public mutating func formUnion(_ other: ViewSpacing, edges: Edge.Set = .all) {
        self = self.union(other, edges: edges)
    }

    public func union(_ other: ViewSpacing, edges: Edge.Set = .all) -> ViewSpacing {
        var result = self
        if edges.contains(.top) {
            result.top = unionValue(self.top, other.top)
            if other.zeroEdges.contains(.top) { result.zeroEdges.insert(.top) }
        }
        if edges.contains(.leading) {
            result.leading = unionValue(self.leading, other.leading)
            if other.zeroEdges.contains(.leading) { result.zeroEdges.insert(.leading) }
        }
        if edges.contains(.bottom) {
            result.bottom = unionValue(self.bottom, other.bottom)
            if other.zeroEdges.contains(.bottom) { result.zeroEdges.insert(.bottom) }
        }
        if edges.contains(.trailing) {
            result.trailing = unionValue(self.trailing, other.trailing)
            if other.zeroEdges.contains(.trailing) { result.zeroEdges.insert(.trailing) }
        }
        if edges.contains(.top) || edges.contains(.bottom) {
            result.textVerticalSpacing = result.textVerticalSpacing || other.textVerticalSpacing
        }
        return result
    }

    public func distance(to next: ViewSpacing, along axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal:
            if zeroEdges.contains(.trailing) || next.zeroEdges.contains(.leading) {
                return 0
            }
            let trailing = self.trailing ?? Self.defaultSpacing
            let leading = next.leading ?? Self.defaultSpacing
            return max(trailing, leading)
        case .vertical:
            if zeroEdges.contains(.bottom) || next.zeroEdges.contains(.top) {
                return 0
            }
            // Text-to-text vertical spacing is collapsed until the full spacing
            // category model is implemented.
            if textVerticalSpacing && next.textVerticalSpacing {
                return 0
            }
            let bottom = self.bottom ?? Self.defaultSpacing
            let top = next.top ?? Self.defaultSpacing
            return max(bottom, top)
        }
    }

    private func unionValue(_ lhs: CGFloat?, _ rhs: CGFloat?) -> CGFloat? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }
}
