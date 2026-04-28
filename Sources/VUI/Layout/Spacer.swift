//
//  File: Spacer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Spacer: View {
    public var minLength: CGFloat?
    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }

    public typealias Body = Never
}

extension Spacer: Sendable {
}

extension Spacer: _PrimitiveView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let minLen = view._attribute.value.minLength ?? 0
            return LayoutComputer(
                sizeThatFits: { proposal in
                    CGSize(
                        width:  proposal.width.map  { max($0, minLen) } ?? minLen,
                        height: proposal.height.map { max($0, minLen) } ?? minLen
                    )
                }
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(lcAttr))
    }
}

public struct Divider: View {
    public init() {
    }

    public typealias Body = Never
}

extension Divider: _PrimitiveView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            LayoutComputer(
                sizeThatFits: { proposal in
                    CGSize(width: proposal.width ?? 0, height: 1)
                }
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(lcAttr))
    }
}
