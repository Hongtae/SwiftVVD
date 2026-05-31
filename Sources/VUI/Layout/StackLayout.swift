//
//  File: StackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _StackLayoutCache {
    var spacings: [ViewSpacing] = []
    var subviewSpacings: [CGFloat] = []
    var priorities: [Double] = []
    
    // Store alignment for explicitAlignment calculation
    var horizontalAlignment: HorizontalAlignment?
    var verticalAlignment: VerticalAlignment?
}

enum _StackLayoutImplementation {
    private struct ChildRange {
        var index: Int
        var priority: Double
        var minMajor: CGFloat
        var maxMajor: CGFloat

        var flexibility: CGFloat {
            maxMajor - minMajor
        }
    }

    static func updateCache(_ cache: inout _StackLayoutCache,
                            axis: Axis,
                            explicitSpacing: CGFloat?,
                            horizontalAlignment: HorizontalAlignment?,
                            verticalAlignment: VerticalAlignment?,
                            subviews: LayoutSubviews) {
        cache.priorities = subviews.map { $0.priority }
        cache.spacings = subviews.map { $0.spacing }
        cache.horizontalAlignment = horizontalAlignment
        cache.verticalAlignment = verticalAlignment

        cache.subviewSpacings = cache.spacings.indices.map { index in
            guard index > 0 else { return 0 }
            if let explicitSpacing {
                return explicitSpacing
            }
            return cache.spacings[index - 1].distance(to: cache.spacings[index], along: axis)
        }
    }

    static func sizeThatFits(axis: Axis,
                             proposal: ProposedViewSize,
                             subviews: LayoutSubviews,
                             cache: inout _StackLayoutCache) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let crossProposal = cross(proposal, axis: axis)
        let majorLengths = self.majorLengths(axis: axis,
                                             proposal: proposal,
                                             subviews: subviews,
                                             cache: &cache)
        var dimensions: [ViewDimensions] = []
        dimensions.reserveCapacity(subviews.count)

        for index in subviews.indices {
            let childProposal = proposalFor(axis: axis,
                                            major: majorLengths[index],
                                            cross: crossProposal)
            dimensions.append(subviews[index].dimensions(in: childProposal))
        }

