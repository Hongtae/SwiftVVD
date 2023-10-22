//
//  File: HStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct HStackLayout: Layout {
    public var alignment: VerticalAlignment
    public var spacing: CGFloat?

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Cache = _StackLayoutCache

    public var animatableData: EmptyAnimatableData

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
        self.animatableData = EmptyAnimatableData()
    }

    public func makeCache(subviews: Subviews) -> Self.Cache {
        var cache = Self.Cache()
        self.updateCache(&cache, subviews: subviews)
        return cache
    }

    public func updateCache(_ cache: inout Self.Cache, subviews: Subviews) {
        cache.priorities = subviews.map { $0.priority }
        cache.spacings = subviews.map { $0.spacing }
        cache.minSizes = subviews.map { $0.sizeThatFits(.zero) }
        cache.maxSizes = subviews.map { $0.sizeThatFits(.infinity) }

        let layoutSpacing: CGFloat = self.spacing ?? 0

        cache.subviewSpacings = cache.spacings.indices.map { index in
            if index > 0 {
                let spacing1 = cache.spacings[index-1]
                let spacing2 = cache.spacings[index]
                let space = spacing2.distance(to: spacing1, along: .horizontal)
                return max(space, layoutSpacing)
            }
            return 0
        }
    }

    public func sizeThatFits(proposal: ProposedViewSize,
                             subviews: Subviews,
                             cache: inout Self.Cache) -> CGSize {
        let size = proposal.replacingUnspecifiedDimensions()
        let spacing = cache.subviewSpacings.reduce(.zero, +)

        let minWidth = cache.minSizes.reduce(CGFloat.zero) { result, size in
            result + size.width
        }

        if proposal == .zero {
            return CGSize(width: minWidth + spacing, height: size.height)
        }

        let fitSizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(height: size.height))
        }

        let fitWidth = fitSizes.reduce(CGFloat.zero) { result, size in
            result + size.width
        }
        let fitHeight = fitSizes.reduce(CGFloat.zero) { result, size in
            max(result, size.height)
        }

        if proposal.width == nil {
            return CGSize(width: fitWidth + spacing, height: fitHeight)
        }

        let maxWidth = cache.maxSizes.reduce(CGFloat.zero) { result, size in
            result + size.width
        }

        let width = min(max(size.width - spacing, fitWidth), maxWidth)
        return CGSize(width: width + spacing, height: fitHeight)
    }

    public func spacing(subviews: Self.Subviews,
                        cache: inout Self.Cache) -> ViewSpacing {
        var spacing = ViewSpacing()
        for index in cache.spacings.indices {
            var edges: Edge.Set = [.top, .bottom]
            if index == 0 { edges.formUnion(.leading) }
            if index == cache.spacings.count - 1 { edges.formUnion(.trailing) }
            spacing.formUnion(cache.spacings[index], edges: edges)
        }
        return spacing
    }

    public func placeSubviews(in bounds: CGRect,
                              proposal: ProposedViewSize,
                              subviews: Subviews,
                              cache: inout Self.Cache) {
        var offset = bounds.origin
        let width = bounds.width
        let height = bounds.height
        var anchor: UnitPoint
        switch self.alignment {
        case .top:
            offset.y = bounds.minY
            anchor = .topLeading
        case .bottom:
            offset.y = bounds.maxY
            anchor = .bottomLeading
        default:
            offset.y = bounds.midY
            anchor = .leading
        }

        let proposalSize = proposal.replacingUnspecifiedDimensions()
        let fitSizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(height: proposalSize.height))
        }

        let fitWidth = fitSizes.reduce(CGFloat.zero) { result, size in
            result + size.width
        }
        let maxWidth = cache.maxSizes.reduce(CGFloat.zero) { result, size in
            result + size.width
        }
        let totalSpacing = cache.subviewSpacings.reduce(.zero, +)

        let layoutWidth = min(maxWidth + totalSpacing, width)
        offset.x += (width - layoutWidth) * 0.5    // center layout

        var restOfFlexibleViews = zip(cache.maxSizes, fitSizes).reduce(Int.zero) {
            count, sizes in
            count + (sizes.0.width > sizes.1.width ? 1 : 0)
        }
        var flexibleSpaces = max(layoutWidth - fitWidth - totalSpacing, 0)

        subviews.indices.forEach { index in
            var fitWidth = fitSizes[index].width
            let maxWidth = cache.maxSizes[index].width

            let flexible = maxWidth > fitWidth
            if flexible && restOfFlexibleViews > 0 {
                let s = max(flexibleSpaces, 0) / CGFloat(restOfFlexibleViews)
                fitWidth += s
                flexibleSpaces -= s
                restOfFlexibleViews -= 1
            }
            offset.x += cache.subviewSpacings[index]

            let proposal = ProposedViewSize(width: fitWidth, height: height)
            subviews[index].place(at: offset,
                                  anchor: anchor,
                                  proposal: proposal)
            let placed = subviews[index].dimensions(in: proposal)

            if flexible {
                flexibleSpaces = flexibleSpaces - (placed.width - fitWidth)
            }
            offset.x += placed.width
        }
    }

    public static var layoutProperties: LayoutProperties {
        LayoutProperties(stackOrientation: .horizontal)
    }
}

public typealias _HStackLayout = HStackLayout
extension _HStackLayout: _VariadicView_UnaryViewRoot {
}
