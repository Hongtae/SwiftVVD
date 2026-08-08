//
//  File: StackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private struct StackLayout {
    struct MajorAxisRangeCache {
        var min: CGFloat?
        var max: CGFloat?
    }

    struct Child {
        var layoutPriority: Double
        var majorAxisRangeCache: MajorAxisRangeCache
        var distanceToPrevious: CGFloat
        var fittingOrder: Int
        var geometry: ViewGeometry
    }

    struct Header {
        var minorAxisAlignment: AlignmentKey
        var uniformSpacing: CGFloat?
        var majorAxis: Axis
        var internalSpacing: CGFloat
        var lastProposedSize: ProposedViewSize
        var stackSize: CGSize
        var proxies: LayoutSubviews
        var resizeChildrenWithTrailingOverflow: Bool
    }

    var header: Header
    var children: [Child]
}

public struct _StackLayoutCache {
    fileprivate var stack: StackLayout
}

enum _StackLayoutImplementation {
    private struct ChildIndexProjection: MutableCollection, RandomAccessCollection {
        typealias Index = Int
        typealias Element = Int

        var base: UnsafeMutableBufferPointer<StackLayout.Child>

        var startIndex: Int { 0 }
        var endIndex: Int { base.count }

        subscript(position: Int) -> Int {
            get { base[position].fittingOrder }
            set { base[position].fittingOrder = newValue }
        }
    }

    static func makeCache(
        axis: Axis,
        uniformSpacing: CGFloat?,
        minorAxisAlignment: AlignmentKey,
        subviews: LayoutSubviews,
        resizeChildrenWithTrailingOverflow: Bool
    ) -> _StackLayoutCache {
        var children: [StackLayout.Child] = []
        children.reserveCapacity(subviews.count)
        var internalSpacing: CGFloat = 0
        makeChildren(
            in: &children,
            internalSpacing: &internalSpacing,
            axis: axis,
            uniformSpacing: uniformSpacing,
            subviews: subviews
        )
        return _StackLayoutCache(
            stack: StackLayout(
                header: StackLayout.Header(
                    minorAxisAlignment: minorAxisAlignment,
                    uniformSpacing: uniformSpacing,
                    majorAxis: axis,
                    internalSpacing: internalSpacing,
                    lastProposedSize: ProposedViewSize(
                        width: -.infinity,
                        height: -.infinity
                    ),
                    stackSize: .zero,
                    proxies: subviews,
                    resizeChildrenWithTrailingOverflow: resizeChildrenWithTrailingOverflow
                ),
                children: children
            )
        )
    }

    static func updateCache(
        _ cache: inout _StackLayoutCache,
        axis: Axis,
        uniformSpacing: CGFloat?,
        minorAxisAlignment: AlignmentKey,
        subviews: LayoutSubviews,
        resizeChildrenWithTrailingOverflow: Bool
    ) {
        cache.stack.header = StackLayout.Header(
            minorAxisAlignment: minorAxisAlignment,
            uniformSpacing: uniformSpacing,
            majorAxis: axis,
            internalSpacing: 0,
            lastProposedSize: ProposedViewSize(
                width: -.infinity,
                height: -.infinity
            ),
            stackSize: .zero,
            proxies: subviews,
            resizeChildrenWithTrailingOverflow: resizeChildrenWithTrailingOverflow
        )
        cache.stack.children.removeAll(keepingCapacity: true)
        makeChildren(
            in: &cache.stack.children,
            internalSpacing: &cache.stack.header.internalSpacing,
            axis: axis,
            uniformSpacing: uniformSpacing,
            subviews: subviews
        )
    }

    private static func makeChildren(
        in children: inout [StackLayout.Child],
        internalSpacing: inout CGFloat,
        axis: Axis,
        uniformSpacing: CGFloat?,
        subviews: LayoutSubviews
    ) {
        children.reserveCapacity(subviews.count)
        for index in subviews.indices {
            let childSpacing: CGFloat
            if index == subviews.startIndex {
                childSpacing = 0
            } else if let uniformSpacing {
                childSpacing = uniformSpacing
            } else {
                childSpacing = subviews[index - 1].spacing.distance(
                    to: subviews[index].spacing,
                    along: axis
                )
            }

            internalSpacing += childSpacing
            children.append(
                StackLayout.Child(
                    layoutPriority: subviews[index].priority,
                    majorAxisRangeCache: StackLayout.MajorAxisRangeCache(),
                    distanceToPrevious: childSpacing,
                    fittingOrder: index,
                    geometry: .invalidValue
                )
            )
        }
    }

