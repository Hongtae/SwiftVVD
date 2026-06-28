//
//  File: BlurEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private enum _BlurEffectSupport {
    static func makeView<Modifier>(
        modifier: _GraphValue<Modifier>,
        radius: _GraphValue<CGFloat>,
        isOpaque: _GraphValue<Bool>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs where Modifier: ViewModifier {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Modifier.self)._makeView called outside an active AttributeGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        applyBlur(to: &outputs.preferences, radius: radius, isOpaque: isOpaque, graph: graph)
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

    private static func applyBlur(
        to preferences: inout PreferencesOutputs,
        radius: _GraphValue<CGFloat>,
        isOpaque: _GraphValue<Bool>,
        graph: AttributeGraph
    ) {
        let displayNodes = preferences.values(for: DisplayList.Key.self)
        guard !displayNodes.isEmpty else { return }

        let weakNodes = displayNodes.compactMap { graph.weakAttributeIfValid(for: $0) }
        let radiusAttr = radius._attribute
        let isOpaqueAttr = isOpaque._attribute
        let transformedAttr: Attribute<DisplayList> = graph.makeRule {
            var combined = DisplayList.Key.defaultValue
            for weakNode in weakNodes where weakNode.isValid(in: graph) {
                let list = Attribute<DisplayList>(weakNode.toStrong()).value
                DisplayList.Key.reduce(value: &combined) { list }
            }
            return displayList(
                combined,
                applyingBlur: radiusAttr.value,
                isOpaque: isOpaqueAttr.value
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
        applyingBlur radius: CGFloat,
        isOpaque: Bool
    ) -> DisplayList {
        var result = DisplayList()
        result.debugItems.append(contentsOf: source.debugItems)
        result.recordInterpolationBounds(source.interpolationBounds)
        for effect in source.effects {
            result.appendEffect(
                effect.effect,
                contents: displayList(
                    effect.contents,
                    applyingBlur: radius,
                    isOpaque: isOpaque
                )
            )
        }

        guard !source.items.isEmpty else { return result }
        guard radius >= .ulpOfOne else {
            result.items.append(contentsOf: source.items)
            return result
        }

        let items = source.items
        result.appendBlurItem(
            bounds: source.interpolationBounds,
            radius: radius,
            isOpaque: isOpaque
        ) { context in
            context.drawLayer { layerContext in
                let options: GraphicsContext.BlurOptions = isOpaque ? .opaque : []
                layerContext.addFilter(.blur(radius: radius, options: options))
                for item in items {
                    item(layerContext)
                }
            }
        }
        return result
    }
}

public struct _BlurEffect: Equatable, Animatable, ViewModifier, Sendable {
    public var radius: CGFloat
    public var isOpaque: Bool

    @inlinable public init(radius: CGFloat, opaque: Bool) {
        self.radius = radius
        self.isOpaque = opaque
    }

    public var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        return _BlurEffectSupport.makeView(
            modifier: modifier,
            radius: modifier[\.radius],
            isOpaque: modifier[\.isOpaque],
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _BlurEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

extension View {
    @inlinable public func blur(radius: CGFloat, opaque: Bool = false) -> some View {
        modifier(_BlurEffect(radius: radius, opaque: opaque))
    }
}
