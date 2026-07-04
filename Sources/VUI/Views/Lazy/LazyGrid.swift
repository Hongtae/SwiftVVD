//
//  File: LazyGrid.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private let defaultLazyGridSpacing = ViewSpacing.defaultSpacing

public struct GridItem: Sendable, Equatable {
    public enum Size: Sendable, Equatable {
        case fixed(_: CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }

    public var size: GridItem.Size
    public var spacing: CGFloat?
    public var alignment: Alignment?

    public init(
        _ size: GridItem.Size = .flexible(),
        spacing: CGFloat? = nil,
        alignment: Alignment? = nil
    ) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

struct _LazyGridLayout: Layout {
    var axis: Axis
    var items: [GridItem]
    var horizontalAlignment: HorizontalAlignment
    var verticalAlignment: VerticalAlignment
    var spacing: CGFloat?

    typealias Body = Never
    typealias AnimatableData = EmptyAnimatableData
    typealias Cache = Void

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        metrics(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let metrics = metrics(proposal: proposal, subviews: subviews)
        guard !metrics.trackSizes.isEmpty else { return }

        for index in subviews.indices {
            let track = index % metrics.trackSizes.count
            let group = index / metrics.trackSizes.count
            guard group < metrics.groupSizes.count else { continue }

            let childProposal = childProposal(forTrack: metrics.trackSizes[track])
            let childSize = subviews[index].sizeThatFits(childProposal)
            let alignment = items[track].alignment ?? defaultCellAlignment
            let cell = cellRect(
                bounds: bounds,
                track: track,
                group: group,
                metrics: metrics
            )
            subviews[index].place(
                at: origin(for: childSize, in: cell, alignment: alignment),
                anchor: .topLeading,
                proposal: childProposal
            )
        }
    }

    static func _makeView(
        root: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: (_Graph, _ViewInputs) -> _ViewListOutputs
    ) -> _ViewOutputs {
        Self._makeLayoutView(root: root, inputs: inputs, body: body)
    }

    private struct Metrics {
        var trackSizes: [CGFloat]
        var trackOffsets: [CGFloat]
        var groupSizes: [CGFloat]
        var groupOffsets: [CGFloat]
        var size: CGSize
    }

    private var defaultCellAlignment: Alignment {
        Alignment(horizontal: horizontalAlignment, vertical: verticalAlignment)
    }

    private func metrics(proposal: ProposedViewSize, subviews: Subviews) -> Metrics {
        let trackSizes = resolvedTrackSizes(proposedCrossSize: proposedCrossSize(proposal))
        guard !trackSizes.isEmpty else {
            return Metrics(
                trackSizes: [],
                trackOffsets: [],
                groupSizes: [],
                groupOffsets: [],
                size: .zero
            )
        }

        let trackOffsets = offsets(sizes: trackSizes, spacings: trackSpacings())
        var groupSizes = Array(
            repeating: CGFloat.zero,
            count: max(1, (subviews.count + trackSizes.count - 1) / trackSizes.count)
        )

        for index in subviews.indices {
            let track = index % trackSizes.count
            let group = index / trackSizes.count
            let childSize = subviews[index].sizeThatFits(childProposal(forTrack: trackSizes[track]))
            groupSizes[group] = max(groupSizes[group], major(childSize))
        }

        let groupOffsets = offsets(sizes: groupSizes, spacings: majorSpacings(count: groupSizes.count))
        let naturalCross = sum(trackSizes) + sum(trackSpacings())
        let naturalMajor = sum(groupSizes) + sum(majorSpacings(count: groupSizes.count))
        let crossSize = proposedCrossSize(proposal) ?? naturalCross

        return Metrics(
            trackSizes: trackSizes,
            trackOffsets: trackOffsets,
            groupSizes: groupSizes,
            groupOffsets: groupOffsets,
            size: size(major: naturalMajor, cross: crossSize)
        )
    }

