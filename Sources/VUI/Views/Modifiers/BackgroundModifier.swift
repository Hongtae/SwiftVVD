//
//  File: BackgroundModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _BackgroundModifier<Background>: MultiViewModifier, PrimitiveViewModifier where Background: View {
    public var background: Background
    public var alignment: Alignment

    @inlinable public init(background: Background, alignment: Alignment = .center) {
        self.background = background
        self.alignment = alignment
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        return makeSecondaryLayerView(
            secondaryLayer: modifier[\.background]._attribute,
            alignment: modifier[\.alignment]._attribute,
            inputs: inputs,
            body: body,
            flipOrder: true
        )
    }
}

@available(*, unavailable)
extension _BackgroundModifier: Sendable {
    public typealias Body = Never
}

public struct _BackgroundStyleModifier<Style>: MultiViewModifier, PrimitiveViewModifier, ContentResponder
    where Style: ShapeStyle {
    public var style: Style
    public var ignoresSafeAreaEdges: Edge.Set

    @inlinable public init(style: Style, ignoresSafeAreaEdges: Edge.Set) {
        self.style = style
        self.ignoresSafeAreaEdges = ignoresSafeAreaEdges
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let mainOutputs = body(_Graph(), inputs)
        let sizeAttr = inputs.size
        let positionAttr = inputs.position
        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let m = modifier._attribute.value
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            let environment = environmentAttr.value.untrackedCopy()
            var list = DisplayList()
            if viewSize.width > 0 && viewSize.height > 0 {
                let frame = CGRect(origin: position, size: viewSize)
                let path = Rectangle().path(in: frame)
                list.appendShapeItem(
                    path: path,
                    role: .fill,
                    style: m.style,
                    bounds: frame,
                    fillStyle: FillStyle(),
                    environment: environment
                )
            }
            return list
        }
        var bgPreferences = PreferencesOutputs()
        bgPreferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        let mergedPreferences = PreferencesOutputs.merge([bgPreferences, mainOutputs.preferences], in: graph)
        return _ViewOutputs(
            preferences: mergedPreferences,
            layoutComputer: mainOutputs._layoutComputer
        )
    }

    func contentPath(size: CGSize) -> Path {
        Rectangle().path(in: CGRect(origin: .zero, size: size))
    }
}

@available(*, unavailable)
extension _BackgroundStyleModifier: Sendable {
    public typealias Body = Never
}

public struct _BackgroundShapeModifier<Style, Bounds>: MultiViewModifier, PrimitiveViewModifier, ContentResponder
    where Style: ShapeStyle, Bounds: Shape {
    public var style: Style
    public var shape: Bounds
    public var fillStyle: FillStyle

    @inlinable public init(style: Style, shape: Bounds, fillStyle: FillStyle) {
        self.style = style
        self.shape = shape
        self.fillStyle = fillStyle
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let mainOutputs = body(_Graph(), inputs)
        let sizeAttr = inputs.size
        let positionAttr = inputs.position
        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let m = modifier._attribute.value
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            let environment = environmentAttr.value.untrackedCopy()
            var list = DisplayList()
            if viewSize.width > 0 && viewSize.height > 0 {
                let frame = CGRect(origin: position, size: viewSize)
                let path = m.shape.path(in: frame)
                list.appendShapeItem(
                    path: path,
                    role: .fill,
                    style: m.style,
                    bounds: frame,
                    fillStyle: m.fillStyle,
                    environment: environment
                )
            }
            return list
        }
        var bgPreferences = PreferencesOutputs()
        bgPreferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        let mergedPreferences = PreferencesOutputs.merge([bgPreferences, mainOutputs.preferences], in: graph)
        return _ViewOutputs(
            preferences: mergedPreferences,
            layoutComputer: mainOutputs._layoutComputer
        )
    }

    func contentPath(size: CGSize) -> Path {
        shape.path(in: CGRect(origin: .zero, size: size))
    }
}

@available(*, unavailable)
extension _BackgroundShapeModifier: Sendable {
    public typealias Body = Never
}

public struct _InsettableBackgroundShapeModifier<Style, Bounds>: MultiViewModifier, PrimitiveViewModifier where Style: ShapeStyle, Bounds: InsettableShape {
    public var style: Style
    public var shape: Bounds
    public var fillStyle: FillStyle

    @inlinable public init(style: Style, shape: Bounds, fillStyle: FillStyle) {
        self.style = style
        self.shape = shape
        self.fillStyle = fillStyle
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let mainOutputs = body(_Graph(), inputs)
        let sizeAttr = inputs.size
        let positionAttr = inputs.position
        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let m = modifier._attribute.value
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            let environment = environmentAttr.value.untrackedCopy()
            var list = DisplayList()
            if viewSize.width > 0 && viewSize.height > 0 {
                let frame = CGRect(origin: position, size: viewSize)
                let path = m.shape.path(in: frame)
                list.appendShapeItem(
                    path: path,
                    role: .fill,
                    style: m.style,
                    bounds: frame,
                    fillStyle: m.fillStyle,
                    environment: environment
                )
            }
            return list
        }
        var bgPreferences = PreferencesOutputs()
        bgPreferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        let mergedPreferences = PreferencesOutputs.merge([bgPreferences, mainOutputs.preferences], in: graph)
        return _ViewOutputs(
            preferences: mergedPreferences,
            layoutComputer: mainOutputs._layoutComputer
        )
    }
}

@available(*, unavailable)
extension _InsettableBackgroundShapeModifier: Sendable {
    public typealias Body = Never
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
