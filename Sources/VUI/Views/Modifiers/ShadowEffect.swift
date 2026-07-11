//
//  File: ShadowEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private enum _ShadowEffectSupport {
    static func makeView<Modifier>(
        modifier: _GraphValue<Modifier>,
        style: _GraphValue<ResolvedShadowStyle>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs where Modifier: ViewModifier {
        guard let graph = _AGGraph.current else {
            fatalError("\(Modifier.self)._makeView called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        applyShadow(
            to: &outputs.preferences,
            style: style,
            graph: graph
        )
        return outputs
    }

    static func makeViewList<Modifier>(
        modifier: _GraphValue<Modifier>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs where Modifier: ViewModifier {
        guard _AGGraph.current != nil else {
            fatalError("\(Modifier.self)._makeViewList called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }

    private static func applyShadow(
        to preferences: inout PreferencesOutputs,
        style: _GraphValue<ResolvedShadowStyle>,
        graph: _AGGraph
    ) {
        let displayNodes = preferences.values(for: DisplayList.Key.self)
        guard !displayNodes.isEmpty else { return }

        let weakNodes = displayNodes.compactMap { graph.weakAttributeIfValid(for: $0) }
        let styleAttr = style._attribute
        let transformedAttr: Attribute<DisplayList> = graph.makeRule {
            var combined = DisplayList.Key.defaultValue
            for weakNode in weakNodes where weakNode.isValid(in: graph) {
                let list = Attribute<DisplayList>(weakNode.toStrong()).value
                DisplayList.Key.reduce(value: &combined) { list }
            }
            return displayList(
                combined,
                applying: styleAttr.value
            )
        }

        let displayKeyID = ObjectIdentifier(DisplayList.Key.self)
        preferences.preferences.removeAll {
            ObjectIdentifier($0.key) == displayKeyID
        }
        preferences.append(DisplayList.Key.self, node: transformedAttr.identifier)
    }

    private static func displayList(
        _ source: DisplayList,
        applying style: ResolvedShadowStyle
    ) -> DisplayList {
        guard style.color.opacity > 0 else { return source }

        var result = DisplayList()
        result.debugItems.append(contentsOf: source.debugItems)
        result.recordInterpolationBounds(source.interpolationBounds)
        for effect in source.effects {
            result.appendEffect(
                effect.effect,
                contents: displayList(
                    effect.contents,
                    applying: style
                )
            )
        }

        guard !source.renderItems.isEmpty else { return result }

        let items = source.renderItems
        result.appendShadowItem(
            bounds: source.interpolationBounds,
            color: style.color.base,
            radius: style.radius,
            offset: style.offset
        ) { context in
            context.drawLayer { layerContext in
                layerContext.addFilter(
                    .shadow(
                        color: Color(style.color),
                        radius: style.radius,
                        x: style.offset.width,
                        y: style.offset.height
                    )
                )
                for item in items {
                    item(layerContext)
                }
            }
        }
        return result
    }
}

public struct _ShadowEffect: EnvironmentalModifier, Equatable {
    public var color: Color
    public var radius: CGFloat
    public var offset: CGSize

    @inlinable public init(color: Color, radius: CGFloat, offset: CGSize) {
        self.color = color
        self.radius = radius
        self.offset = offset
    }

    public func resolve(in environment: EnvironmentValues) -> _Resolved {
        _Resolved(
            style: ResolvedShadowStyle(
                color: Color.ResolvedHDR(color.resolve(in: environment)),
                radius: radius,
                offset: offset
            )
        )
    }

    public struct _Resolved: ViewModifier, Animatable {
        var style: ResolvedShadowStyle

        init(style: ResolvedShadowStyle) {
            self.style = style
        }

        public typealias AnimatableData = AnimatablePair<
            Color.Resolved.AnimatableData,
            AnimatablePair<CGFloat, CGSize.AnimatableData>
        >

        public var animatableData: AnimatableData {
            get { style.animatableData }
            set { style.animatableData = newValue }
        }

        public typealias Body = Never

        public static func _makeView(
            modifier: _GraphValue<Self>,
            inputs: _ViewInputs,
            body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
        ) -> _ViewOutputs {
            var modifier = modifier
            Self._makeAnimatable(value: &modifier, inputs: inputs.base)
            return _ShadowEffectSupport.makeView(
                modifier: modifier,
                style: modifier[\.style],
                inputs: inputs,
                body: body
            )
        }

        public static func _makeViewList(
            modifier: _GraphValue<Self>,
            inputs: _ViewListInputs,
            body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
        ) -> _ViewListOutputs {
            _ShadowEffectSupport.makeViewList(
                modifier: modifier,
                inputs: inputs,
                body: body
            )
        }
    }
}

extension _ShadowEffect._Resolved {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.style == rhs.style
    }
}

extension View {
    @inlinable public func shadow(
        color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33),
        radius: CGFloat,
        x: CGFloat = 0,
        y: CGFloat = 0
    ) -> some View {
        modifier(
            _ShadowEffect(
                color: color,
                radius: radius,
                offset: CGSize(width: x, height: y)
            )
        )
    }
}
