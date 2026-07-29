//
//  File: StrokedShape.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _StrokedShape<S>: Shape where S: Shape {
    public var shape: S
    public var style: StrokeStyle

    public init(shape: S, style: StrokeStyle) {
        self.shape = shape
        self.style = style
    }

    public func path(in rect: CGRect) -> Path {
        shape.path(in: rect)
    }

    public static var role: ShapeRole { .stroke }

    public typealias AnimatableData = AnimatablePair<S.AnimatableData, StrokeStyle.AnimatableData>
    public typealias Body = _ShapeView<Self, ForegroundStyle>

    public var animatableData: AnimatableData {
        get {
            AnimatableData(shape.animatableData, style.animatableData)
        }
        set {
            shape.animatableData = newValue.first
            style.animatableData = newValue.second
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        shape.sizeThatFits(proposal)
    }

    public var body: Body {
        _ShapeView(shape: self, style: ForegroundStyle())
    }
}

protocol ShapeStrokeStyleProviding {
    var strokeStyle: StrokeStyle { get }
}

extension _StrokedShape: ShapeStrokeStyleProviding {
    var strokeStyle: StrokeStyle { style }
}

protocol ShapeDrawer {
    func _draw(in frame: CGRect, style: any ShapeStyle, fillStyle: FillStyle, context: GraphicsContext)
}

extension _StrokedShape: ShapeDrawer {
    func _draw(in frame: CGRect, style: any ShapeStyle, fillStyle: FillStyle, context: GraphicsContext) {
        if let drawer = self.shape as? ShapeDrawer {
            drawer._draw(in: frame, style: style, fillStyle: fillStyle, context: context)
        }
        context.stroke(self.path(in: frame), with: .style(style), style: self.style)
    }
}

extension Shape {
    @inlinable public func stroke(style: StrokeStyle) -> some Shape {
        return _StrokedShape(shape: self, style: style)
    }

    @inlinable public func stroke(lineWidth: CGFloat = 1) -> some Shape {
        return stroke(style: StrokeStyle(lineWidth: lineWidth))
    }
}
