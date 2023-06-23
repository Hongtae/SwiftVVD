//
//  File: VStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct VStackLayout: Layout {
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

        let defaultSpacing: CGFloat = max(self.spacing ?? 0, 0)
        var spacing = ViewSpacing()
        var subviewSpacings = CGFloat.zero
        for index in cache.spacings.indices {
            let s = cache.spacings[index]
            if index > 0 && index < cache.spacings.count - 1 {
                let space = max(s.top, spacing.bottom)
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

        let minHeight = cache.minSizes.reduce(CGFloat.zero) { result, size in
            result + size.height
        }

        if proposal == .zero {
            return CGSize(width: size.width, height: minHeight + spacing)
        }

        let proposedSizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: size.width))
        }

        let fitHeight = proposedSizes.reduce(CGFloat.zero) { result, size in
            result + size.height
        }

        if proposal.height == nil {
            return CGSize(width: size.width, height: fitHeight + spacing)
        }

        let maxHeight = cache.maxSizes.reduce(CGFloat.zero) { result, size in
            result + size.height
        }

        let height = min(max(size.height, fitHeight), maxHeight)
        return CGSize(width: size.width, height: height + spacing)
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
        let proposedSizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: proposalSize.width))
        }

        let fitHeight = proposedSizes.reduce(CGFloat.zero, { result, size in
            result + size.height
        })

        var freeSpace = height - fitHeight - cache.subviewSpacings
        var numFlexibleViews = zip(proposedSizes, cache.maxSizes).reduce(Int.zero) {
            count, sizes in
            count + ((sizes.0.height < sizes.1.height) ? 1 : 0)
        }
        let defaultSpacing: CGFloat = self.spacing ?? 0
        var spacing1 = ViewSpacing()
        for index in subviews.indices {
            let maxHeight = cache.maxSizes[index].height
            let fitHeight = proposedSizes[index].height

            let spacing2 = cache.spacings[index]
            if index > 0 && index < subviews.count - 1 {
                let space = max(spacing1.bottom, spacing2.top)
                offset.y += max(space, defaultSpacing)
            }
            spacing1 = spacing2

            var proposal = ProposedViewSize(width: width, height: fitHeight)
            var flexibleSize = false
            if maxHeight > fitHeight && numFlexibleViews > 0 {  // flexible
                if freeSpace > 0 {
                    let f = freeSpace / CGFloat(numFlexibleViews)
                    proposal.height = fitHeight + f
                }
                flexibleSize = true
                numFlexibleViews -= 1
            }
            subviews[index].place(at: offset,
                                  anchor: anchor,
                                  proposal: proposal)
            let placed = subviews[index].dimensions(in: proposal)
            if flexibleSize {
                freeSpace = freeSpace - (placed.height - fitHeight)
            }
            offset.y += placed.height
        }
    }

    static public var layoutProperties: LayoutProperties {
        LayoutProperties(stackOrientation: .vertical)
    }
}

public typealias _VStackLayout = VStackLayout
extension _VStackLayout: _VariadicView_UnaryViewRoot {
}

extension _VStackLayout: _VariadicView_ViewRoot {
}
