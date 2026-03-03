//
//  File: OverlayModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
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
        fatalError("Implement with AG")
    }
}

extension _OverlayModifier: Equatable where Overlay: Equatable {
}

extension _OverlayModifier: _UnaryViewModifier {
    public typealias Body = Never
}

public struct _OverlayStyleModifier<Style>: ViewModifier where Style: ShapeStyle {
    public var style: Style
    public var ignoresSafeAreaEdges: Edge.Set

    @inlinable public init(style: Style, ignoresSafeAreaEdges: Edge.Set) {
        self.style = style
        self.ignoresSafeAreaEdges = ignoresSafeAreaEdges
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }
}

extension _OverlayStyleModifier: _UnaryViewModifier {
    public typealias Body = Never
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
        fatalError("Implement with AG")
    }
}

extension _OverlayShapeModifier: _UnaryViewModifier {
    public typealias Body = Never
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

