//
//  File: ShapeView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

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
        let generator = GenericViewGenerator(graph: view, inputs: inputs) { content, inputs in
            ShapeViewContext(view: content, inputs: inputs.base, graph: view)
        }
        return _ViewOutputs(view: generator)
    }

    public typealias Body = Never
}

extension _ShapeView: _PrimitiveView {
}

private class ShapeViewContext<Content, Style> : ViewContext where Content: Shape, Style: ShapeStyle {
    typealias ShapeView = _ShapeView<Content, Style>
    let view: ShapeView
    var shape: Content          { view.shape }
    var style: Style            { view.style }
    var fillStyle: FillStyle    { view.fillStyle }

    init(view: _ShapeView<Content, Style>, inputs: _GraphInputs, graph: _GraphValue<ShapeView>) {
        self.view = view
        super.init(inputs: inputs, graph: graph)
    }

    override func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
        self._validPath = false
        if graph.value(atPath: self.graph, from: encloser) is ShapeView {
            self._validPath = true
            return true
        }
        return false
    }

    override func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        self.shape.sizeThatFits(proposal)
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        if let drawer = self.shape as? ShapeDrawer {
            drawer._draw(in: frame, style: self.style, fillStyle: self.fillStyle, context: context)
        } else {
            let path = self.shape.path(in: frame)
            context.fill(path, with: .style(self.style), style: self.fillStyle)
        }
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        if self.frame.contains(location) {
            if self.shape is ShapeDrawer {
                // TODO: Find the closest distance to Path-Stroke
                //Log.warn("Hit testing for path-stroke is not yet implemented.")
            } else {
                let path = self.shape.path(in: frame)
                if path.contains(location, eoFill: self.fillStyle.isEOFilled) {
                    return self
                }
            }
        }
        return super.hitTest(location)
    }
}
