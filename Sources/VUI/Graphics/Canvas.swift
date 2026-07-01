//
//  File: Canvas.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public enum ColorRenderingMode: Equatable, Hashable, Sendable {
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
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            LayoutComputer(
                sizeThatFits: { proposal in
                    CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
                }
            )
        }
        let sizeAttr = inputs.size
        let positionAttr = inputs.position
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let canvas = view._attribute.value
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            var list = DisplayList()
            if viewSize.width > 0 && viewSize.height > 0 {
                let frame = CGRect(origin: position, size: viewSize)
                list.appendCustomItem(
                    bounds: frame,
                    isOpaque: canvas.isOpaque,
                    colorMode: canvas.colorMode,
                    rendersAsynchronously: canvas.rendersAsynchronously
                ) { context in
                    context.drawLayer(in: frame) { layerContext, size in
                        canvas.renderer(&layerContext, size)
                    }
                }
            }
            return list
        }

        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(lcAttr))
        outputs.preferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        return outputs
    }
}

extension Canvas: _PrimitiveView {
}
