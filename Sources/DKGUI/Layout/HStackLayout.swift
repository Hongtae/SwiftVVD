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
        cache.spacings = subviews.map { $0.spacing }
        cache.minSizes = subviews.map { $0.sizeThatFits(.zero) }
        cache.maxSizes = subviews.map { $0.sizeThatFits(.infinity) }

        let defaultSpacing: CGFloat = self.spacing ?? 0
        var spacing = ViewSpacing()
        var subviewSpacings = CGFloat.zero
        for index in cache.spacings.indices {
            let s = cache.spacings[index]
            if index > 0 && index < cache.spacings.count - 1 {
                let space = max(s.leading, spacing.trailing)
                subviewSpacings += max(space, defaultSpacing)
            }
            spacing = s
        }
        cache.subviewSpacings = subviewSpacings
    }

    public func sizeThatFits(proposal: ProposedViewSize,
                             subviews: Subviews,
                             cache: inout Self.Cache) -> CGSize {
        let size = proposal.replacingUnspecifiedDimensions()
        let spacing = cache.subviewSpacings

        let minWidth = cache.minSizes.reduce(CGFloat.zero) { result, size in
            result + size.width
        }

        if proposal == .zero {
            return CGSize(width: minWidth + spacing, height: size.height)
        }

        let proposedSizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(height: size.height))
        }

        let fitWidth = proposedSizes.reduce(CGFloat.zero) { result, size in
            result + size.width
        }

        if proposal.width == nil {
            return CGSize(width: fitWidth + spacing, height: size.height)
        }

        let maxWidth = cache.maxSizes.reduce(CGFloat.zero) { result, size in
            result + size.width
        }

        let width = min(max(size.width, fitWidth), maxWidth)
        return CGSize(width: width + spacing, height: size.height)
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

        let proposalSize = proposal.replacingUnspecifiedDimensions()
        let proposedSizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(height: proposalSize.height))
        }

        let fitWidth = proposedSizes.reduce(CGFloat.zero, { result, size in
            result + size.width
        })

        var freeSpace = width - fitWidth - cache.subviewSpacings
        var numFlexibleViews = zip(proposedSizes, cache.maxSizes).reduce(Int.zero) {
            count, sizes in
            count + ((sizes.0.width < sizes.1.width) ? 1 : 0)
        }
        let defaultSpacing: CGFloat = self.spacing ?? 0
        var spacing1 = ViewSpacing()
        for index in subviews.indices {
            let maxWidth = cache.maxSizes[index].width
            let fitWidth = proposedSizes[index].width

            let spacing2 = cache.spacings[index]
            if index > 0 && index < subviews.count - 1 {
                let space = max(spacing1.trailing, spacing2.leading)
                offset.x += max(space, defaultSpacing)
            }
            spacing1 = spacing2

            var proposal = ProposedViewSize(width: fitWidth, height: height)
            var flexibleSize = false
            if maxWidth > fitWidth && numFlexibleViews > 0 {  // flexible
                if freeSpace > 0 {
                    let f = freeSpace / CGFloat(numFlexibleViews)
                    proposal.width = fitWidth + f
                }
                flexibleSize = true
                numFlexibleViews -= 1
            }
            subviews[index].place(at: offset,
                                  anchor: .topLeading,
                                  proposal: proposal)
            let placed = subviews[index].dimensions(in: proposal)
            if flexibleSize {
                freeSpace = freeSpace - (placed.width - fitWidth)
            }
            offset.x += placed.width
        }
    }
}

public typealias _HStackLayout = HStackLayout
extension _HStackLayout: _VariadicView_UnaryViewRoot {
}
