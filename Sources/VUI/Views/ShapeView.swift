//
//  File: ShapeView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol ShapeView<Content>: View {
    associatedtype Content: Shape
    var shape: Content { get }
}

struct AnimatedShape<Content: Shape>: LeafViewLayout {
    var shape: Content
    var fillStyle: FillStyle

    struct Init: Rule, AsyncAttribute {
        typealias Value = AnimatedShape<Content>

        var shape: Attribute<Content>
        var fillStyle: Attribute<FillStyle>

        var value: Value {
            AnimatedShape(shape: shape.value, fillStyle: fillStyle.value)
        }
    }

    func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
        shape.sizeThatFits(ProposedViewSize(proposal))
    }
}

public struct _ShapeView<Content, Style>: View, ShapeView, ContentResponder
    where Content: Shape, Style: ShapeStyle {
    public var shape: Content
    public var style: Style
    public var fillStyle: FillStyle

    public init(shape: Content, style: Style, fillStyle: FillStyle = FillStyle()) {
        self.shape = shape
        self.style = style
        self.fillStyle = fillStyle
    }

    func contentPath(size: CGSize) -> Path {
        shape.path(in: CGRect(origin: .zero, size: size))
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let sourceShape = view[\.shape]
        var animatedShape = sourceShape
        Content._makeAnimatable(value: &animatedShape, inputs: inputs.base)
        let animatedColorStyle = Self.makeAnimatedColorStyle(
            view: view,
            inputs: inputs,
            graph: graph
        )
        let cachedEnvironmentAttribute = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value
        let sizeAttr = cachedEnvironment.animatedSize(for: inputs)
        let positionAttr = cachedEnvironment.animatedPosition(for: inputs)
        cachedEnvironmentAttribute.value = cachedEnvironment
        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let v = view._attribute.value   // dep: style/fillStyle changes
            let shape = animatedShape._attribute.value
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            let environment = environmentAttr.value.untrackedCopy()
            var list = DisplayList()
            //Log.debug("ShapeView: size=\(viewSize), position=\(position)")
            if viewSize.width > 0 && viewSize.height > 0 {
                let frame = CGRect(origin: position, size: viewSize)
                let strokeStyle = (shape as? ShapeStrokeStyleProviding)?.strokeStyle
                if let animatedColorStyle {
                    let style = animatedColorStyle.value
                    if let drawer = shape as? ShapeDrawer {
                        list.appendShapeItem(
                            role: Content.role,
                            style: style,
                            bounds: frame,
                            fillStyle: v.fillStyle,
                            strokeStyle: strokeStyle,
                            environment: environment
                        ) { context in
                            drawer._draw(in: frame, style: style, fillStyle: v.fillStyle, context: context)
                        }
                    } else {
                        list.appendShapeItem(
                            path: shape.path(in: frame),
                            role: Content.role,
                            style: style,
                            bounds: frame,
                            fillStyle: v.fillStyle,
                            strokeStyle: strokeStyle,
                            environment: environment
                        )
                    }
                } else {
                    if let drawer = shape as? ShapeDrawer {
                        list.appendShapeItem(
                            role: Content.role,
                            style: v.style,
                            bounds: frame,
                            fillStyle: v.fillStyle,
                            strokeStyle: strokeStyle,
                            environment: environment
                        ) { context in
                            drawer._draw(in: frame, style: v.style, fillStyle: v.fillStyle, context: context)
                        }
                    } else {
                        list.appendShapeItem(
                            path: shape.path(in: frame),
                            role: Content.role,
                            style: v.style,
                            bounds: frame,
                            fillStyle: v.fillStyle,
                            strokeStyle: strokeStyle,
                            environment: environment
                        )
                    }
                }
            }
            return list
        }
        var outputs = _ViewOutputs()
        if MemoryLayout<Content.AnimatableData>.size == 0 {
            makeLeafLayout(&outputs, view: view, inputs: inputs)
        } else {
            let layoutShape: Attribute<AnimatedShape<Content>> = graph.makeRule(
                AnimatedShape.Init(
                    shape: animatedShape._attribute,
                    fillStyle: view[\.fillStyle]._attribute
                )
            )
            AnimatedShape<Content>.makeLeafLayout(
                &outputs,
                view: _GraphValue(_attribute: layoutShape),
                inputs: inputs
            )
        }
        outputs.preferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        return outputs
    }

    private static func makeAnimatedColorStyle(
        view: _GraphValue<Self>,
        inputs: _ViewInputs,
        graph: _AGGraph
    ) -> Attribute<Color.Resolved>? {
        guard Style.self == Color.self else {
            return nil
        }

        let environment = inputs.base.cachedEnvironment.value.environment
        let resolvedStyle: Attribute<Color.Resolved> = graph.makeRule {
            guard let color = view._attribute.value.style as? Color else {
                return Color.clear.resolve(in: environment.value)
            }
            return color.resolve(in: environment.value)
        }
        var animatedStyle = _GraphValue(_attribute: resolvedStyle)
        Color.Resolved._makeAnimatable(value: &animatedStyle, inputs: inputs.base)
        return animatedStyle._attribute
    }

    public typealias Body = Never
}

extension _ShapeView: LeafViewLayout {
    func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
        shape.sizeThatFits(ProposedViewSize(proposal))
    }
}

@available(*, unavailable)
extension _ShapeView: Sendable {
}

extension _ShapeView: PrimitiveView, UnaryView {
}
