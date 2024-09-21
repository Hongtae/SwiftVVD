//
//  File: Canvas.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

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
        let generator = GenericViewGenerator(graph: view, inputs: inputs) { content, inputs in
            CanvasViewContext(view: content, inputs: inputs.base, graph: view)
        }
        return _ViewOutputs(view: generator)
    }
}

extension Canvas: _PrimitiveView {
}

private class CanvasViewContext<Symbols>: ViewContext where Symbols: View {
    typealias Content = Canvas<Symbols>
    var view: Content
    
    init(view: Content, inputs: _GraphInputs, graph: _GraphValue<Content>) {
        self.view = view
        super.init(inputs: inputs, graph: graph)
    }

    override func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
        self._validPath = false
        if graph.value(atPath: self.graph, from: encloser) is Content {
            self._validPath = true
            return true
        }
        return false
    }

    override func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
        if let view = graph.value(atPath: self.graph, from: encloser) as? Content {
            self.view = view
        } else {
            fatalError("Unable to recover Canvas")
        }
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)

        if self.frame.width > 0 && self.frame.height > 0 {
            context.drawLayer(in: frame) { context, size in
                let renderer = self.view.renderer
                renderer(&context, size)
            }
        }
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        if self.frame.contains(location) {
            return self
        }
        return super.hitTest(location)
    }
}
