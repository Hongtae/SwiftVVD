//
//  File: VStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct VStackLayout: Layout {
    public var alignment: HorizontalAlignment
    public var spacing: CGFloat?

    public typealias Body = Never
    public typealias AnimatableData = EmptyAnimatableData
    public typealias Cache = _StackLayoutCache

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) {
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
                                               axis: .vertical,
                                               explicitSpacing: self.spacing,
                                               horizontalAlignment: self.alignment,
                                               verticalAlignment: nil,
                                               subviews: subviews)
    }

    public func sizeThatFits(proposal: ProposedViewSize,
                             subviews: Subviews,
                             cache: inout Self.Cache) -> CGSize {
        _StackLayoutImplementation.sizeThatFits(axis: .vertical,
                                                proposal: proposal,
                                                subviews: subviews,
                                                cache: &cache)
    }

    public func spacing(subviews: Self.Subviews,
                        cache: inout Self.Cache) -> ViewSpacing {
        _StackLayoutImplementation.spacing(axis: .vertical, cache: cache)
    }

    public func placeSubviews(in bounds: CGRect,
                              proposal: ProposedViewSize,
                              subviews: Subviews,
                              cache: inout Self.Cache) {
        _StackLayoutImplementation.placeSubviews(axis: .vertical,
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
        _StackLayoutImplementation.explicitAlignment(axis: .vertical,
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
        _StackLayoutImplementation.explicitAlignment(axis: .vertical,
                                                     guide: guide.key,
                                                     in: bounds,
                                                     proposal: proposal,
                                                     subviews: subviews,
                                                     cache: &cache)
    }

}


public typealias _VStackLayout = VStackLayout
extension _VStackLayout: _VariadicView_UnaryViewRoot {}
extension _VStackLayout: _VariadicView_ViewRoot {}
extension _VStackLayout: Sendable {}

extension _VStackLayout: HVStack {
    typealias MinorAxisAlignment = HorizontalAlignment

    static var majorAxis: Axis {
        .vertical
    }
}
