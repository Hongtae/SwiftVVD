//
//  File: OverlayModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
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
        fatalError()
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
        fatalError()
    }
    public typealias Body = Never
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
        fatalError()
    }
    public typealias Body = Never
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

fileprivate struct ViewContextLayer: ViewLayer {
    private let view: ViewContext
    private let alignment: Alignment
    private let ignoresSafeAreaEdges: Edge.Set
    
    init<V>(view: V, inputs: _ViewInputs, alignment: Alignment, ignoresSafeAreaEdges: Edge.Set) where V: View {
        fatalError()
        
        self.alignment = alignment
        self.ignoresSafeAreaEdges = ignoresSafeAreaEdges
    }
    func loadResources(_ context: GraphicsContext) {
        self.view.loadResources(context)
    }
    func layout(frame: CGRect) {
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
        self.view.place(at: position,
                        anchor: anchor,
                        proposal: proposal)
    }
    func draw(frame: CGRect, context: GraphicsContext) {
        let width = view.frame.width
        let height = view.frame.height
        guard width > 0 && height > 0 else {
            return
        }
        if frame.intersection(view.frame).isNull {
            return
        }
        var context = context
        context.environment = self.view.environmentValues
        self.view.draw(frame: view.frame, context: context)
    }
}

