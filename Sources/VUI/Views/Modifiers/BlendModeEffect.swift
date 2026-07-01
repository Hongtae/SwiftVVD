//
//  File: BlendModeEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private enum _BlendModeEffectSupport {
    static func makeView<Modifier>(
        modifier: _GraphValue<Modifier>,
        blendMode: _GraphValue<BlendMode>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs where Modifier: ViewModifier {
        guard let graph = _AGGraph.current else {
            fatalError("\(Modifier.self)._makeView called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        applyBlendMode(to: &outputs.preferences, blendMode: blendMode, graph: graph)
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

    private static func applyBlendMode(
        to preferences: inout PreferencesOutputs,
        blendMode: _GraphValue<BlendMode>,
        graph: _AGGraph
    ) {
        let displayNodes = preferences.values(for: DisplayList.Key.self)
        guard !displayNodes.isEmpty else { return }

        let weakNodes = displayNodes.compactMap { graph.weakAttributeIfValid(for: $0) }
        let blendModeAttr = blendMode._attribute
        let transformedAttr: Attribute<DisplayList> = graph.makeRule {
            var combined = DisplayList.Key.defaultValue
            for weakNode in weakNodes where weakNode.isValid(in: graph) {
                let list = Attribute<DisplayList>(weakNode.toStrong()).value
                DisplayList.Key.reduce(value: &combined) { list }
            }
            return displayList(combined, applyingBlendMode: blendModeAttr.value)
        }

        let displayKeyID = ObjectIdentifier(DisplayList.Key.self)
        preferences.preferences.removeAll {
            ObjectIdentifier($0.key) == displayKeyID
        }
        preferences.append(DisplayList.Key.self, node: transformedAttr.identifier)
    }

    private static func displayList(
        _ source: DisplayList,
        applyingBlendMode blendMode: BlendMode
    ) -> DisplayList {
        var result = DisplayList()
        result.debugItems.append(contentsOf: source.debugItems)
        result.recordInterpolationBounds(source.interpolationBounds)
        for effect in source.effects {
            result.appendEffect(
                effect.effect,
                contents: displayList(
                    effect.contents,
                    applyingBlendMode: blendMode
                )
            )
        }

        guard !source.items.isEmpty else { return result }
        guard blendMode != .normal else {
            result.items.append(contentsOf: source.items)
            return result
        }

        let items = source.items
        result.appendBlendModeItem(
            bounds: source.interpolationBounds,
            blendMode: blendMode
        ) { context in
            var context = context
            context.blendMode = blendMode.graphicsContextBlendMode
            context.drawLayer { layerContext in
                for item in items {
                    item(layerContext)
                }
            }
        }
        return result
    }
}

public struct _BlendModeEffect: Equatable, Animatable, ViewModifier, Sendable {
    public var blendMode: BlendMode

    @inlinable public init(blendMode: BlendMode) {
        self.blendMode = blendMode
    }

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        _BlendModeEffectSupport.makeView(
            modifier: modifier,
            blendMode: modifier[\.blendMode],
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _BlendModeEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

extension View {
    @inlinable public func blendMode(_ blendMode: BlendMode) -> some View {
        modifier(_BlendModeEffect(blendMode: blendMode))
    }
}
