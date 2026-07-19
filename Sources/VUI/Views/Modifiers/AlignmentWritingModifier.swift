//
//  File: AlignmentWritingModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _AlignmentWritingModifier: MultiViewModifier, PrimitiveViewModifier {
    @usableFromInline
    let key: AlignmentKey
    @usableFromInline
    let computeValue: @Sendable (ViewDimensions) -> CGFloat

    @inlinable init(key: AlignmentKey, computeValue: @escaping @Sendable (ViewDimensions) -> CGFloat) {
        self.key = key
        self.computeValue = computeValue
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        if inputs.requestsLayoutComputer {
            let layoutComputer: Attribute<LayoutComputer> = graph.makeStatefulRule(
                AlignmentModifiedLayoutComputer(
                    modifier: modifier._attribute,
                    layoutComputer: outputs._layoutComputer
                )
            )
            outputs._layoutComputer = OptionalAttribute(layoutComputer)
        }
        return outputs
    }
    public typealias Body = Never
}

private struct AlignmentModifiedLayoutComputer: StatefulRule, AsyncAttribute {
    typealias Value = LayoutComputer

    var modifier: Attribute<_AlignmentWritingModifier>
    var layoutComputer: OptionalAttribute<LayoutComputer>

    mutating func updateValue() {
        let modifier = modifier.value
        let layoutComputer = layoutComputer.attribute?.value ?? .defaultValue
        update(
            to: Engine(
                key: modifier.key,
                computeValue: modifier.computeValue,
                layoutComputer: layoutComputer
            )
        )
    }

    struct Engine: LayoutEngine, LayoutEnginePlacing {
        var key: AlignmentKey
        var computeValue: @Sendable (ViewDimensions) -> CGFloat
        var layoutComputer: LayoutComputer

        func layoutPriority() -> Double {
            layoutComputer.layoutPriority()
        }

        func ignoresAutomaticPadding() -> Bool {
            layoutComputer.ignoresAutomaticPadding()
        }

        func requiresSpacingProjection() -> Bool {
            layoutComputer.requiresSpacingProjection()
        }

        func spacing() -> Spacing {
            layoutComputer.spacing()
        }

        func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
            layoutComputer.sizeThatFits(proposal)
        }

        func lengthThatFits(_ proposal: _ProposedSize, in axis: Axis) -> CGFloat {
            layoutComputer.lengthThatFits(proposal, in: axis)
        }

        func childGeometries(at size: ViewSize, origin: CGPoint) -> [ViewGeometry] {
            layoutComputer.childGeometries(at: size, origin: origin)
        }

        func explicitAlignment(_ requestedKey: AlignmentKey, at size: ViewSize) -> CGFloat? {
            if requestedKey == key {
                return computeValue(
                    ViewDimensions(guideComputer: layoutComputer, size: size)
                )
            }
            return layoutComputer.explicitAlignment(requestedKey, at: size)
        }

        mutating func childPlacement(at size: ViewSize) -> _Placement {
            layoutComputer.childPlacement(at: size)
        }

        mutating func childPlacement(
            at size: ViewSize,
            placementContext: _PositionAwarePlacementContext
        ) -> _Placement {
            layoutComputer.childPlacement(
                at: size,
                placementContext: placementContext
            )
        }

        mutating func place(
            at position: CGPoint,
            anchor: UnitPoint,
            proposal: ProposedViewSize
        ) {
            layoutComputer.place(at: position, anchor: anchor, proposal: proposal)
        }
    }
}

extension View {
    @inlinable public func alignmentGuide(_ g: HorizontalAlignment, computeValue: @escaping @Sendable (ViewDimensions) -> CGFloat) -> some View {
        return modifier(
            _AlignmentWritingModifier(key: g.key, computeValue: computeValue))
    }

    @inlinable public func alignmentGuide(_ g: VerticalAlignment, computeValue: @escaping @Sendable (ViewDimensions) -> CGFloat) -> some View {
        return modifier(
            _AlignmentWritingModifier(key: g.key, computeValue: computeValue))
    }
}
