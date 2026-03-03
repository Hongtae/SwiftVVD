//
//  File: ShapeView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _ShapeView<Content, Style>: View where Content: Shape, Style: ShapeStyle {
    public var shape: Content
    public var style: Style
    public var fillStyle: FillStyle

    public init(shape: Content, style: Style, fillStyle: FillStyle = FillStyle()) {
        self.shape = shape
        self.style = style
        self.fillStyle = fillStyle
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let v = view._attribute.value   // dep: shape/style changes
            return LayoutComputer(
                sizeThatFits: { proposal in v.shape.sizeThatFits(proposal) },
                dimensions: { proposal in
                    let size = v.shape.sizeThatFits(proposal)
                    return ViewDimensions(width: size.width, height: size.height)
                }
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(lcAttr))
    }

    public typealias Body = Never
}

extension _ShapeView: _PrimitiveView {
}

