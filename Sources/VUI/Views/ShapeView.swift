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
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let sizeAttr = inputs.size
        let positionAttr = inputs.position
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let v = view._attribute.value   // dep: shape/style changes
            return LayoutComputer(
                sizeThatFits: { proposal in v.shape.sizeThatFits(proposal) }
            )
        }
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let v = view._attribute.value   // dep: shape/style/fillStyle changes
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            var list = DisplayList()
            //Log.debug("ShapeView: size=\(viewSize), position=\(position)")
            if viewSize.width > 0 && viewSize.height > 0 {
                let frame = CGRect(origin: position, size: viewSize)
                let strokeStyle = (v.shape as? ShapeStrokeStyleProviding)?.strokeStyle
                list.appendShapeItem(
                    role: Content.role,
                    style: v.style,
                    bounds: frame,
                    fillStyle: v.fillStyle,
                    strokeStyle: strokeStyle
                ) { context in
                    if let drawer = v.shape as? ShapeDrawer {
                        drawer._draw(in: frame, style: v.style, fillStyle: v.fillStyle, context: context)
                    } else {
                        let path = v.shape.path(in: frame)
                        context.fill(path, with: .style(v.style), style: v.fillStyle)
                    }
                }
            }
            return list
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(lcAttr))
        outputs.preferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        return outputs
    }

    public typealias Body = Never
}

extension _ShapeView: _PrimitiveView, LeafViewLayout {
}
