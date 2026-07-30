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
                    _modifier: modifier._attribute,
                    _childLayoutComputer: outputs._layoutComputer
                )
            )
            outputs._layoutComputer = OptionalAttribute(layoutComputer)
        }
        return outputs
    }
    public typealias Body = Never
}

/// Wraps a child layout computer with one explicit alignment-guide override.
private struct AlignmentModifiedLayoutComputer: StatefulRule, AsyncAttribute {
    typealias Value = LayoutComputer

    var _modifier: Attribute<_AlignmentWritingModifier>
    var _childLayoutComputer: OptionalAttribute<LayoutComputer>

    mutating func updateValue() {
        let modifier = _modifier.value
        let childLayoutComputer =
            _childLayoutComputer.attribute?.value ?? .defaultValue
        update(
            to: Engine(
                modifier: modifier,
                childLayoutComputer: childLayoutComputer
            )
        )
    }

    /// Forwards layout queries while intercepting the configured alignment key.
    struct Engine: LayoutEngine {
        var modifier: _AlignmentWritingModifier
        var childLayoutComputer: LayoutComputer

        func layoutPriority() -> Double {
            childLayoutComputer.layoutPriority()
        }

        func spacing() -> Spacing {
            childLayoutComputer.spacing()
        }

        func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
            childLayoutComputer.sizeThatFits(proposal)
        }

        func lengthThatFits(_ proposal: _ProposedSize, in axis: Axis) -> CGFloat {
            childLayoutComputer.lengthThatFits(proposal, in: axis)
        }

        func explicitAlignment(_ requestedKey: AlignmentKey, at size: ViewSize) -> CGFloat? {
            if requestedKey == modifier.key {
                return modifier.computeValue(
                    ViewDimensions(
                        guideComputer: childLayoutComputer,
                        size: size
                    )
                )
            }
            return childLayoutComputer.explicitAlignment(
                requestedKey,
                at: size
            )
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
