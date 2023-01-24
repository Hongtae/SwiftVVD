//
//  File: Canvas.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
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

struct CanvasContext<Symbols>: ViewProxy where Symbols: View {
    typealias Content = Canvas<Symbols>
    var view: Content

    var modifiers: [any ViewModifier]
    var subviews: [any ViewProxy]

    var size: CGSize

    init(view: Content, modifiers: [any ViewModifier]) {
        self.view = view
        self.modifiers = modifiers
        self.subviews = []
        self.size = .zero
    }

    func draw() {
        var gc = GraphicsContext(opacity: 1.0, blendMode: .normal, transform: .identity)
        self.view.renderer(&gc, self.size)
        //print("Canvas.draw")
    }
}

extension Canvas: _PrimitiveView {
    func makeViewProxy(modifiers: [any ViewModifier]) -> any ViewProxy {
        CanvasContext(view: self, modifiers: modifiers)
    }
}
