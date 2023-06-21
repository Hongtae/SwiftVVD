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

class CanvasContext<Symbols>: ViewProxy where Symbols: View {

    typealias Content = Canvas<Symbols>
    var view: _GraphValue<Content>
    
    var modifiers: [ObjectIdentifier: any ViewModifier]
    var traits: [ObjectIdentifier: Any]
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext
    var frame: CGRect

    init(view: _GraphValue<Content>, inputs: _ViewInputs) {
        self.modifiers = inputs.modifiers
        self.traits = inputs.traits
        self.environmentValues = inputs.environmentValues
        self.view = self.environmentValues._resolve(view)
        self.sharedContext = inputs.sharedContext
        self.frame = .zero
    }

    func draw(frame: CGRect, context: GraphicsContext) {
        if self.frame.width > 0 && self.frame.height > 0 {
            context.drawLayer(in: frame) { context, size in
                let renderer = self.view[\.renderer].value
                renderer(&context, size)
            }
        }
    }

    func modifier<K>(key: K.Type) -> K? where K : ViewModifier {
        modifiers[ObjectIdentifier(key)] as? K
    }

    func trait<Trait>(key: Trait.Type) -> Trait.Value where Trait: _ViewTraitKey {
        traits[ObjectIdentifier(key)] as? Trait.Value ?? Trait.defaultValue
    }

    func updateEnvironment(_ environmentValues: EnvironmentValues) {
        //self.environmentValues = environmentValues._resolve(modifiers: modifiers)
        // TODO: redraw!
    }
}

extension Canvas: _PrimitiveView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = CanvasContext(view: view, inputs: inputs)
        return _ViewOutputs(item: .view(view))
    }
}
