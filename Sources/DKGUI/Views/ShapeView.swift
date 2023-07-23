//
//  File: ShapeView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
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
        let proxy = view.value.makeViewProxy(inputs: inputs)
        return _ViewOutputs(item: .view(proxy))
    }

    public typealias Body = Never
}

extension _ShapeView: _PrimitiveView {
}

extension _ShapeView: _ViewProxyProvider {
    func makeViewProxy(inputs: _ViewInputs) -> ViewProxy {
        ShapeViewProxy(view: self, inputs: inputs)
    }
}

class ShapeViewProxy<Content, Style>: ViewProxy where Content: Shape, Style: ShapeStyle {
    let shape: Content
    let style: Style
    let fillStyle: FillStyle

    init(view: _ShapeView<Content, Style>, inputs: _ViewInputs) {
        self.shape = view.shape
        self.style = view.style
        self.fillStyle = view.fillStyle
        super.init(inputs: inputs)
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
