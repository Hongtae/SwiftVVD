//
//  File: Canvas.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public enum ColorRenderingMode: Equatable, Hashable {
    case nonLinear
    case linear
    case extendedLinear
}

public struct Canvas<Symbols>: View where Symbols: View {
    public var symbols: Symbols
    public var renderer: (inout GraphicsContext, CGSize) -> Void
    public var isOpaque: Bool
    public var colorMode: ColorRenderingMode
    public var rendersAsynchronously: Bool

    public init(opaque: Bool = false,
                colorMode: ColorRenderingMode = .nonLinear,
                rendersAsynchronously: Bool = false,
                renderer: @escaping (inout GraphicsContext, CGSize) -> Void,
                @ViewBuilder symbols: () -> Symbols) {
        self.symbols = symbols()
        self.renderer = renderer
        self.isOpaque = opaque
        self.colorMode = colorMode
        self.rendersAsynchronously = rendersAsynchronously
    }

    public typealias Body = Never
}

extension Canvas where Symbols == EmptyView {
    public init(opaque: Bool = false,
                colorMode: ColorRenderingMode = .nonLinear,
                rendersAsynchronously: Bool = false,
                renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {
        self.symbols = Symbols()
        self.renderer = renderer
        self.isOpaque = opaque
        self.colorMode = colorMode
        self.rendersAsynchronously = rendersAsynchronously
    }
}

extension Canvas {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            CanvasViewContext(graph: graph, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }
}

extension Canvas: _PrimitiveView {
}

private class CanvasViewContext<Symbols>: PrimitiveViewContext<Canvas<Symbols>> where Symbols: View {
    typealias Content = Canvas<Symbols>

    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)

        if let renderer = self.view?.renderer {
            let bounds = self.bounds
            if bounds.width > 0 && bounds.height > 0 {
                context.drawLayer(in: frame) { context, size in
                    renderer(&context, size)
                }
            }
        }
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        if self.bounds.contains(location) {
            return self
        }
        return super.hitTest(location)
    }
}
