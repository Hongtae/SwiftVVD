//
//  File: Canvas.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

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
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext
    var layoutOffset: CGPoint
    var layoutSize: CGSize
    var contentScaleFactor: CGFloat

    init(view: Content,
         modifiers: [any ViewModifier],
         environmentValues: EnvironmentValues,
         sharedContext: SharedContext) {
        self.modifiers = modifiers
        self.environmentValues = environmentValues._resolve(modifiers: modifiers)
        self.view = self.environmentValues._resolve(view)
        self.sharedContext = sharedContext
        self.layoutOffset = .zero
        self.layoutSize = .zero
        self.contentScaleFactor = 1
    }

    mutating func layout(offset: CGPoint, size: CGSize, scaleFactor: CGFloat) {
        self.layoutOffset = offset
        self.layoutSize = size
        self.contentScaleFactor = scaleFactor
    }

    func draw() {
        guard let queue = self.sharedContext.commandQueue else {
            Log.err("Invalid command queue")
            return
        }
        guard let backBuffer = self.sharedContext.backBuffer else {
            Log.err("Invalid back buffer")
            return
        }
        guard let stencilBuffer = self.sharedContext.stencilBuffer else {
            Log.err("Invalid depth stencil buffer")
            return
        }

        if self.layoutSize.width > 0 && self.layoutSize.height > 0 {
            if let commandBuffer = queue.makeCommandBuffer() {
                let bounds = CGRect(origin: self.layoutOffset, size: self.layoutSize)
                let resolution = CGSize(width: backBuffer.width, height: backBuffer.height)
                if var gc = GraphicsContext(environment: self.environmentValues,
                                            contentBounds: bounds,
                                            resolution: resolution,
                                            commandBuffer: commandBuffer,
                                            backBuffer: backBuffer,
                                            stencilBuffer: stencilBuffer) {
                    self.view.renderer(&gc, self.layoutSize)
                    commandBuffer.commit()
                }               
            }
        }
    }
}

extension Canvas: _PrimitiveView {
    func makeViewProxy(modifiers: [any ViewModifier],
                       environmentValues: EnvironmentValues,
                       sharedContext: SharedContext) -> any ViewProxy {
        CanvasContext(view: self,
                      modifiers: modifiers,
                      environmentValues: environmentValues,
                      sharedContext: sharedContext)
    }
}
