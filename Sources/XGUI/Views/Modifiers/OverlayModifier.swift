//
//  File: OverlayModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
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
        if let body = outputs.view {
            var overlayInputs = inputs
            overlayInputs.base.properties.setValue(ZStackLayout(), forKey: DefaultLayoutProperty.self)
            if let overlay = makeView(view: modifier[\.overlay], inputs: overlayInputs).view {
                let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                    OverlayViewContext(overlay: overlay.makeView(),
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
        if let body = outputs.view {
            if let overlay = makeView(view: modifier[\._shapeView], inputs: inputs).view {
                let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                    OverlayViewContext(overlay: overlay.makeView(),
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
        if let body = outputs.view {
            if let overlay = makeView(view: modifier[\._shapeView], inputs: inputs).view {
                let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                    OverlayViewContext(overlay: overlay.makeView(),
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

extension _OverlayModifier: _OverlayModifierWithAlignment {
}

extension _OverlayStyleModifier: _OverlayModifierWithIgnoresSafeAreaEdges {
}

private class OverlayViewContext<Modifier>: ViewModifierContext<Modifier> where Modifier: ViewModifier {
    let overlay: ViewContext

    init(overlay: ViewContext, graph: _GraphValue<Modifier>, body: ViewContext, inputs: _GraphInputs) {
        self.overlay = overlay
        defer { self.overlay.superview = self }

        super.init(graph: graph, body: body, inputs: inputs)
    }

    deinit {
        self.overlay.superview = nil
    }

    override func updateContent() {
        super.updateContent()
        if self.view != nil {
            overlay.updateContent()
        }
    }

    override var isValid: Bool {
        if super.isValid {
            return overlay.isValid
        }
        return false
    }

    override func validate() -> Bool {
        super.validate() && overlay.validate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let modifier else { fatalError("Invalid view modifier") }

        let alignment: Alignment
        if let alignmentModifier = modifier as? _OverlayModifierWithAlignment {
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
        overlay.place(at: position,
                      anchor: anchor,
                      proposal: proposal)
    }

    override func drawOverlay(frame: CGRect, context: GraphicsContext) {
        let width = overlay.frame.width
        let height = overlay.frame.height
        guard width > .ulpOfOne && height > .ulpOfOne else {
            return
        }

        let drawingFrame = overlay.frame.offsetBy(dx: frame.minX,
                                                  dy: frame.minY)
        if frame.intersection(drawingFrame).isNull {
            return
        }
        overlay.drawView(frame: drawingFrame, context: context)
    }
    
    override func hitTest(_ location: CGPoint) -> ViewContext? {
        let local = location.applying(overlay.transformToContainer.inverted())
        if let result = overlay.hitTest(local) {
            return result
        }
        return super.hitTest(location)
    }
}
