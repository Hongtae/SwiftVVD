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
        color: _GraphValue<Color.Resolved>,
        radius: _GraphValue<CGFloat>,
        offset: _GraphValue<CGSize>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs where Modifier: ViewModifier {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Modifier.self)._makeView called outside an active AttributeGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        applyShadow(
            to: &outputs.preferences,
            color: color,
            radius: radius,
            offset: offset,
            graph: graph
        )
        return outputs
    }

    static func makeViewList<Modifier>(
        modifier: _GraphValue<Modifier>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs where Modifier: ViewModifier {
        guard AttributeGraph.current != nil else {
            fatalError("\(Modifier.self)._makeViewList called outside an active AttributeGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }

    private static func applyShadow(
        to preferences: inout PreferencesOutputs,
        color: _GraphValue<Color.Resolved>,
        radius: _GraphValue<CGFloat>,
        offset: _GraphValue<CGSize>,
        graph: AttributeGraph
    ) {
        let displayNodes = preferences.values(for: DisplayList.Key.self)
        guard !displayNodes.isEmpty else { return }

        let weakNodes = displayNodes.compactMap { graph.weakAttributeIfValid(for: $0) }
        let colorAttr = color._attribute
        let radiusAttr = radius._attribute
        let offsetAttr = offset._attribute
        let transformedAttr: Attribute<DisplayList> = graph.makeRule {
            var combined = DisplayList.Key.defaultValue
            for weakNode in weakNodes where weakNode.isValid(in: graph) {
                let list = Attribute<DisplayList>(weakNode.toStrong()).value
                DisplayList.Key.reduce(value: &combined) { list }
            }
            return displayList(
                combined,
                applyingShadowColor: colorAttr.value,
                radius: radiusAttr.value,
                offset: offsetAttr.value
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
        applyingShadowColor color: Color.Resolved,
        radius: CGFloat,
        offset: CGSize
    ) -> DisplayList {
        guard color.opacity > 0 else { return source }

        var result = DisplayList()
        result.debugItems.append(contentsOf: source.debugItems)
        result.recordInterpolationBounds(source.interpolationBounds)
        for effect in source.effects {
            result.appendEffect(
                effect.effect,
                contents: displayList(
                    effect.contents,
                    applyingShadowColor: color,
                    radius: radius,
                    offset: offset
                )
            )
        }

        guard !source.items.isEmpty else { return result }

        let items = source.items
        result.appendShadowItem(
            bounds: source.interpolationBounds,
            color: color,
            radius: radius,
            offset: offset
        ) { context in
            context.drawLayer { layerContext in
                layerContext.addFilter(
                    .shadow(
                        color: Color(color),
                        radius: radius,
                        x: offset.width,
                        y: offset.height
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
            color: color.resolve(in: environment),
            radius: radius,
            offset: offset
        )
    }

    public struct _Resolved: ViewModifier, Animatable {
        public var color: Color.Resolved
        public var radius: CGFloat
        public var offset: CGSize

        init(color: Color.Resolved, radius: CGFloat, offset: CGSize) {
            self.color = color
            self.radius = radius
            self.offset = offset
        }

        public typealias AnimatableData = AnimatablePair<
            Color.Resolved.AnimatableData,
            AnimatablePair<CGFloat, CGSize.AnimatableData>
        >

        public var animatableData: AnimatableData {
            get {
                AnimatableData(
                    color.animatableData,
                    AnimatablePair(radius, offset.animatableData)
                )
            }
            set {
                color.animatableData = newValue.first
                radius = newValue.second.first
                offset.animatableData = newValue.second.second
            }
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
                color: modifier[\.color],
                radius: modifier[\.radius],
                offset: modifier[\.offset],
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
        lhs.color == rhs.color &&
            lhs.radius == rhs.radius &&
            lhs.offset == rhs.offset
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