        let totalMajor = majorLengths.reduce(0, +) + totalSpacing(for: subviews.count, cache: cache)
        let totalCross = crossExtent(axis: axis, dimensions: dimensions, cache: cache)
        return size(axis: axis, major: totalMajor, cross: totalCross)
    }

    static func spacing(axis: Axis, cache: _StackLayoutCache) -> ViewSpacing {
        var spacing = ViewSpacing()
        for index in cache.spacings.indices {
            var edges: Edge.Set
            switch axis {
            case .horizontal:
                edges = [.top, .bottom]
                if index == 0 { edges.formUnion(.leading) }
                if index == cache.spacings.count - 1 { edges.formUnion(.trailing) }
            case .vertical:
                edges = [.leading, .trailing]
                if index == 0 { edges.formUnion(.top) }
                if index == cache.spacings.count - 1 { edges.formUnion(.bottom) }
            }
            spacing.formUnion(cache.spacings[index], edges: edges)
        }
        return spacing
    }

    static func placeSubviews(axis: Axis,
                              in bounds: CGRect,
                              proposal: ProposedViewSize,
                              subviews: LayoutSubviews,
                              cache: inout _StackLayoutCache) {
        guard !subviews.isEmpty else { return }

        let placementProposal = proposalWhenPlacing(axis: axis,
                                                    proposal: proposal,
                                                    bounds: bounds)
        let crossProposal = cross(placementProposal, axis: axis)
        let majorLengths = self.majorLengths(axis: axis,
                                             proposal: placementProposal,
                                             subviews: subviews,
                                             cache: &cache)
        var dimensions: [ViewDimensions] = []
        dimensions.reserveCapacity(subviews.count)

        for index in subviews.indices {
            let childProposal = proposalFor(axis: axis,
                                            major: majorLengths[index],
                                            cross: crossProposal)
            dimensions.append(subviews[index].dimensions(in: childProposal))
        }

        let crossRange = alignmentRange(axis: axis, dimensions: dimensions, cache: cache)
        // Normalize extra cross-axis alignment bounds inside the stack-local frame.
        // Larger outer frames move the whole stack instead of recentering children.
        let guidePosition = minCross(bounds, axis: axis) - crossRange.min

        var majorOffset = minMajor(bounds, axis: axis)
        for index in subviews.indices {
            majorOffset += spacingBeforeSubview(at: index, cache: cache)

            let childProposal = proposalFor(axis: axis,
                                            major: majorLengths[index],
                                            cross: crossProposal)
            let childCrossOrigin = guidePosition - alignmentGuide(axis: axis,
                                                                  dimensions: dimensions[index],
                                                                  cache: cache)
            let point = origin(axis: axis, major: majorOffset, cross: childCrossOrigin)
            subviews[index].place(at: point, anchor: .topLeading, proposal: childProposal)

            majorOffset += majorLengths[index]
        }
    }

    static func explicitAlignment(axis: Axis,
                                  guide: AlignmentKey,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: LayoutSubviews,
                                  cache: inout _StackLayoutCache) -> CGFloat? {
        guard !subviews.isEmpty else { return nil }

        // Tested non-baseline built-in stack guides do not propagate as explicit
        // values even when direct children write them. Custom guides and text
        // baselines do propagate.
        guard !guide.suppressesStackExplicitPropagation else {
            return nil
        }

        let placementProposal = proposalWhenPlacing(axis: axis,
                                                    proposal: proposal,
                                                    bounds: bounds)
        let crossProposal = cross(placementProposal, axis: axis)
        let majorLengths = self.majorLengths(axis: axis,
                                             proposal: placementProposal,
                                             subviews: subviews,
                                             cache: &cache)
        var dimensions: [ViewDimensions] = []
        dimensions.reserveCapacity(subviews.count)

        for index in subviews.indices {
            let childProposal = proposalFor(axis: axis,
                                            major: majorLengths[index],
                                            cross: crossProposal)
            dimensions.append(subviews[index].dimensions(in: childProposal))
        }

        let crossRange = alignmentRange(axis: axis, dimensions: dimensions, cache: cache)
        let guidePosition = minCross(bounds, axis: axis) - crossRange.min

        var majorOffset = minMajor(bounds, axis: axis)
        var explicitValues: [CGFloat?] = []
        explicitValues.reserveCapacity(subviews.count)

        for index in subviews.indices {
            majorOffset += spacingBeforeSubview(at: index, cache: cache)

            let childCrossOrigin = guidePosition - alignmentGuide(axis: axis,
                                                                  dimensions: dimensions[index],
                                                                  cache: cache)
            let childOrigin = origin(axis: axis, major: majorOffset, cross: childCrossOrigin)
            let childOffset = guide.axis == .horizontal ? childOrigin.x : childOrigin.y
            explicitValues.append(dimensions[index][explicit: guide].map { childOffset + $0 })

            majorOffset += majorLengths[index]
        }

        return guide.combineExplicit(explicitValues)
    }

    private static func majorLengths(axis: Axis,
                                     proposal: ProposedViewSize,
                                     subviews: LayoutSubviews,
                                     cache: inout _StackLayoutCache) -> [CGFloat] {
        let crossProposal = cross(proposal, axis: axis)
        guard let proposedMajor = major(proposal, axis: axis) else {
            return subviews.indices.map { index in
                major(subviews[index].sizeThatFits(proposalFor(axis: axis,
                                                               major: nil,
                                                               cross: crossProposal)),
                      axis: axis)
            }
        }

        let ranges = subviews.indices.map { index in
            let minSize = subviews[index].sizeThatFits(proposalFor(axis: axis,
                                                                   major: 0,
                                                                   cross: crossProposal))
            let maxSize = subviews[index].sizeThatFits(proposalFor(axis: axis,
                                                                   major: .infinity,
                                                                   cross: crossProposal))
            return ChildRange(index: index,
                              priority: priority(at: index, cache: cache),
                              minMajor: major(minSize, axis: axis),
                              maxMajor: major(maxSize, axis: axis))
        }
        let sortedRanges = ranges.sorted(by: childSortPrecedes(_:_:))
        var resolved = Array(repeating: CGFloat.zero, count: subviews.count)
        var remaining = proposedMajor - totalSpacing(for: subviews.count, cache: cache)

        var groupStart = sortedRanges.startIndex
        while groupStart < sortedRanges.endIndex {
            var groupEnd = sortedRanges.index(after: groupStart)
            while groupEnd < sortedRanges.endIndex &&
                    sortedRanges[groupEnd].priority == sortedRanges[groupStart].priority {
                groupEnd = sortedRanges.index(after: groupEnd)
            }

            let lowerMinimum = sortedRanges[groupEnd...].reduce(CGFloat.zero) { partial, range in
                partial + range.minMajor
            }
            var groupRemaining = remaining - lowerMinimum
            var unsizedCount = groupEnd - groupStart
            var index = groupStart

            while index < groupEnd {
                let range = sortedRanges[index]
                let proposed = groupRemaining / CGFloat(unsizedCount)
                let actualSize = subviews[range.index].sizeThatFits(proposalFor(axis: axis,
                                                                                major: proposed,
                                                                                cross: crossProposal))
                let actualMajor = major(actualSize, axis: axis)
                resolved[range.index] = actualMajor
                remaining -= actualMajor
                groupRemaining -= actualMajor
                unsizedCount -= 1
                index = sortedRanges.index(after: index)
            }

            groupStart = groupEnd
        }

        return resolved
    }

    private static func childSortPrecedes(_ lhs: ChildRange, _ rhs: ChildRange) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }

        let lhsFlex = lhs.flexibility
        let rhsFlex = rhs.flexibility
        if lhsFlex.isFinite != rhsFlex.isFinite {
            return lhsFlex.isFinite
        }
        if lhsFlex.isFinite && lhsFlex != rhsFlex {
            return lhsFlex < rhsFlex
        }
        if !lhsFlex.isFinite && !rhsFlex.isFinite && lhs.minMajor != rhs.minMajor {
            return lhs.minMajor > rhs.minMajor
        }
        return lhs.index < rhs.index
    }

    private static func alignmentRange(axis: Axis,
                                       dimensions: [ViewDimensions],
                                       cache: _StackLayoutCache) -> (min: CGFloat, max: CGFloat) {
        guard !dimensions.isEmpty else { return (0, 0) }

        var minValue = CGFloat.infinity
        var maxValue = -CGFloat.infinity
        for dimensions in dimensions {
            let guide = alignmentGuide(axis: axis, dimensions: dimensions, cache: cache)
            let crossLength = cross(dimensions, axis: axis)
            minValue = Swift.min(minValue, -guide)
            maxValue = Swift.max(maxValue, crossLength - guide)
        }
        return (minValue, maxValue)
    }

    private static func crossExtent(axis: Axis,
                                    dimensions: [ViewDimensions],
                                    cache: _StackLayoutCache) -> CGFloat {
        let range = alignmentRange(axis: axis, dimensions: dimensions, cache: cache)
        return range.max - range.min
    }

    private static func alignmentGuide(axis: Axis,
                                       dimensions: ViewDimensions,
                                       cache: _StackLayoutCache) -> CGFloat {
        switch axis {
        case .horizontal:
            return dimensions[cache.verticalAlignment ?? .center]
        case .vertical:
            return dimensions[cache.horizontalAlignment ?? .center]
        }
    }

    private static func priority(at index: Int, cache: _StackLayoutCache) -> Double {
        guard cache.priorities.indices.contains(index) else { return 0 }
        return cache.priorities[index]
    }

    private static func spacingBeforeSubview(at index: Int, cache: _StackLayoutCache) -> CGFloat {
        guard cache.subviewSpacings.indices.contains(index) else { return 0 }
        return cache.subviewSpacings[index]
    }

    private static func totalSpacing(for count: Int, cache: _StackLayoutCache) -> CGFloat {
        cache.subviewSpacings.prefix(count).reduce(0, +)
    }

    private static func proposalFor(axis: Axis,
                                    major: CGFloat?,
                                    cross: CGFloat?) -> ProposedViewSize {
        switch axis {
        case .horizontal:
            return ProposedViewSize(width: major, height: cross)
        case .vertical:
            return ProposedViewSize(width: cross, height: major)
        }
    }

    private static func proposalWhenPlacing(axis: Axis,
                                            proposal: ProposedViewSize,
                                            bounds: CGRect) -> ProposedViewSize {
        let placementMajor = major(proposal, axis: axis)
        let placementCross = cross(proposal, axis: axis) ?? crossSize(bounds, axis: axis)
        return proposalFor(axis: axis, major: placementMajor, cross: placementCross)
    }

    private static func major(_ proposal: ProposedViewSize, axis: Axis) -> CGFloat? {
        switch axis {
        case .horizontal: return proposal.width
        case .vertical: return proposal.height
        }
    }

    private static func cross(_ proposal: ProposedViewSize, axis: Axis) -> CGFloat? {
        switch axis {
        case .horizontal: return proposal.height
        case .vertical: return proposal.width
        }
    }

    private static func major(_ size: CGSize, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: return size.width
        case .vertical: return size.height
        }
    }

    private static func cross(_ dimensions: ViewDimensions, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: return dimensions.height
        case .vertical: return dimensions.width
        }
    }

    private static func size(axis: Axis, major: CGFloat, cross: CGFloat) -> CGSize {
        switch axis {
        case .horizontal:
            return CGSize(width: major, height: cross)
        case .vertical:
            return CGSize(width: cross, height: major)
        }
    }

    private static func minMajor(_ bounds: CGRect, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: return bounds.minX
        case .vertical: return bounds.minY
        }
    }

    private static func minCross(_ bounds: CGRect, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: return bounds.minY
        case .vertical: return bounds.minX
        }
    }

    private static func crossSize(_ bounds: CGRect, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: return bounds.height
        case .vertical: return bounds.width
        }
    }

    private static func origin(axis: Axis, major: CGFloat, cross: CGFloat) -> CGPoint {
        switch axis {
        case .horizontal:
            return CGPoint(x: major, y: cross)
        case .vertical:
            return CGPoint(x: cross, y: major)
        }
    }
}

/// Marks stack layouts that dispatch variadic view construction through layout view generation.
protocol HVStack: Layout, _VariadicView_UnaryViewRoot {
    associatedtype MinorAxisAlignment: AlignmentGuide

    var alignment: MinorAxisAlignment { get }
    var spacing: CGFloat? { get }

    static var majorAxis: Axis { get }
    static var resizeChildrenWithTrailingOverflow: Bool { get }
}

extension HVStack {
    static var resizeChildrenWithTrailingOverflow: Bool {
        false
    }

    public static var layoutProperties: LayoutProperties {
        LayoutProperties(stackOrientation: Self.majorAxis)
    }

    public static func _makeView(root: _GraphValue<Self>,
                                 inputs: _ViewInputs,
                                 body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        Self._makeLayoutView(root: root, inputs: inputs, body: body)
    }
}