    static func sizeThatFits(
        proposal: ProposedViewSize,
        cache: inout _StackLayoutCache
    ) -> CGSize {
        guard !cache.stack.children.isEmpty else {
            return .zero
        }
        resolveChildren(proposal: proposal, cache: &cache)
        return cache.stack.header.stackSize
    }

    static func spacing(cache: _StackLayoutCache) -> ViewSpacing {
        let axis = cache.stack.header.majorAxis
        let subviews = cache.stack.header.proxies
        var spacing = ViewSpacing(
            Spacing(),
            layoutDirection: subviews.layoutDirection
        )
        for index in subviews.indices {
            var edges: Edge.Set
            switch axis {
            case .horizontal:
                edges = [.top, .bottom]
                if index == 0 { edges.formUnion(.leading) }
                if index == subviews.endIndex - 1 { edges.formUnion(.trailing) }
            case .vertical:
                edges = [.leading, .trailing]
                if index == 0 { edges.formUnion(.top) }
                if index == subviews.endIndex - 1 { edges.formUnion(.bottom) }
            }
            spacing.formUnion(subviews[index].spacing, edges: edges)
        }
        return spacing
    }

    static func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        cache: inout _StackLayoutCache
    ) {
        guard !cache.stack.children.isEmpty else {
            return
        }

        let axis = cache.stack.header.majorAxis
        let subviews = cache.stack.header.proxies
        let placementProposal = proposalWhenPlacing(
            axis: axis,
            proposal: proposal,
            bounds: bounds
        )
        resolveChildren(proposal: placementProposal, cache: &cache)

        for index in subviews.indices {
            var geometry = cache.stack.children[index].geometry
            guard !geometry.isInvalid else {
                continue
            }
            geometry.origin.x += bounds.minX
            geometry.origin.y += bounds.minY
            subviews[index].place(in: geometry, layoutDirection: .leftToRight)
        }
    }

    static func explicitAlignment(
        guide: AlignmentKey,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        cache: inout _StackLayoutCache
    ) -> CGFloat? {
        guard !cache.stack.children.isEmpty else {
            return nil
        }

        // Tested non-baseline built-in stack guides do not propagate as explicit
        // values even when direct children write them. Custom guides and text
        // baselines do propagate.
        guard !guide.suppressesStackExplicitPropagation else {
            return nil
        }

        let axis = cache.stack.header.majorAxis
        let subviews = cache.stack.header.proxies
        let placementProposal = proposalWhenPlacing(
            axis: axis,
            proposal: proposal,
            bounds: bounds
        )
        resolveChildren(proposal: placementProposal, cache: &cache)
        var explicitValues: [CGFloat?] = []
        explicitValues.reserveCapacity(subviews.count)

        for index in subviews.indices {
            let geometry = cache.stack.children[index].geometry
            guard !geometry.isInvalid else {
                explicitValues.append(nil)
                continue
            }
            let dimensions = geometry.dimensions
            let childOffset = guide.axis == .horizontal
                ? geometry.origin.x
                : geometry.origin.y
            explicitValues.append(dimensions[explicit: guide].map { childOffset + $0 })
        }

        guard let combined = guide.combineExplicit(explicitValues) else {
            return nil
        }
        let boundsOffset = guide.axis == .horizontal
            ? bounds.minX
            : bounds.minY
        return boundsOffset + combined
    }

    private static func resolveChildren(
        proposal: ProposedViewSize,
        cache: inout _StackLayoutCache
    ) {
        let axis = cache.stack.header.majorAxis
        let subviews = cache.stack.header.proxies
        precondition(cache.stack.children.count == subviews.count)

        if cache.stack.header.lastProposedSize == proposal {
            return
        }

        let previousProposal = cache.stack.header.lastProposedSize
        let crossProposal = cross(proposal, axis: axis)
        placeChildren(
            proposal: proposal,
            crossProposalForChild: { _ in crossProposal },
            previousProposal: previousProposal,
            subviews: subviews,
            cache: &cache
        )

        if cache.stack.header.resizeChildrenWithTrailingOverflow {
            resizeAnyChildrenWithTrailingOverflow(
                proposal: proposal,
                previousProposal: previousProposal,
                subviews: subviews,
                cache: &cache
            )
        }
        cache.stack.header.lastProposedSize = proposal
    }

    private static func placeChildren(
        proposal: ProposedViewSize,
        crossProposalForChild: (StackLayout.Child) -> CGFloat?,
        previousProposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout _StackLayoutCache
    ) {
        let axis = cache.stack.header.majorAxis
        if let proposedMajor = major(proposal, axis: axis) {
            sizeChildrenGenerally(
                axis: axis,
                proposedMajor: proposedMajor,
                crossProposal: cross(proposal, axis: axis),
                crossProposalForChild: crossProposalForChild,
                previousProposal: previousProposal,
                subviews: subviews,
                cache: &cache
            )
        } else {
            sizeChildrenIdeally(
                axis: axis,
                crossProposalForChild: crossProposalForChild,
                subviews: subviews,
                cache: &cache
            )
        }

        positionChildren(
            axis: axis,
            cache: &cache
        )
    }

    private static func sizeChildrenIdeally(
        axis: Axis,
        crossProposalForChild: (StackLayout.Child) -> CGFloat?,
        subviews: LayoutSubviews,
        cache: inout _StackLayoutCache
    ) {
        for index in subviews.indices {
            let crossProposal = crossProposalForChild(
                cache.stack.children[index]
            )
            resize(
                childAt: index,
                proposal: proposalFor(
                    axis: axis,
                    major: nil,
                    cross: crossProposal
                ),
                subviews: subviews,
                cache: &cache
            )
        }
    }

    private static func sizeChildrenGenerally(
        axis: Axis,
        proposedMajor: CGFloat,
        crossProposal: CGFloat?,
        crossProposalForChild: (StackLayout.Child) -> CGFloat?,
        previousProposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout _StackLayoutCache
    ) {
        prioritize(
            axis: axis,
            crossProposal: crossProposal,
            previousProposal: previousProposal,
            subviews: subviews,
            cache: &cache
        )

        var available = proposedMajor - cache.stack.header.internalSpacing
        var groupStart = cache.stack.children.startIndex
        var isFirstGroup = true
        while groupStart < cache.stack.children.endIndex {
            let firstIndex = cache.stack.children[groupStart].fittingOrder
            let groupPriority = cache.stack.children[firstIndex].layoutPriority
            var groupEnd = cache.stack.children.index(after: groupStart)
            while groupEnd < cache.stack.children.endIndex {
                let childIndex = cache.stack.children[groupEnd].fittingOrder
                guard cache.stack.children[childIndex].layoutPriority == groupPriority else {
                    break
                }
                groupEnd = cache.stack.children.index(after: groupEnd)
            }

            if isFirstGroup {
                var lowerMinimum: CGFloat = 0
                var lowerIndex = groupEnd
                while lowerIndex < cache.stack.children.endIndex {
                    let childIndex =
                        cache.stack.children[lowerIndex].fittingOrder
                    lowerMinimum += majorAxisRange(
                        childAt: childIndex,
                        axis: axis,
                        crossProposal: crossProposal,
                        subviews: subviews,
                        cache: &cache
                    ).min
                    lowerIndex =
                        cache.stack.children.index(after: lowerIndex)
                }
                available -= lowerMinimum
                isFirstGroup = false
            } else {
                var groupMinimum: CGFloat = 0
                var groupIndex = groupStart
                while groupIndex < groupEnd {
                    let childIndex =
                        cache.stack.children[groupIndex].fittingOrder
                    groupMinimum += majorAxisRange(
                        childAt: childIndex,
                        axis: axis,
                        crossProposal: crossProposal,
                        subviews: subviews,
                        cache: &cache
                    ).min
                    groupIndex =
                        cache.stack.children.index(after: groupIndex)
                }
                available += groupMinimum
            }

            var unsizedCount = groupEnd - groupStart
            var sortedIndex = groupStart
            while sortedIndex < groupEnd {
                let childIndex = cache.stack.children[sortedIndex].fittingOrder
                let dividedLength = available / CGFloat(unsizedCount)
                let proposedLength = dividedLength <= 0 ? 0 : dividedLength
                let childCrossProposal = crossProposalForChild(
                    cache.stack.children[childIndex]
                )
                resize(
                    childAt: childIndex,
                    proposal: proposalFor(
                        axis: axis,
                        major: proposedLength,
                        cross: childCrossProposal
                    ),
                    subviews: subviews,
                    cache: &cache
                )
                let actualLength = major(
                    cache.stack.children[childIndex].geometry.dimensions,
                    axis: axis
                )
                available = subtractingWithoutNaN(
                    actualLength,
                    from: available
                )
                unsizedCount -= 1
                sortedIndex = cache.stack.children.index(after: sortedIndex)
            }

            groupStart = groupEnd
        }
    }

    private static func resizeAnyChildrenWithTrailingOverflow(
        proposal: ProposedViewSize,
        previousProposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout _StackLayoutCache
    ) {
        let axis = cache.stack.header.majorAxis
        let proposedCross = cross(proposal, axis: axis) ?? .infinity
        let stackCross = cross(
            cache.stack.header.stackSize,
            axis: axis
        )

        guard stackCross > proposedCross else {
            return
        }

        // When one child already spans the whole cross-axis result, the excess
        // is intrinsic to that child rather than a sibling-alignment offset.
        for child in cache.stack.children {
            if cross(child.geometry.dimensions, axis: axis) == stackCross {
                return
            }
        }

        // Preserve the normal major-axis priority budget. Only the cross-axis
        // proposal is reduced, and only by the amount that this child's
        // previously placed trailing edge exceeded the finite stack proposal.
        placeChildren(
            proposal: proposal,
            crossProposalForChild: { child in
                crossProposalRemovingTrailingOverflow(
                    from: child,
                    proposedCross: proposedCross,
                    axis: axis
                )
            },
            previousProposal: previousProposal,
            subviews: subviews,
            cache: &cache
        )
    }

    private static func crossProposalRemovingTrailingOverflow(
        from child: StackLayout.Child,
        proposedCross: CGFloat,
        axis: Axis
    ) -> CGFloat {
        let fallbackOverflow = nonNegative(-proposedCross)
        var trailingOverflow = fallbackOverflow

        if !child.geometry.isInvalid {
            let start = cross(child.geometry.origin, axis: axis)
            let end = start + cross(
                child.geometry.dimensions,
                axis: axis
            )

            // Select the ordered endpoints explicitly so unordered values keep
            // the same fallback behavior as the geometry validity path.
            let lower = end < start ? end : start
            let upper = start <= end ? end : start
            if lower <= upper {
                trailingOverflow = nonNegative(upper - proposedCross)
            }
        }
        return proposedCross - trailingOverflow
    }

    private static func nonNegative(_ value: CGFloat) -> CGFloat {
        value <= 0 ? 0 : value
    }

    private static func subtractingWithoutNaN(
        _ value: CGFloat,
        from available: CGFloat
    ) -> CGFloat {
        let result = available - value
        return result.isNaN ? available : result
    }

    private static func prioritize(
        axis: Axis,
        crossProposal: CGFloat?,
        previousProposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout _StackLayoutCache
    ) {
        if major(previousProposal, axis: axis) != nil,
           cross(previousProposal, axis: axis) == crossProposal {
            return
        }

        for index in cache.stack.children.indices {
            cache.stack.children[index].majorAxisRangeCache =
                StackLayout.MajorAxisRangeCache()
        }

        cache.stack.children.withUnsafeMutableBufferPointer { children in
            guard let baseAddress = children.baseAddress else {
                return
            }
            var projection = ChildIndexProjection(base: children)
            projection.sort { lhsIndex, rhsIndex in
                let lhsPriority = baseAddress[lhsIndex].layoutPriority
                let rhsPriority = baseAddress[rhsIndex].layoutPriority
                if lhsPriority != rhsPriority {
                    return lhsPriority > rhsPriority
                }

                let lhsRange = majorAxisRange(
                    childAt: lhsIndex,
                    baseAddress: baseAddress,
                    axis: axis,
                    crossProposal: crossProposal,
                    subviews: subviews
                )
                let rhsRange = majorAxisRange(
                    childAt: rhsIndex,
                    baseAddress: baseAddress,
                    axis: axis,
                    crossProposal: crossProposal,
                    subviews: subviews
                )
                let lhsFlexibility = lhsRange.max - lhsRange.min
                let rhsFlexibility = rhsRange.max - rhsRange.min
                if lhsFlexibility.isFinite != rhsFlexibility.isFinite {
                    return lhsFlexibility.isFinite
                }
                if lhsFlexibility.isFinite &&
                    lhsFlexibility != rhsFlexibility {
                    return lhsFlexibility < rhsFlexibility
                }
                if !lhsFlexibility.isFinite &&
                    !rhsFlexibility.isFinite &&
                    lhsRange.min != rhsRange.min {
                    return lhsRange.min > rhsRange.min
                }
                return lhsIndex < rhsIndex
            }
        }
    }

    private static func majorAxisRange(
        childAt index: Int,
        axis: Axis,
        crossProposal: CGFloat?,
        subviews: LayoutSubviews,
        cache: inout _StackLayoutCache
    ) -> (min: CGFloat, max: CGFloat) {
        if cache.stack.children[index].majorAxisRangeCache.min == nil {
            cache.stack.children[index].majorAxisRangeCache.min = lengthThatFits(
                childAt: index,
                axis: axis,
                major: 0,
                cross: crossProposal,
                subviews: subviews
            )
        }
        if cache.stack.children[index].majorAxisRangeCache.max == nil {
            cache.stack.children[index].majorAxisRangeCache.max = lengthThatFits(
                childAt: index,
                axis: axis,
                major: .infinity,
                cross: crossProposal,
                subviews: subviews
            )
        }
        return (
            cache.stack.children[index].majorAxisRangeCache.min!,
            cache.stack.children[index].majorAxisRangeCache.max!
        )
    }

    private static func majorAxisRange(
        childAt index: Int,
        baseAddress: UnsafeMutablePointer<StackLayout.Child>,
        axis: Axis,
        crossProposal: CGFloat?,
        subviews: LayoutSubviews
    ) -> (min: CGFloat, max: CGFloat) {
        if baseAddress[index].majorAxisRangeCache.min == nil {
            baseAddress[index].majorAxisRangeCache.min = lengthThatFits(
                childAt: index,
                axis: axis,
                major: 0,
                cross: crossProposal,
                subviews: subviews
            )
        }
        if baseAddress[index].majorAxisRangeCache.max == nil {
            baseAddress[index].majorAxisRangeCache.max = lengthThatFits(
                childAt: index,
                axis: axis,
                major: .infinity,
                cross: crossProposal,
                subviews: subviews
            )
        }
        return (
            baseAddress[index].majorAxisRangeCache.min!,
            baseAddress[index].majorAxisRangeCache.max!
        )
    }

    private static func lengthThatFits(
        childAt index: Int,
        axis: Axis,
        major: CGFloat,
        cross: CGFloat?,
        subviews: LayoutSubviews
    ) -> CGFloat {
        subviews[index].proxy.layoutComputer.lengthThatFits(
            _ProposedSize(
                proposalFor(
                    axis: axis,
                    major: major,
                    cross: cross
                )
            ),
            in: axis
        )
    }

    private static func resize(
        childAt index: Int,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout _StackLayoutCache
    ) {
        let dimensions = subviews[index].dimensions(in: proposal)
        cache.stack.children[index].geometry = ViewGeometry(
            origin: .zero,
            dimensions: dimensions
        )
    }

    private static func positionChildren(
        axis: Axis,
        cache: inout _StackLayoutCache
    ) {
        let crossRange = alignmentRange(axis: axis, cache: cache)
        var majorOffset: CGFloat = 0
        for index in cache.stack.children.indices {
            var geometry = cache.stack.children[index].geometry
            guard !geometry.isInvalid else {
                continue
            }
            let dimensions = geometry.dimensions
            majorOffset += cache.stack.children[index].distanceToPrevious
            let minorOffset = -crossRange.min - alignmentGuide(
                dimensions: dimensions,
                cache: cache
            )
            geometry.origin = origin(
                axis: axis,
                major: majorOffset,
                cross: minorOffset
            )
            cache.stack.children[index].geometry = geometry
            majorOffset += major(dimensions, axis: axis)
        }
        cache.stack.header.stackSize = size(
            axis: axis,
            major: majorOffset,
            cross: crossRange.max - crossRange.min
        )
    }

    private static func alignmentRange(
        axis: Axis,
        cache: _StackLayoutCache
    ) -> (min: CGFloat, max: CGFloat) {
        guard !cache.stack.children.isEmpty else {
            return (0, 0)
        }

        var minValue: CGFloat = 0
        var maxValue: CGFloat = 0
        for child in cache.stack.children {
            guard !child.geometry.isInvalid else {
                continue
            }
            let dimensions = child.geometry.dimensions
            let guide = alignmentGuide(dimensions: dimensions, cache: cache)
            let crossLength = cross(dimensions, axis: axis)
            let start = -guide
            let end = start + crossLength
            minValue = Swift.min(minValue, start, end)
            maxValue = Swift.max(maxValue, start, end)
        }
        return (minValue, maxValue)
    }

    private static func alignmentGuide(
        dimensions: ViewDimensions,
        cache: _StackLayoutCache
    ) -> CGFloat {
        dimensions[cache.stack.header.minorAxisAlignment]
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

    private static func major(_ dimensions: ViewDimensions, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: return dimensions.width
        case .vertical: return dimensions.height
        }
    }

    private static func cross(_ dimensions: ViewDimensions, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: return dimensions.height
        case .vertical: return dimensions.width
        }
    }

    private static func cross(_ size: CGSize, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: return size.height
        case .vertical: return size.width
        }
    }

    private static func cross(_ point: CGPoint, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: return point.y
        case .vertical: return point.x
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
        var properties = LayoutProperties()
        properties.stackOrientation = Self.majorAxis
        return properties
    }

    public static func _makeView(root: _GraphValue<Self>,
                                 inputs: _ViewInputs,
                                 body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        Self._makeLayoutView(root: root, inputs: inputs, body: body)
    }
}
