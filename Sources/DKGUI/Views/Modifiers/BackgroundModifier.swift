//
//  File: BackgroundModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
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
        let outputs = body(_Graph(), inputs)
        var backgroundInputs = inputs
        backgroundInputs.base.properties.replace(item: DefaultLayoutPropertyItem(layout: ZStackLayout()))
        let background = makeView(view: modifier[\.background], inputs: backgroundInputs)
        let generator = BackgroundViewContext.Generator(content: outputs.view, background: background.view, graph: modifier, baseInputs: inputs.base)
        return _ViewOutputs(view: generator, preferences: .init(preferences: []))
    }

    public typealias Body = Never
}

extension _BackgroundModifier: Equatable where Background: Equatable {
}

extension _BackgroundModifier: _UnaryViewModifier {
}

public struct _BackgroundStyleModifier<Style>: ViewModifier where Style: ShapeStyle {
    public var style: Style
    public var ignoresSafeAreaEdges: Edge.Set

    @inlinable public init(style: Style, ignoresSafeAreaEdges: Edge.Set) {
        self.style = style
        self.ignoresSafeAreaEdges = ignoresSafeAreaEdges
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        let background = makeView(view: modifier[\._shapeView], inputs: inputs)
        let generator = BackgroundViewContext.Generator(content: outputs.view, background: background.view, graph: modifier, baseInputs: inputs.base)
        return _ViewOutputs(view: generator, preferences: .init(preferences: []))
    }

    public typealias Body = Never

    var _shapeView: some View {
        _ShapeView(shape: Rectangle(), style: self.style)
    }
}

extension _BackgroundStyleModifier: _UnaryViewModifier {
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

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        let background = makeView(view: modifier[\._shapeView], inputs: inputs)
        let generator = BackgroundViewContext.Generator(content: outputs.view, background: background.view, graph: modifier, baseInputs: inputs.base)
        return _ViewOutputs(view: generator, preferences: .init(preferences: []))
    }

    public typealias Body = Never

    var _shapeView: some View {
        _ShapeView(shape: self.shape, style: self.style, fillStyle: self.fillStyle)
    }
}

extension _BackgroundShapeModifier: _UnaryViewModifier {
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

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        let background = makeView(view: modifier[\._shapeView], inputs: inputs)
        let generator = BackgroundViewContext.Generator(content: outputs.view, background: background.view, graph: modifier, baseInputs: inputs.base)
        return _ViewOutputs(view: generator, preferences: .init(preferences: []))
    }

    public typealias Body = Never

    var _shapeView : some View {
        _ShapeView(shape: self.shape, style: self.style, fillStyle: self.fillStyle)
    }
}

extension _InsettableBackgroundShapeModifier: _UnaryViewModifier {
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

extension _BackgroundModifier : _BackgroundModifierWithAlignment {
}

extension _BackgroundStyleModifier : _BackgroundModifierWithIgnoresSafeAreaEdges {
}

private class BackgroundViewContext<Modifier> : ViewModifierContext<Modifier> {
    let background: ViewContext
    let alignment: Alignment
    let ignoresSafeAreaEdges: Edge.Set

    struct Generator : ViewGenerator {
        var content: any ViewGenerator
        var background: any ViewGenerator
        let graph: _GraphValue<Modifier>
        var baseInputs: _GraphInputs

        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let content = content.makeView(encloser: encloser, graph: graph) {
                if let modifier = graph.value(atPath: self.graph, from: encloser) {
                    if let background = background.makeView(encloser: modifier, graph: self.graph) {
                        return BackgroundViewContext(content: content,
                                                     background: background,
                                                     modifier: modifier,
                                                     inputs: baseInputs,
                                                     graph: self.graph)
                    }
                } else {
                    fatalError("Unable to recover modifier")
                }
                return content
            }
            return nil
        }

        mutating func mergeInputs(_ inputs: _GraphInputs) {
            content.mergeInputs(inputs)
            background.mergeInputs(inputs)
            baseInputs.mergedInputs.append(inputs)
        }
    }

    init(content: ViewContext, background: ViewContext, modifier: Modifier, inputs: _GraphInputs, graph: _GraphValue<Modifier> ) {
        self.background = background
        if let alignmentModifier = modifier as? _BackgroundModifierWithAlignment {
            self.alignment = alignmentModifier.alignment
        } else {
            self.alignment = .center
        }
        if let ignoresSafeAreaEdgesModifier = modifier as? _BackgroundModifierWithIgnoresSafeAreaEdges {
            self.ignoresSafeAreaEdges = ignoresSafeAreaEdgesModifier.ignoresSafeAreaEdges
        } else {
            self.ignoresSafeAreaEdges = .all
        }
        super.init(content: content, modifier: modifier, inputs: inputs, graph: graph)
        self._debugDraw = false
        self.background._debugDraw = false
    }
    
    override func loadResources(_ context: GraphicsContext) {
        super.loadResources(context)
        background.loadResources(context)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        var position = frame.origin
        var anchor = UnitPoint()
        switch self.alignment.horizontal {
        case .leading:      position.x = frame.minX
            anchor.x = 0
        case .center:       position.x = frame.midX
            anchor.x = 0.5
        case .trailing:     position.x = frame.maxX
            anchor.x = 1
        default:            position.x = frame.midX
            anchor.x = 0.5
        }
        switch self.alignment.vertical {
        case .top:          position.y = frame.minY
            anchor.y = 0
        case .center:       position.y = frame.midY
            anchor.y = 0.5
        case .bottom:       position.y = frame.maxY
            anchor.y = 1
        default:            position.y = frame.midY
            anchor.y = 0.5
        }
        let proposal = ProposedViewSize(width: frame.width, height: frame.height)
        background.place(at: position,
                         anchor: anchor,
                         proposal: proposal)
    }

    override func drawBackground(frame: CGRect, context: GraphicsContext) {
        let width = background.frame.width
        let height = background.frame.height
        guard width > 0 && height > 0 else {
            return
        }
        if frame.intersection(background.frame).isNull {
            return
        }
        background.drawView(frame: background.frame, context: context)
    }
}
