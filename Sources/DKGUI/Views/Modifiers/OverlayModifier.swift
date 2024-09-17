//
//  File: OverlayModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _OverlayModifier<Overlay>: ViewModifier where Overlay: View {
    public let overlay: Overlay
    public let alignment: Alignment

    @inlinable public init(overlay: Overlay, alignment: Alignment = .center) {
        self.overlay = overlay
        self.alignment = alignment
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let content = outputs.view {
            var overlayInputs = inputs
            overlayInputs.base.properties.replace(item: DefaultLayoutPropertyItem(layout: ZStackLayout()))
            if let overlay = makeView(view: modifier[\.overlay], inputs: overlayInputs).view {
                let generator = OverlayViewContext.Generator(content: content, overlay: overlay, graph: modifier, baseInputs: inputs.base)
                return _ViewOutputs(view: generator)
            }
        }
        return outputs
    }

    public typealias Body = Never
}

extension _OverlayModifier: Equatable where Overlay: Equatable {
}

extension _OverlayModifier: _UnaryViewModifier {
}

public struct _OverlayStyleModifier<Style>: ViewModifier where Style: ShapeStyle {
    public var style: Style
    public var ignoresSafeAreaEdges: Edge.Set

    @inlinable public init(style: Style, ignoresSafeAreaEdges: Edge.Set) {
        self.style = style
        self.ignoresSafeAreaEdges = ignoresSafeAreaEdges
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let content = outputs.view, let overlay = makeView(view: modifier[\._shapeView], inputs: inputs).view {
            let generator = OverlayViewContext.Generator(content: content, overlay: overlay, graph: modifier, baseInputs: inputs.base)
            return _ViewOutputs(view: generator)
        }
        return outputs
    }

    public typealias Body = Never

    var _shapeView : some View {
        _ShapeView(shape: Rectangle(), style: self.style)
    }
}

extension _OverlayStyleModifier: _UnaryViewModifier {
}

public struct _OverlayShapeModifier<Style, Bounds>: ViewModifier where Style: ShapeStyle, Bounds: Shape {
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
        if let content = outputs.view, let overlay = makeView(view: modifier[\._shapeView], inputs: inputs).view {
            let generator = OverlayViewContext.Generator(content: content, overlay: overlay, graph: modifier, baseInputs: inputs.base)
            return _ViewOutputs(view: generator)
        }
        return outputs
    }

    public typealias Body = Never

    var _shapeView : some View {
        _ShapeView(shape: self.shape, style: self.style, fillStyle: self.fillStyle)
    }
}

extension _OverlayShapeModifier: _UnaryViewModifier {
}

extension View {
    @inlinable public func overlay<V>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View where V: View {
          modifier(_OverlayModifier(overlay: content(), alignment: alignment))
      }

    @inlinable public func overlay<S>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View where S: ShapeStyle {
          modifier(_OverlayStyleModifier(
              style: style, ignoresSafeAreaEdges: edges))
      }

    @inlinable public func overlay<S, T>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View where S: ShapeStyle, T: Shape {
          modifier(_OverlayShapeModifier(
              style: style, shape: shape, fillStyle: fillStyle))
      }

    @inlinable public func border<S>(_ content: S, width: CGFloat = 1) -> some View where S: ShapeStyle {
        return overlay {
            Rectangle().strokeBorder(content, lineWidth: width)
        }
    }
}


private protocol _OverlayModifierWithAlignment {
    var alignment: Alignment { get }
}

private protocol _OverlayModifierWithIgnoresSafeAreaEdges {
    var ignoresSafeAreaEdges: Edge.Set { get }
}

extension _OverlayModifier : _OverlayModifierWithAlignment {
}

extension _OverlayStyleModifier : _OverlayModifierWithIgnoresSafeAreaEdges {
}

private class OverlayViewContext<Modifier> : ViewModifierContext<Modifier> {
    let overlay: ViewContext
    let alignment: Alignment
    let ignoresSafeAreaEdges: Edge.Set

    struct Generator : ViewGenerator {
        var content: any ViewGenerator
        var overlay: any ViewGenerator
        let graph: _GraphValue<Modifier>
        var baseInputs: _GraphInputs

        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let content = content.makeView(encloser: encloser, graph: graph) {
                if let modifier = graph.value(atPath: self.graph, from: encloser) {
                    if let overlay = overlay.makeView(encloser: modifier, graph: self.graph) {
                        return OverlayViewContext(content: content,
                                                  overlay: overlay,
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
            overlay.mergeInputs(inputs)
            baseInputs.mergedInputs.append(inputs)
        }
    }

    init(content: ViewContext, overlay: ViewContext, modifier: Modifier, inputs: _GraphInputs, graph: _GraphValue<Modifier> ) {
        self.overlay = overlay
        if let alignmentModifier = modifier as? _OverlayModifierWithAlignment {
            self.alignment = alignmentModifier.alignment
        } else {
            self.alignment = .center
        }
        if let ignoresSafeAreaEdgesModifier = modifier as? _OverlayModifierWithIgnoresSafeAreaEdges {
            self.ignoresSafeAreaEdges = ignoresSafeAreaEdgesModifier.ignoresSafeAreaEdges
        } else {
            self.ignoresSafeAreaEdges = .all
        }
        super.init(content: content, modifier: modifier, inputs: inputs, graph: graph)
        self._debugDraw = false
        self.overlay._debugDraw = false
    }

    override func loadResources(_ context: GraphicsContext) {
        super.loadResources(context)
        self.overlay.loadResources(context)
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
        overlay.place(at: position,
                           anchor: anchor,
                           proposal: proposal)
    }

    override func drawOverlay(frame: CGRect, context: GraphicsContext) {
        let width = overlay.frame.width
        let height = overlay.frame.height
        guard width > 0 && height > 0 else {
            return
        }
        if frame.intersection(overlay.frame).isNull {
            return
        }
        overlay.drawView(frame: overlay.frame, context: context)
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        if let view = self.overlay.hitTest(location) {
            return view
        }
        return super.hitTest(location)
    }
}