    private func resolvedTrackSizes(proposedCrossSize: CGFloat?) -> [CGFloat] {
        guard !items.isEmpty else { return [] }

        let spacings = trackSpacings()
        let totalSpacing = sum(spacings)
        var sizes = Array(repeating: CGFloat.zero, count: items.count)
        var flexibleIndices: [Int] = []
        var fixedTotal = CGFloat.zero

        for (index, item) in items.enumerated() {
            switch item.size {
            case .fixed(let value):
                let size = max(0, value)
                sizes[index] = size
                fixedTotal += size
            case .flexible, .adaptive:
                flexibleIndices.append(index)
            }
        }

        let proposedShare: CGFloat?
        if let proposedCrossSize {
            proposedShare = flexibleIndices.isEmpty ? nil :
                max(0, proposedCrossSize - fixedTotal - totalSpacing) / CGFloat(flexibleIndices.count)
        } else {
            proposedShare = nil
        }

        for index in flexibleIndices {
            switch items[index].size {
            case .fixed:
                break
            case .flexible(let minimum, let maximum):
                sizes[index] = clamped(proposedShare ?? minimum, minimum: minimum, maximum: maximum)
            case .adaptive(let minimum, let maximum):
                sizes[index] = clamped(proposedShare ?? minimum, minimum: minimum, maximum: maximum)
            }
        }

        return sizes
    }

    private func childProposal(forTrack trackSize: CGFloat) -> ProposedViewSize {
        switch axis {
        case .vertical:
            return ProposedViewSize(width: trackSize, height: nil)
        case .horizontal:
            return ProposedViewSize(width: nil, height: trackSize)
        }
    }

    private func cellRect(bounds: CGRect, track: Int, group: Int, metrics: Metrics) -> CGRect {
        switch axis {
        case .vertical:
            return CGRect(
                x: bounds.minX + metrics.trackOffsets[track],
                y: bounds.minY + metrics.groupOffsets[group],
                width: metrics.trackSizes[track],
                height: metrics.groupSizes[group]
            )
        case .horizontal:
            return CGRect(
                x: bounds.minX + metrics.groupOffsets[group],
                y: bounds.minY + metrics.trackOffsets[track],
                width: metrics.groupSizes[group],
                height: metrics.trackSizes[track]
            )
        }
    }

    private func origin(for childSize: CGSize, in cell: CGRect, alignment: Alignment) -> CGPoint {
        CGPoint(
            x: alignedOffset(
                start: cell.minX,
                container: cell.width,
                child: childSize.width,
                horizontal: alignment.horizontal
            ),
            y: alignedOffset(
                start: cell.minY,
                container: cell.height,
                child: childSize.height,
                vertical: alignment.vertical
            )
        )
    }

    private func alignedOffset(
        start: CGFloat,
        container: CGFloat,
        child: CGFloat,
        horizontal alignment: HorizontalAlignment
    ) -> CGFloat {
        if alignment == .leading {
            return start
        }
        if alignment == .trailing {
            return start + container - child
        }
        return start + (container - child) * 0.5
    }

    private func alignedOffset(
        start: CGFloat,
        container: CGFloat,
        child: CGFloat,
        vertical alignment: VerticalAlignment
    ) -> CGFloat {
        if alignment == .top {
            return start
        }
        if alignment == .bottom {
            return start + container - child
        }
        return start + (container - child) * 0.5
    }

    private func proposedCrossSize(_ proposal: ProposedViewSize) -> CGFloat? {
        let value = axis == .vertical ? proposal.width : proposal.height
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }

    private func major(_ size: CGSize) -> CGFloat {
        axis == .vertical ? size.height : size.width
    }

    private func size(major: CGFloat, cross: CGFloat) -> CGSize {
        switch axis {
        case .vertical:
            return CGSize(width: cross, height: major)
        case .horizontal:
            return CGSize(width: major, height: cross)
        }
    }

    private func trackSpacings() -> [CGFloat] {
        guard items.count > 1 else { return [] }
        return items.dropLast().map { $0.spacing ?? defaultLazyGridSpacing }
    }

    private func majorSpacings(count: Int) -> [CGFloat] {
        guard count > 1 else { return [] }
        return Array(repeating: spacing ?? defaultLazyGridSpacing, count: count - 1)
    }

    private func offsets(sizes: [CGFloat], spacings: [CGFloat]) -> [CGFloat] {
        guard !sizes.isEmpty else { return [] }
        var result = Array(repeating: CGFloat.zero, count: sizes.count)
        var offset = CGFloat.zero
        for index in sizes.indices {
            result[index] = offset
            offset += sizes[index]
            if index < spacings.count {
                offset += spacings[index]
            }
        }
        return result
    }

