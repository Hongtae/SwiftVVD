//
//  File: ShapeView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct AnimatedShape<Content: Shape>: LeafViewLayout {
    var shape: Content
    var fillStyle: FillStyle

    struct Init: Rule {
        typealias Value = AnimatedShape<Content>

        var shape: Attribute<Content>
        var fillStyle: Attribute<FillStyle>

        func updateValue() -> Value {
            AnimatedShape(shape: shape.value, fillStyle: fillStyle.value)
        }
    }

    func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
        shape.sizeThatFits(proposal)
    }
}

public struct _ShapeView<Content, Style>: View where Content: Shape, Style: ShapeStyle {
    public var shape: Content
    public var style: Style
    public var fillStyle: FillStyle

    public init(shape: Content, style: Style, fillStyle: FillStyle = FillStyle()) {
        self.shape = shape
        self.style = style
        self.fillStyle = fillStyle
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
        let sizeAttr = inputs.size
        let positionAttr = inputs.position
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let v = view._attribute.value   // dep: style/fillStyle changes
            let shape = animatedShape._attribute.value
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            var list = DisplayList()
            //Log.debug("ShapeView: size=\(viewSize), position=\(position)")
            if viewSize.width > 0 && viewSize.height > 0 {
                let frame = CGRect(origin: position, size: viewSize)
                let strokeStyle = (shape as? ShapeStrokeStyleProviding)?.strokeStyle
                if let animatedColorStyle {
                    let style = animatedColorStyle.value
                    list.appendShapeItem(
                        role: Content.role,
                        style: style,
                        bounds: frame,
                        fillStyle: v.fillStyle,
                        strokeStyle: strokeStyle
                    ) { context in
                        if let drawer = shape as? ShapeDrawer {
                            drawer._draw(in: frame, style: style, fillStyle: v.fillStyle, context: context)
                        } else {
                            let path = shape.path(in: frame)
                            context.fill(path, with: .style(style), style: v.fillStyle)
                        }
                    }
                } else {
                    list.appendShapeItem(
                        role: Content.role,
                        style: v.style,
                        bounds: frame,
                        fillStyle: v.fillStyle,
                        strokeStyle: strokeStyle
                    ) { context in
                        if let drawer = shape as? ShapeDrawer {
                            drawer._draw(in: frame, style: v.style, fillStyle: v.fillStyle, context: context)
                        } else {
                            let path = shape.path(in: frame)
                            context.fill(path, with: .style(v.style), style: v.fillStyle)
                        }
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

extension _ShapeView: PrimitiveView, UnaryView, LeafViewLayout {
    func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
        shape.sizeThatFits(proposal)
    }
}
