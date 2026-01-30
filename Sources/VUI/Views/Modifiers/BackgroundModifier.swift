//
//  File: BackgroundModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
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
        if let body = outputs.view {
            var backgroundInputs = inputs
            backgroundInputs.base.properties.setValue(ZStackLayout(), forKey: DefaultLayoutProperty.self)
            if let background = makeView(view: modifier[\.background], inputs: backgroundInputs).view {
                let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                    BackgroundViewContext(background: background.makeView(),
                                          graph: graph,
                                          body: body.makeView(),
                                          inputs: inputs)
                }
                return _ViewOutputs(view: view)
            }
        }
        return outputs
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
        if let body = outputs.view {
            if let background = makeView(view: modifier[\._shapeView], inputs: inputs).view {
                let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                    BackgroundViewContext(background: background.makeView(),
                                          graph: graph,
                                          body: body.makeView(),
                                          inputs: inputs)
                }
                return _ViewOutputs(view: view)
            }
        }
        return outputs
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
        if let body = outputs.view {
            if let background = makeView(view: modifier[\._shapeView], inputs: inputs).view {
                let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                    BackgroundViewContext(background: background.makeView(),
                                          graph: graph,
                                          body: body.makeView(),
                                          inputs: inputs)
                }
                return _ViewOutputs(view: view)
            }
        }
        return outputs
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
        if let body = outputs.view {
            if let background = makeView(view: modifier[\._shapeView], inputs: inputs).view {
                let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                    BackgroundViewContext(background: background.makeView(),
                                          graph: graph,
                                          body: body.makeView(),
                                          inputs: inputs)
                }
                return _ViewOutputs(view: view)
            }
        }
        return outputs
    }

    public typealias Body = Never

    var _shapeView: some View {
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

extension _BackgroundModifier: _BackgroundModifierWithAlignment {
}

extension _BackgroundStyleModifier: _BackgroundModifierWithIgnoresSafeAreaEdges {
}

private class BackgroundViewContext<Modifier>: ViewModifierContext<Modifier> where Modifier: ViewModifier {
    let background: ViewContext

    init(background: ViewContext, graph: _GraphValue<Modifier>, body: ViewContext, inputs: _GraphInputs) {
        self.background = background
        defer { self.background.superview = self }

        super.init(graph: graph, body: body, inputs: inputs)
    }

    deinit {
        self.background.superview = nil
    }

    override func updateContent() {
        super.updateContent()
        if self.view != nil {
            background.updateContent()
        }
    }

    override func validate() -> Bool {
        if super.validate() {
            background.validate()
            return true
        }
        return false
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let modifier else { fatalError("Invalid view modifier") }

        let alignment: Alignment
        if let alignmentModifier = modifier as? _BackgroundModifierWithAlignment {
            alignment = alignmentModifier.alignment
        } else {
            alignment = .center
        }

        let frame = self.bounds
        var position = frame.origin
        var anchor = UnitPoint()
        switch alignment.horizontal {
        case .leading:
            position.x = frame.minX
            anchor.x = 0
        case .center:
            position.x = frame.midX
            anchor.x = 0.5
        case .trailing:
            position.x = frame.maxX
            anchor.x = 1
        default:
            position.x = frame.midX
            anchor.x = 0.5
        }
        switch alignment.vertical {
        case .top:
            position.y = frame.minY
            anchor.y = 0
        case .center:
            position.y = frame.midY
            anchor.y = 0.5
        case .bottom:
            position.y = frame.maxY
            anchor.y = 1
        default:
            position.y = frame.midY
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
        guard width > .ulpOfOne && height > .ulpOfOne else {
            return
        }

        let drawingFrame = background.frame.offsetBy(dx: frame.minX,
                                                     dy: frame.minY)
        if frame.intersection(drawingFrame).isNull {
            return
        }
        background.drawView(frame: drawingFrame, context: context)
    }
    
    override func hitTest(_ location: CGPoint) -> ViewContext? {
        if let result = super.hitTest(location) {
            return result
        }
        let local = location.applying(background.transformToContainer.inverted())
        return background.hitTest(local)
    }
}