    private func clamped(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }

    private func sum(_ values: [CGFloat]) -> CGFloat {
        values.reduce(0, +)
    }
}

extension _LazyGridLayout: _VariadicView_UnaryViewRoot {
}

protocol HVGrid: LazyStack where MinorGeometry == [HVGridGeometry] {
    var gridItems: [GridItem] { get }
    var minorAxisAnchor: CGFloat { get }
}

extension HVGrid {
    func flexibleMinorSize(subviews: _LazyLayout_Subviews) -> CGFloat {
        guard !gridItems.isEmpty else { return 0 }

        var result = CGFloat.zero
        for index in gridItems.indices {
            var from = index
            var idealMinorSize = CGFloat.zero
            _ = subviews.apply(from: &from) { _, subview, stop in
                let item = subview.cache.item(data: subview.data)
                let layoutComputer = item.outputs._layoutComputer.attribute?.value ?? .defaultValue
                let idealSize = layoutComputer.sizeThatFits(.unspecified)
                idealMinorSize = Self.majorAxis == .horizontal ? idealSize.height : idealSize.width
                stop = true
            }
            result += resolvedIntrinsicMinorSize(for: gridItems[index], idealMinorSize: idealMinorSize)
            result += spacing(after: index)
        }
        return result
    }

    func minorGeometry(updatingSize size: inout CGFloat) -> (count: Int, data: [HVGridGeometry]) {
        guard !gridItems.isEmpty, size.isFinite else {
            return (0, [])
        }

        let requestedSize = max(0, size)
        var remainingSize = requestedSize
        var flexibleItemCount = 0

        for index in gridItems.indices {
            switch gridItems[index].size {
            case .fixed(let value):
                remainingSize -= max(0, value)
            case .flexible, .adaptive:
                flexibleItemCount += 1
            }
            remainingSize -= spacing(after: index)
        }

        var position = CGFloat.zero
        var geometry: [HVGridGeometry] = []
        geometry.reserveCapacity(gridItems.count)

        for index in gridItems.indices {
            let item = gridItems[index]
            let spacingAfterItem = spacing(after: index)
            let anchor = anchor(for: item)

            switch item.size {
            case .fixed(let value):
                let trackSize = max(0, value)
                geometry.append(HVGridGeometry(position: position, size: trackSize, anchor: anchor))
                position += trackSize

            case .flexible(let minimum, let maximum):
                let trackSize = resolvedFlexibleMinorSize(
                    remainingSize: remainingSize,
                    remainingFlexibleItemCount: flexibleItemCount,
                    minimum: minimum,
                    maximum: maximum
                )
                geometry.append(HVGridGeometry(position: position, size: trackSize, anchor: anchor))
                remainingSize -= trackSize
                flexibleItemCount -= 1
                position += trackSize

            case .adaptive(let minimum, let maximum):
                let adaptive = resolvedAdaptiveMinorSize(
                    remainingSize: remainingSize,
                    remainingFlexibleItemCount: flexibleItemCount,
                    minimum: minimum,
                    maximum: maximum,
                    spacing: spacing(within: item)
                )
                for offset in 0..<adaptive.count {
                    let trackPosition = position + CGFloat(offset) * (adaptive.size + spacing(within: item))
                    geometry.append(HVGridGeometry(
                        position: trackPosition,
                        size: adaptive.size,
                        anchor: anchor
                    ))
                }
                remainingSize -= adaptive.totalLength
                flexibleItemCount -= 1
                position += adaptive.totalLength
            }

            position += spacingAfterItem
        }

        if position > requestedSize {
            size = position
        } else if position < requestedSize {
            let offset = (requestedSize - position) * minorAxisAnchor
            for index in geometry.indices {
                geometry[index].position += offset
            }
        }

        return (geometry.count, geometry)
    }

