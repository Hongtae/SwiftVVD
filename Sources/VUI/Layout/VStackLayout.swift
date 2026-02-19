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
        cache.priorities = subviews.map { $0.priority }
        cache.spacings = subviews.map { $0.spacing }
        cache.horizontalAlignment = self.alignment

        cache.subviewSpacings = cache.spacings.indices.map { index in
            if index > 0 {
                if let layoutSpacing = self.spacing {
                    return layoutSpacing
                }
                let spacing1 = cache.spacings[index-1]
                let spacing2 = cache.spacings[index]
                return spacing1.distance(to: spacing2, along: .vertical)
            }
            return 0
        }
    }

    private func layoutHeights(proposal: ProposedViewSize,
                               subviews: Subviews,
                               cache: inout Self.Cache) -> [CGFloat] {
        let fitWidthProposal = ProposedViewSize(width: proposal.width)
        
        let minHeights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: fitWidthProposal.width, height: 0)).height }
        let idealHeights = subviews.map { $0.sizeThatFits(fitWidthProposal).height }
        let maxHeights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: fitWidthProposal.width, height: .infinity)).height }
        
        if proposal.height == nil {
            return idealHeights
        }
        
        let totalSpacing = cache.subviewSpacings.reduce(0, +)
        let totalMinHeight = minHeights.reduce(0, +) + totalSpacing
        let availableHeight = proposal.height!
        
        var currentHeights = minHeights
        var remainingSpace = availableHeight - totalMinHeight
        
        if remainingSpace <= 0 {
            // Insufficient space: all views get minimum height (may clip)
            return minHeights
        }
        
        let priorities = cache.priorities
        let uniquePriorities = Set(priorities).sorted(by: >)
        
        // Phase 1: Grow from min to ideal (high priority first)
        for priority in uniquePriorities {
            var flexibleIndices = subviews.indices.filter {
                priorities[$0] == priority && currentHeights[$0] < idealHeights[$0]
            }
            
            while remainingSpace > 1e-5 && !flexibleIndices.isEmpty {
                let count = CGFloat(flexibleIndices.count)
                let share = remainingSpace / count
                var distributed: CGFloat = 0
                
                for index in flexibleIndices {
                    let limit = idealHeights[index] - currentHeights[index]
                    let give = min(share, limit)
                    currentHeights[index] += give
                    distributed += give
                }
                
                remainingSpace -= distributed
                if distributed < 1e-5 { break }
                
                flexibleIndices = flexibleIndices.filter { currentHeights[$0] < idealHeights[$0] }
            }
        }
        
        // Phase 2: Grow from ideal to max (high priority first)
        for priority in uniquePriorities {
            var flexibleIndices = subviews.indices.filter {
                priorities[$0] == priority && currentHeights[$0] < maxHeights[$0]
            }
            
            while remainingSpace > 1e-5 && !flexibleIndices.isEmpty {
                let count = CGFloat(flexibleIndices.count)
                let share = remainingSpace / count
                var distributed: CGFloat = 0
                
                for index in flexibleIndices {
                    let limit = maxHeights[index] - currentHeights[index]
                    let give = min(share, limit)
                    currentHeights[index] += give
                    distributed += give
                }
                
                remainingSpace -= distributed
                if distributed < 1e-5 { break }
                
                flexibleIndices = flexibleIndices.filter { currentHeights[$0] < maxHeights[$0] }
            }
        }
        
        return currentHeights
    }

    public func sizeThatFits(proposal: ProposedViewSize,
                             subviews: Subviews,
                             cache: inout Self.Cache) -> CGSize {
        let heights = layoutHeights(proposal: proposal, subviews: subviews, cache: &cache)
        let totalSpacing = cache.subviewSpacings.reduce(0, +)
        let totalHeight = heights.reduce(0, +) + totalSpacing
        
        let fitWidthProposal = ProposedViewSize(width: proposal.width)
        let widths = subviews.indices.map { index in
            subviews[index].sizeThatFits(ProposedViewSize(width: fitWidthProposal.width, height: heights[index])).width
        }
        let maxWidth = widths.reduce(0, max)
        
        return CGSize(width: maxWidth, height: totalHeight)
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
        let start = bounds.origin
        
        // Use bounds height for layout calculation
        let actualProposal = ProposedViewSize(width: bounds.width, height: bounds.height)
        let heights = layoutHeights(proposal: actualProposal, subviews: subviews, cache: &cache)
        
        // Pre-calculate max leading and trailing for alignment
        var maxLeading: CGFloat = 0
        var maxTrailing: CGFloat = 0
        var leadings: [CGFloat] = []
        leadings.reserveCapacity(subviews.count)
        
        for index in subviews.indices {
            let childHeight = heights[index]
            let childProposal = ProposedViewSize(width: actualProposal.width, height: childHeight)
            let dimensions = subviews[index].dimensions(in: childProposal)
            
            let leading = dimensions[self.alignment]
            let trailing = dimensions.width - leading
            
            maxLeading = max(maxLeading, leading)
            maxTrailing = max(maxTrailing, trailing)
            
            leadings.append(leading)
        }
        
        let contentWidth = maxLeading + maxTrailing
        // Center the content horizontally within bounds
        let contentLeading = bounds.minX + (bounds.width - contentWidth) * 0.5
        let guideX = contentLeading + maxLeading
        
        var offset = start
        
        for index in subviews.indices {
            offset.y += cache.subviewSpacings[index]
            
            let childHeight = heights[index]
            let childProposal = ProposedViewSize(width: actualProposal.width, height: childHeight)
            
            let leading = leadings[index]
            let x = guideX - leading
            
            subviews[index].place(at: CGPoint(x: x, y: offset.y),
                                  anchor: .topLeading,
                                  proposal: childProposal)
            
            offset.y += childHeight
        }
    }

    public static var layoutProperties: LayoutProperties {
        LayoutProperties(stackOrientation: .vertical)
    }
}


public typealias _VStackLayout = VStackLayout
extension _VStackLayout: _VariadicView_UnaryViewRoot {}
extension _VStackLayout: _VariadicView_ViewRoot {}
extension _VStackLayout: Sendable {}


