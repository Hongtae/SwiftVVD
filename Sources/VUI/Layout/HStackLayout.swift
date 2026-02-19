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
        cache.priorities = subviews.map { $0.priority }
        cache.spacings = subviews.map { $0.spacing }
        cache.verticalAlignment = self.alignment

        cache.subviewSpacings = cache.spacings.indices.map { index in
            if index > 0 {
                if let layoutSpacing = self.spacing {
                    return layoutSpacing
                }
                let spacing1 = cache.spacings[index-1]
                let spacing2 = cache.spacings[index]
                return spacing1.distance(to: spacing2, along: .horizontal)
            }
            return 0
        }
    }

    private func layoutWidths(proposal: ProposedViewSize,
                              subviews: Subviews,
                              cache: inout Self.Cache) -> [CGFloat] {
        let fitHeightProposal = ProposedViewSize(height: proposal.height)
        
        let minWidths = subviews.map { $0.sizeThatFits(ProposedViewSize(width: 0, height: fitHeightProposal.height)).width }
        let idealWidths = subviews.map { $0.sizeThatFits(fitHeightProposal).width }
        let maxWidths = subviews.map { $0.sizeThatFits(ProposedViewSize(width: .infinity, height: fitHeightProposal.height)).width }
        
        if proposal.width == nil {
            return idealWidths
        }
        
        let totalSpacing = cache.subviewSpacings.reduce(0, +)
        let totalMinWidth = minWidths.reduce(0, +) + totalSpacing
        let availableWidth = proposal.width!
        
        var currentWidths = minWidths
        var remainingSpace = availableWidth - totalMinWidth
        
        if remainingSpace <= 0 {
            // Insufficient space: all views get minimum width (may clip)
            return minWidths
        }
        
        let priorities = cache.priorities
        let uniquePriorities = Set(priorities).sorted(by: >)
        
        // Phase 1: Grow from min to ideal (high priority first)
        for priority in uniquePriorities {
            var flexibleIndices = subviews.indices.filter {
                priorities[$0] == priority && currentWidths[$0] < idealWidths[$0]
            }
            
            while remainingSpace > 1e-5 && !flexibleIndices.isEmpty {
                let count = CGFloat(flexibleIndices.count)
                let share = remainingSpace / count
                var distributed: CGFloat = 0
                
                for index in flexibleIndices {
                    let limit = idealWidths[index] - currentWidths[index]
                    let give = min(share, limit)
                    currentWidths[index] += give
                    distributed += give
                }
                
                remainingSpace -= distributed
                if distributed < 1e-5 { break }
                
                flexibleIndices = flexibleIndices.filter { currentWidths[$0] < idealWidths[$0] }
            }
        }
        
        // Phase 2: Grow from ideal to max (high priority first)
        for priority in uniquePriorities {
            var flexibleIndices = subviews.indices.filter {
                priorities[$0] == priority && currentWidths[$0] < maxWidths[$0]
            }
            
            while remainingSpace > 1e-5 && !flexibleIndices.isEmpty {
                let count = CGFloat(flexibleIndices.count)
                let share = remainingSpace / count
                var distributed: CGFloat = 0
                
                for index in flexibleIndices {
                    let limit = maxWidths[index] - currentWidths[index]
                    let give = min(share, limit)
                    currentWidths[index] += give
                    distributed += give
                }
                
                remainingSpace -= distributed
                if distributed < 1e-5 { break }
                
                flexibleIndices = flexibleIndices.filter { currentWidths[$0] < maxWidths[$0] }
            }
        }
        
        return currentWidths
    }

    public func sizeThatFits(proposal: ProposedViewSize,
                             subviews: Subviews,
                             cache: inout Self.Cache) -> CGSize {
        let widths = layoutWidths(proposal: proposal, subviews: subviews, cache: &cache)
        let totalSpacing = cache.subviewSpacings.reduce(0, +)
        let totalWidth = widths.reduce(0, +) + totalSpacing
        
        let fitHeightProposal = ProposedViewSize(height: proposal.height)
        let heights = subviews.indices.map { index in
            subviews[index].sizeThatFits(ProposedViewSize(width: widths[index], height: fitHeightProposal.height)).height
        }
        let maxHeight = heights.reduce(0, max)
        
        return CGSize(width: totalWidth, height: maxHeight)
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
        let start = bounds.origin
        
        // Use bounds width for layout calculation
        let actualProposal = ProposedViewSize(width: bounds.width, height: bounds.height)
        let widths = layoutWidths(proposal: actualProposal, subviews: subviews, cache: &cache)
        
        // Pre-calculate max ascent and descent for alignment
        var maxAscent: CGFloat = 0
        var maxDescent: CGFloat = 0
        
        // We need to store alignment values to avoid re-calculating dimensions if expensive, 
        // but for now, we'll re-calculate to keep code simple as ViewDimensions is a value type.
        // Actually, let's store ascents to avoid re-calculation.
        var ascents: [CGFloat] = []
        ascents.reserveCapacity(subviews.count)
        
        for index in subviews.indices {
            let childWidth = widths[index]
            let childProposal = ProposedViewSize(width: childWidth, height: actualProposal.height)
            let dimensions = subviews[index].dimensions(in: childProposal)
            
            let ascent = dimensions[self.alignment]
            let descent = dimensions.height - ascent
            
            maxAscent = max(maxAscent, ascent)
            maxDescent = max(maxDescent, descent)
            
            ascents.append(ascent)
        }
        
        let contentHeight = maxAscent + maxDescent
        // Center the content vertically within bounds
        let contentTop = bounds.minY + (bounds.height - contentHeight) * 0.5
        let guideY = contentTop + maxAscent
        
        var offset = start
        
        for index in subviews.indices {
            offset.x += cache.subviewSpacings[index]
            
            let childWidth = widths[index]
            let childProposal = ProposedViewSize(width: childWidth, height: actualProposal.height)
            
            let ascent = ascents[index]
            let y = guideY - ascent
            
            subviews[index].place(at: CGPoint(x: offset.x, y: y),
                                  anchor: .topLeading,
                                  proposal: childProposal)
            
            offset.x += childWidth
        }
    }

    public static var layoutProperties: LayoutProperties {
        LayoutProperties(stackOrientation: .horizontal)
    }
}

public typealias _HStackLayout = HStackLayout
extension _HStackLayout: _VariadicView_UnaryViewRoot {}
extension _HStackLayout: _VariadicView_ViewRoot {}
extension _HStackLayout: Sendable {}


