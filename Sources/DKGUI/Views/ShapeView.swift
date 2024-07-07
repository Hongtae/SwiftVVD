//
//  File: ShapeView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
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
        let generator = ShapeViewContext.Generator(graph: view, baseInputs: inputs.base)
        return _ViewOutputs(view: generator, preferences: .init(preferences: []))
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

    struct Generator : ViewGenerator {
        let graph: _GraphValue<ShapeView>
        var baseInputs: _GraphInputs

        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let view = graph.value(atPath: self.graph, from: encloser) {
                return ShapeViewContext(view: view, inputs: baseInputs, graph: self.graph)
            }
            return nil
        }
    }

    init(view: _ShapeView<Content, Style>, inputs: _GraphInputs, graph: _GraphValue<ShapeView>) {
        self.view = view
        super.init(inputs: inputs, graph: graph)
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
}
