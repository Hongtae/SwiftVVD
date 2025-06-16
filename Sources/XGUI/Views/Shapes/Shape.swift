//
//  File: Shape.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public enum ShapeRole: Equatable, Hashable {
    case fill
    case stroke
    case separator
}

public protocol Shape: Animatable, View {
    func path(in rect: CGRect) -> Path
    static var role: ShapeRole { get }
    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize
}

extension Shape {
    public static var role: ShapeRole { .fill }
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let size = proposal.replacingUnspecifiedDimensions()
        if size.width == .infinity || size.height == .infinity {
            return size
        }
        let path = self.path(in: CGRect(origin: .zero, size: size))
        return path.boundingRect.standardized.size
    }
}

extension Shape {
    @inlinable public func fill<S>(_ content: S, style: FillStyle = FillStyle()) -> some View where S: ShapeStyle {
        return _ShapeView(shape: self, style: content, fillStyle: style)
    }

    @inlinable public func fill(style: FillStyle = FillStyle()) -> some View {
        return _ShapeView(shape: self, style: .foreground, fillStyle: style)
    }

    @inlinable public func stroke<S>(_ content: S, style: StrokeStyle) -> some View where S: ShapeStyle {
        return stroke(style: style).fill(content)
    }

    @inlinable public func stroke<S>(_ content: S, lineWidth: CGFloat = 1) -> some View where S: ShapeStyle {
        return stroke(content, style: StrokeStyle(lineWidth: lineWidth))
    }
}

extension Shape {
    public var body: _ShapeView<Self, ForegroundStyle> {
        .init(shape: self, style: ForegroundStyle())
    }
}

extension Shape {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Body._makeView(view: view[\.body], inputs: inputs)
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError()
    }
}
