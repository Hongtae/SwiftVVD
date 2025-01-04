//
//  File: VStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct VStackLayout : Layout {
    public var alignment: HorizontalAlignment
    public var spacing: CGFloat?

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Cache = _StackLayoutCache

    public var animatableData: EmptyAnimatableData

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) {
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

        let layoutSpacing: CGFloat = self.spacing ?? Self._defaultLayoutSpacing

        cache.subviewSpacings = cache.spacings.indices.map { index in
            if index > 0 {
                let spacing1 = cache.spacings[index-1]
                let spacing2 = cache.spacings[index]
                let space = spacing2.distance(to: spacing1, along: .vertical)
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

        let minHeight = cache.minSizes.reduce(CGFloat.zero) { result, size in
            result + size.height
        }

        if proposal == .zero {
            return CGSize(width: size.width, height: minHeight + spacing)
        }

        let proposalFitSize = ProposedViewSize(width: proposal.width)
        let fitSizes = subviews.map {
            $0.sizeThatFits(proposalFitSize)
        }

        let fitHeight = fitSizes.reduce(CGFloat.zero) { result, size in
            result + size.height
        }
        let fitWidth = fitSizes.reduce(CGFloat.zero) { result, size in
            max(result, size.width)
        }

        if proposal.height == nil {
            return CGSize(width: fitWidth, height: fitHeight + spacing)
        }

        let maxHeight = cache.maxSizes.reduce(CGFloat.zero) { result, size in
            result + size.height
        }

        let height = min(max(size.height - spacing, fitHeight), maxHeight)
        return CGSize(width: fitWidth, height: height + spacing)
    }

    public func spacing(subviews: Self.Subviews,
                        cache: inout Self.Cache) -> ViewSpacing {
        var spacing = ViewSpacing()
        for index in cache.spacings.indices {
            var edges: Edge.Set = [.leading, .trailing]
            if index == 0 { edges.formUnion(.top) }
            if index == cache.spacings.count - 1 { edges.formUnion(.bottom) }
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
        case .leading:
            offset.x = bounds.minX
            anchor = .topLeading
        case .trailing:
            offset.x = bounds.maxX
            anchor = .topTrailing
        default:
            offset.x = bounds.midX
            anchor = .top
        }

        let proposalSize = proposal.replacingUnspecifiedDimensions()
        let fitSizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: proposalSize.width))
        }

        let fitHeight = fitSizes.reduce(CGFloat.zero) { result, size in
            result + size.height
        }
        let maxHeight = cache.maxSizes.reduce(CGFloat.zero) { result, size in
            result + size.height
        }
        let totalSpacing = cache.subviewSpacings.reduce(.zero, +)

        let layoutHeight = min(maxHeight + totalSpacing, height)
        offset.y += (height - layoutHeight) * 0.5    // center layout

        var restOfFlexibleViews = zip(cache.maxSizes, fitSizes).reduce(Int.zero) {
            count, sizes in
            count + (sizes.0.height > sizes.1.height ? 1 : 0)
        }
        var flexibleSpaces = max(layoutHeight - fitHeight - totalSpacing, 0)

        subviews.indices.forEach { index in
            var fitHeight = fitSizes[index].height
            let maxHeight = cache.maxSizes[index].height

            let flexible = maxHeight > fitHeight
            if flexible && restOfFlexibleViews > 0 {
                let s = max(flexibleSpaces, 0) / CGFloat(restOfFlexibleViews)
                fitHeight += s
                flexibleSpaces -= s
                restOfFlexibleViews -= 1
            }
            offset.y += cache.subviewSpacings[index]

            let proposal = ProposedViewSize(width: width, height: fitHeight)
            subviews[index].place(at: offset,
                                  anchor: anchor,
                                  proposal: proposal)
            let placed = subviews[index].dimensions(in: proposal)

            if flexible {
                flexibleSpaces = flexibleSpaces - (placed.height - fitHeight)
            }
            offset.y += placed.height
        }
    }

    public static var layoutProperties: LayoutProperties {
        LayoutProperties(stackOrientation: .vertical)
    }
}


public typealias _VStackLayout = VStackLayout
extension _VStackLayout : _VariadicView_UnaryViewRoot {}
extension _VStackLayout : _VariadicView_ViewRoot {}
extension _VStackLayout : Sendable {}

extension _VStackLayout {
    static var _defaultLayoutSpacing : CGFloat { 8 }
}
