//
//  File: HStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct HStackLayout: Layout {
    public var alignment: VerticalAlignment
    public var spacing: CGFloat?

    public typealias Body = Never
    public typealias AnimatableData = EmptyAnimatableData
    public typealias Cache = _StackLayoutCache

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }

    public func makeCache(subviews: Subviews) -> Self.Cache {
        var cache = Self.Cache()
        self.updateCache(&cache, subviews: subviews)
        return cache
    }

    public func updateCache(_ cache: inout Self.Cache, subviews: Subviews) {
        _StackLayoutImplementation.updateCache(&cache,
                                               axis: .horizontal,
                                               explicitSpacing: self.spacing,
                                               horizontalAlignment: nil,
                                               verticalAlignment: self.alignment,
                                               subviews: subviews)
    }

    public func sizeThatFits(proposal: ProposedViewSize,
                             subviews: Subviews,
                             cache: inout Self.Cache) -> CGSize {
        _StackLayoutImplementation.sizeThatFits(axis: .horizontal,
                                                proposal: proposal,
                                                subviews: subviews,
                                                cache: &cache)
    }

    public func spacing(subviews: Self.Subviews,
                        cache: inout Self.Cache) -> ViewSpacing {
        _StackLayoutImplementation.spacing(axis: .horizontal, cache: cache)
    }

    public func placeSubviews(in bounds: CGRect,
                              proposal: ProposedViewSize,
                              subviews: Subviews,
                              cache: inout Self.Cache) {
        _StackLayoutImplementation.placeSubviews(axis: .horizontal,
                                                 in: bounds,
                                                 proposal: proposal,
                                                 subviews: subviews,
                                                 cache: &cache)
    }

    public func explicitAlignment(of guide: HorizontalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Subviews,
                                  cache: inout Self.Cache) -> CGFloat? {
        _StackLayoutImplementation.explicitAlignment(axis: .horizontal,
                                                     guide: guide.key,
                                                     in: bounds,
                                                     proposal: proposal,
                                                     subviews: subviews,
                                                     cache: &cache)
    }

    public func explicitAlignment(of guide: VerticalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Subviews,
                                  cache: inout Self.Cache) -> CGFloat? {
        _StackLayoutImplementation.explicitAlignment(axis: .horizontal,
                                                     guide: guide.key,
                                                     in: bounds,
                                                     proposal: proposal,
                                                     subviews: subviews,
                                                     cache: &cache)
    }

}

public typealias _HStackLayout = HStackLayout
extension _HStackLayout: _VariadicView_UnaryViewRoot {}
extension _HStackLayout: _VariadicView_ViewRoot {}
extension _HStackLayout: Sendable {}

extension _HStackLayout: HVStack {
    typealias MinorAxisAlignment = VerticalAlignment

    static var majorAxis: Axis {
        .horizontal
    }
}
