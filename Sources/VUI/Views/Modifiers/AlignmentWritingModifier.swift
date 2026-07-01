//
//  File: AlignmentWritingModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _AlignmentWritingModifier: ViewModifier {
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
        let childOutputs = body(_Graph(), inputs)
        guard let childLCAttr = childOutputs._layoutComputer.attribute else {
            return childOutputs
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let m = modifier._attribute.value   // dep: key/computeValue changes
            let childLC = childLCAttr.value     // dep: child layout changes
            return LayoutComputer(
                sizeThatFits: { childLC.sizeThatFits($0) },
                spacing: childLC.spacing,
                place: { childLC.place(at: $0, anchor: $1, proposal: $2) },
                explicitAlignment: { key, size in
                    if key == m.key {
                        let dims = ViewDimensions(guideComputer: childLC, size: size)
                        return m.computeValue(dims)
                    }
                    return childLC.explicitAlignment(key, at: size)
                }
            )
        }
        return _ViewOutputs(
            preferences: childOutputs.preferences,
            layoutComputer: OptionalAttribute(lcAttr)
        )
    }
    public typealias Body = Never
}

extension _AlignmentWritingModifier {
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
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