    func lengthAndSpacing(
        subviews: [_LazyLayout_Subview],
        predecessors: [_LazyLayout_Subview]?,
        minorGeometry: [HVGridGeometry]
    ) -> (length: CGFloat, spacing: CGFloat) {
        guard !subviews.isEmpty else {
            return (0, 0)
        }
        precondition(subviews.count <= minorGeometry.count)

        var length = CGFloat.zero
        var maximumSpacing = CGFloat.zero
        for index in subviews.indices {
            let geometry = minorGeometry[index]
            let predecessor = predecessors.flatMap { index < $0.count ? $0[index] : nil }
            let measured = subviews[index].lengthAndSpacing(
                size: proposedSize(minor: geometry.size, length: nil),
                axis: Self.majorAxis,
                predecessor: predecessor,
                uniformSpacing: spacing
            )
            length = max(length, measured.length)
            maximumSpacing = max(maximumSpacing, measured.spacing)
        }
        return (length, maximumSpacing)
    }

    func place(
        subviews: [_LazyLayout_Subview],
        length: CGFloat?,
        minorGeometry: [HVGridGeometry],
        emit: (_LazyLayout_Subview, CGPoint, _ProposedSize, UnitPoint) -> Void
    ) {
        guard !subviews.isEmpty else { return }
        precondition(subviews.count <= minorGeometry.count)

        for index in subviews.indices {
            let geometry = minorGeometry[index]
            let point: CGPoint
            switch Self.majorAxis {
            case .horizontal:
                point = CGPoint(x: 0, y: geometry.position)
            case .vertical:
                point = CGPoint(x: geometry.position, y: 0)
            }
            emit(
                subviews[index],
                point,
                proposedSize(minor: geometry.size, length: length),
                geometry.anchor
            )
        }
    }

    private func proposedSize(minor: CGFloat, length: CGFloat?) -> ProposedViewSize {
        switch Self.majorAxis {
        case .horizontal:
            return ProposedViewSize(width: length, height: minor)
        case .vertical:
            return ProposedViewSize(width: minor, height: length)
        }
    }

    private func resolvedIntrinsicMinorSize(for item: GridItem, idealMinorSize: CGFloat) -> CGFloat {
        switch item.size {
        case .fixed(let value):
            return max(0, value)
        case .flexible(let minimum, let maximum),
             .adaptive(let minimum, let maximum):
            return clamped(max(idealMinorSize, minimum), minimum: minimum, maximum: maximum)
        }
    }

    private func resolvedFlexibleMinorSize(
        remainingSize: CGFloat,
        remainingFlexibleItemCount: Int,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        let share = flexibleShare(
            remainingSize: remainingSize,
            remainingFlexibleItemCount: remainingFlexibleItemCount
        )
        return clamped(share, minimum: minimum, maximum: maximum)
    }

    private func resolvedAdaptiveMinorSize(
        remainingSize: CGFloat,
        remainingFlexibleItemCount: Int,
        minimum: CGFloat,
        maximum: CGFloat,
        spacing: CGFloat
    ) -> (count: Int, size: CGFloat, totalLength: CGFloat) {
        let share = flexibleShare(
            remainingSize: remainingSize,
            remainingFlexibleItemCount: remainingFlexibleItemCount
        )
        let denominator = minimum + spacing
        let count: Int
        if denominator > 0 {
            count = max(1, Int(floor(max(0, share - minimum) / denominator)) + 1)
        } else {
            count = 1
        }
        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let size = min(maximum, max(0, (share - totalSpacing) / CGFloat(count)))
        let totalLength = size * CGFloat(count) + totalSpacing
        return (count, size, totalLength)
    }

    private func flexibleShare(remainingSize: CGFloat, remainingFlexibleItemCount: Int) -> CGFloat {
        guard remainingFlexibleItemCount > 0 else { return 0 }
        return max(0, remainingSize) / CGFloat(remainingFlexibleItemCount)
    }

    private func clamped(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }

    private func spacing(after index: Int) -> CGFloat {
        guard index < gridItems.count - 1 else { return 0 }
        return spacing(within: gridItems[index])
    }

    private func spacing(within item: GridItem) -> CGFloat {
        item.spacing ?? defaultLazyGridSpacing
    }

    private func anchor(for item: GridItem) -> UnitPoint {
        switch Self.majorAxis {
        case .horizontal:
            return UnitPoint(x: 0.5, y: item.alignment?.vertical.fraction ?? minorAxisAnchor)
        case .vertical:
            return UnitPoint(x: item.alignment?.horizontal.fraction ?? minorAxisAnchor, y: 0.5)
        }
    }
}
