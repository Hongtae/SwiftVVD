//
//  File: LazyGrid.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

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

protocol HVGrid: LazyStack where MinorGeometry == [HVGridGeometry] {
    var minorAxisAnchor: CGFloat { get }
}

/// Supplies concrete row or column storage to the shared grid default bodies.
protocol HVGridLayoutStorage: HVGrid {
    var gridItems: [GridItem] { get }
}

extension HVGrid where Self: HVGridLayoutStorage {
    static var layoutProperties: _LazyLayout_Properties {
        _LazyLayout_Properties(
            axes: Axis.Set(majorAxis),
            multipleViewAxes: [.horizontal, .vertical]
        )
    }

    var headerAnchor: UnitPoint {
        UnitPoint(0.5, in: Self.majorAxis, by: minorAxisAnchor)
    }

    var footerAnchor: UnitPoint {
        UnitPoint(0.5, in: Self.majorAxis, by: minorAxisAnchor)
    }

    func flexibleMinorSize(subviews: _LazyLayout_Subviews) -> CGFloat {
        let gridItems = gridItems
        var result = CGFloat.zero
        let defaultSpacing = Self.majorAxis == .horizontal
            ? Spacing.defaultValue.width
            : Spacing.defaultValue.height

        for index in gridItems.indices {
            // A cancelled graph update invalidates the partial aggregate.
            if _AGGraph.currentUpdateContext != nil,
               _AGGraphCancelUpdateIfNeeded() {
                return 0
            }

            var from = index
            _ = subviews.apply(from: &from) { subview, stop in
                defer { stop = true }

                if _AGGraph.currentUpdateContext != nil,
                   _AGGraphCancelUpdateIfNeeded() {
                    return
                }
                let layout = subview.layout
                if _AGGraph.currentUpdateContext != nil,
                   _AGGraphCancelUpdateIfNeeded() {
                    return
                }

                let idealSize = layout.idealSize()
                switch Self.majorAxis {
                case .horizontal:
                    result += idealSize.height
                case .vertical:
                    result += idealSize.width
                }

                if index < gridItems.count - 1 {
                    result += gridItems[index].spacing ?? defaultSpacing
                }
            }

            // Earlier linked clients measured only the first declared track.
            if !isLinkedOnOrAfter(.v5) {
                break
            }
        }
        return result
    }

    func minorGeometry(updatingSize size: inout CGFloat) -> (count: Int, data: [HVGridGeometry]) {
        let gridItems = gridItems
        guard !gridItems.isEmpty, size.isFinite else {
            return (0, [])
        }

        // Preserve the caller's raw extent; fixed sizes and spacing are not
        // sanitized before track resolution.
        let requestedSize = size
        let defaultSpacing = Self.majorAxis == .horizontal
            ? Spacing.defaultValue.width
            : Spacing.defaultValue.height
        var remainingSize = requestedSize
        var flexibleItemCount = 0

        // Fixed tracks consume the shared budget up front. Flexible and
        // adaptive tracks resolve sequentially from the remaining share.
        for index in gridItems.indices {
            let item = gridItems[index]
            switch item.size {
            case .fixed(let value):
                remainingSize -= value
            case .flexible, .adaptive:
                flexibleItemCount += 1
            }
            if index < gridItems.count - 1 {
                remainingSize -= item.spacing ?? defaultSpacing
            }
        }

        var position = CGFloat.zero
        var geometry: [HVGridGeometry] = []
        geometry.reserveCapacity(gridItems.count)

        for index in gridItems.indices {
            let item = gridItems[index]
            let itemSpacing = item.spacing ?? defaultSpacing
            let spacingAfterItem = index < gridItems.count - 1
                ? itemSpacing
                : 0
            let anchor = item.alignment?.fraction
                ?? UnitPoint(0.5, in: Self.majorAxis, by: minorAxisAnchor)
            let trackLength: CGFloat

            switch item.size {
            case .fixed(let value):
                geometry.append(
                    HVGridGeometry(
                        position: position,
                        size: value,
                        anchor: anchor
                    )
                )
                trackLength = value

            case .flexible(let minimum, let maximum):
                precondition(minimum <= maximum)
                let share = max(remainingSize, 0) / CGFloat(flexibleItemCount)
                let trackSize = min(max(share, minimum), maximum)
                geometry.append(
                    HVGridGeometry(
                        position: position,
                        size: trackSize,
                        anchor: anchor
                    )
                )
                remainingSize -= trackSize
                flexibleItemCount -= 1
                trackLength = trackSize

            case .adaptive(let minimum, let maximum):
                let share = max(remainingSize, 0) / CGFloat(flexibleItemCount)
                let count = Int(
                    max(
                        floor((share - minimum) / (minimum + itemSpacing)),
                        0
                    ) + 1
                )
                let totalSpacing = itemSpacing * CGFloat(count - 1)
                let trackSize = min(
                    (share - totalSpacing) / CGFloat(count),
                    maximum
                )

                // One adaptive declaration may expand into several geometry
                // records, with its own spacing inside the shared track span.
                for offset in 0..<count {
                    geometry.append(
                        HVGridGeometry(
                            position: position
                                + CGFloat(offset) * (trackSize + itemSpacing),
                            size: trackSize,
                            anchor: anchor
                        )
                    )
                }
                trackLength = trackSize * CGFloat(count) + totalSpacing
                remainingSize -= trackLength
                flexibleItemCount -= 1
            }
            position += trackLength + spacingAfterItem
        }

        if requestedSize <= position {
            size = position
        } else {
            // Surplus minor-axis space shifts the complete generated group.
            let offset = (requestedSize - position) * minorAxisAnchor
            if offset != 0 {
                for index in geometry.indices {
                    geometry[index].position += offset
                }
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
            let predecessor = predecessors.flatMap {
                index < $0.count ? $0[index] : nil
            }
            let proposedSize = ProposedViewSize(
                _ProposedSize(
                    nil,
                    in: Self.majorAxis,
                    by: geometry.size
                )
            )
            let measured = subviews[index].lengthAndSpacing(
                size: proposedSize,
                axis: Self.majorAxis,
                predecessor: predecessor,
                uniformSpacing: spacing
            )
            // A grid group advances by its largest child length and spacing.
            length = max(length, measured.length)
            maximumSpacing = max(maximumSpacing, measured.spacing)

            // Keep the accumulated prefix when the active update is cancelled.
            if _AGGraph.currentUpdateContext != nil,
               _AGGraphCancelUpdateIfNeeded() {
                break
            }
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
            // Track geometry owns the minor-axis coordinate, proposal, and
            // full placement anchor for the corresponding lazy subview.
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
                _ProposedSize(
                    length,
                    in: Self.majorAxis,
                    by: geometry.size
                ),
                geometry.anchor
            )
        }
    }
}
