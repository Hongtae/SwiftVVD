//
//  File: BackgroundModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _BackgroundModifier<Background>: ViewModifier where Background: View {
    public var background: Background
    public var alignment: Alignment

    @inlinable public init(background: Background, alignment: Alignment = .center) {
        self.background = background
        self.alignment = alignment
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let mainOutputs = body(_Graph(), inputs)
        guard let mainLCAttr = mainOutputs._layoutComputer.attribute else {
            return mainOutputs
        }
        let bgPosAttr = graph.makeInput(value: CGPoint.zero)
        let bgInputs = _ViewInputs(
            base: inputs.base,
            preferences: inputs.preferences,
            transform: inputs.transform,
            position: bgPosAttr,
            containerPosition: inputs.position,
            size: inputs.size,
            safeAreaInsets: inputs.safeAreaInsets,
            containerSize: inputs.containerSize
        )
        let bgOutputs = Background._makeView(view: modifier[\.background], inputs: bgInputs)
        guard let bgLCAttr = bgOutputs._layoutComputer.attribute else {
            return mainOutputs
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let m = modifier._attribute.value   // dep: alignment changes
            let mainLC = mainLCAttr.value       // dep: main content changes
            let bgLC = bgLCAttr.value           // dep: background changes
            return LayoutComputer(
                sizeThatFits: { proposal in mainLC.sizeThatFits(proposal) },
                spacing: mainLC.spacing,
                dimensions: { proposal in mainLC.dimensions(in: proposal) },
                place: { position, anchor, proposal in
                    mainLC.place(at: position, anchor: anchor, proposal: proposal)
                    let mainSize = mainLC.sizeThatFits(proposal)
                    let ox = position.x - mainSize.width * anchor.x
                    let oy = position.y - mainSize.height * anchor.y
                    let mainDims = mainLC.dimensions(in: proposal)
                    let bgProposal = ProposedViewSize(width: mainSize.width, height: mainSize.height)
                    let bgDims = bgLC.dimensions(in: bgProposal)
                    let bgX = ox + mainDims[m.alignment.horizontal] - bgDims[m.alignment.horizontal]
                    let bgY = oy + mainDims[m.alignment.vertical] - bgDims[m.alignment.vertical]
                    let bgOrigin = CGPoint(x: bgX, y: bgY)
                    bgPosAttr.setValue(bgOrigin)
                    bgLC.place(at: bgOrigin, anchor: .topLeading, proposal: bgProposal)
                }
            )
        }
        return _ViewOutputs(
            preferences: mainOutputs.preferences,
            layoutComputer: OptionalAttribute(lcAttr)
        )
    }
}

extension _BackgroundModifier: Equatable where Background: Equatable {
}

extension _BackgroundModifier {
    public typealias Body = Never

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

public struct _BackgroundStyleModifier<Style>: ViewModifier where Style: ShapeStyle {
    public var style: Style
    public var ignoresSafeAreaEdges: Edge.Set

    @inlinable public init(style: Style, ignoresSafeAreaEdges: Edge.Set) {
        self.style = style
        self.ignoresSafeAreaEdges = ignoresSafeAreaEdges
    }

    // TODO: Wire style fill as a background layer once rendering context is available.
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
}

extension _BackgroundStyleModifier {
    public typealias Body = Never

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

public struct _BackgroundShapeModifier<Style, Bounds>: ViewModifier where Style: ShapeStyle, Bounds: Shape {
    public var style: Style
    public var shape: Bounds
    public var fillStyle: FillStyle

    @inlinable public init(style: Style, shape: Bounds, fillStyle: FillStyle) {
        self.style = style
        self.shape = shape
        self.fillStyle = fillStyle
    }

    // TODO: Wire shape fill as a background layer once rendering context is available.
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
}

extension _BackgroundShapeModifier {
    public typealias Body = Never

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

public struct _InsettableBackgroundShapeModifier<Style, Bounds>: ViewModifier where Style: ShapeStyle, Bounds: InsettableShape {
    public var style: Style
    public var shape: Bounds
    public var fillStyle: FillStyle

    @inlinable public init(style: Style, shape: Bounds, fillStyle: FillStyle) {
        self.style = style
        self.shape = shape
        self.fillStyle = fillStyle
    }

    // TODO: Wire insettable shape fill as a background layer once rendering context is available.
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
}

extension _InsettableBackgroundShapeModifier {
    public typealias Body = Never

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

extension View {
    @inlinable public func background<V>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View where V: View {
        modifier(
            _BackgroundModifier(background: content(), alignment: alignment))
    }

    @inlinable public func background(ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        modifier(_BackgroundStyleModifier(
            style: .background, ignoresSafeAreaEdges: edges))
    }

    @inlinable public func background<S>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View where S: ShapeStyle {
        modifier(_BackgroundStyleModifier(
            style: style, ignoresSafeAreaEdges: edges))
    }

    @inlinable public func background<S>(in shape: S, fillStyle: FillStyle = FillStyle()) -> some View where S: Shape {
        modifier(_BackgroundShapeModifier(
            style: .background, shape: shape, fillStyle: fillStyle))
    }

    @inlinable public func background<S, T>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View where S: ShapeStyle, T: Shape {
        modifier(_BackgroundShapeModifier(
            style: style, shape: shape, fillStyle: fillStyle))
    }

    @inlinable public func background<S>(in shape: S, fillStyle: FillStyle = FillStyle()) -> some View where S: InsettableShape {
        modifier(_InsettableBackgroundShapeModifier(
            style: .background, shape: shape, fillStyle: fillStyle))
    }

    @inlinable public func background<S, T>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View where S: ShapeStyle, T: InsettableShape {
        modifier(_InsettableBackgroundShapeModifier(
            style: style, shape: shape, fillStyle: fillStyle))
    }
}

private protocol _BackgroundModifierWithAlignment {
    var alignment: Alignment { get }
}

private protocol _BackgroundModifierWithIgnoresSafeAreaEdges {
    var ignoresSafeAreaEdges: Edge.Set { get }
}

extension _BackgroundModifier: _BackgroundModifierWithAlignment {
}

extension _BackgroundStyleModifier: _BackgroundModifierWithIgnoresSafeAreaEdges {
}

