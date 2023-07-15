//
//  File: BackgroundModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
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
        fatalError()
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
        fatalError()
    }
    public typealias Body = Never
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
        fatalError()
    }
    public typealias Body = Never
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
        fatalError()
    }
    public typealias Body = Never
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
