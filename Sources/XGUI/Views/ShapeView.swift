//
//  File: ShapeView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _ShapeView<Content, Style> : View where Content : Shape, Style : ShapeStyle {
    public var shape: Content
    public var style: Style
    public var fillStyle: FillStyle

    public init(shape: Content, style: Style, fillStyle: FillStyle = FillStyle()) {
        self.shape = shape
        self.style = style
        self.fillStyle = fillStyle
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            ShapeViewContext<Content, Style>(graph: graph, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }

    public typealias Body = Never
}

extension _ShapeView : _PrimitiveView {
}

private class ShapeViewContext<Content, Style> : PrimitiveViewContext<_ShapeView<Content, Style>> where Content : Shape, Style : ShapeStyle {
    typealias ShapeView = _ShapeView<Content, Style>

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if let shape = self.view?.shape {
            return shape.sizeThatFits(proposal)
        }
        return super.sizeThatFits(proposal)
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)
        if let view {
            let style = view.style
            let fillStyle = view.fillStyle

            if let drawer = view.shape as? ShapeDrawer {
                drawer._draw(in: frame, style: style, fillStyle: fillStyle, context: context)
            } else {
                let path = view.shape.path(in: frame)
                context.fill(path, with: .style(style), style: fillStyle)
            }
        }
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        if let view {
            let fillStyle = view.fillStyle

            if view.shape is ShapeDrawer == false {
                let path = view.shape.path(in: bounds)
                if path.contains(location, eoFill: fillStyle.isEOFilled) {
                    return self
                }
            }
        }
        return super.hitTest(location)
    }
}
