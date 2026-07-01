//
//  File: ContentTransitionEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Modifier protocol for renderer effects that rewrite child DisplayList output.
protocol _RendererEffect: ViewModifier where Body == Never {
    func effectValue(size: CGSize) -> DisplayList.Effect
}

// Shared _AGGraph plumbing for renderer-effect modifiers.
enum _RendererEffectSupport {
    static func makeView<Effect: _RendererEffect>(
        effect: _GraphValue<Effect>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Effect.self)._makeView called outside an active _AGGraph context.")
        }

        var outputs = body(_Graph(), inputs)
        let position = inputs.base.cachedEnvironment.value.animatedFrame?._animatedPosition ?? inputs.position
        applyRendererEffect(
            to: &outputs.preferences,
            effect: effect._attribute,
            position: position,
            size: inputs.size,
            graph: graph
        )
        return outputs
    }

    static func makeViewList<Effect: _RendererEffect>(
        modifier: _GraphValue<Effect>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(Effect.self)._makeViewList called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }

    private static func applyRendererEffect<Effect: _RendererEffect>(
        to preferences: inout PreferencesOutputs,
        effect: Attribute<Effect>,
        position: Attribute<CGPoint>,
        size: Attribute<ViewSize>,
        graph: _AGGraph
    ) {
        let displayNodes = preferences.values(for: DisplayList.Key.self)
        guard !displayNodes.isEmpty else { return }

        let weakNodes = displayNodes.compactMap { graph.weakAttributeIfValid(for: $0) }
        let transformedAttr: Attribute<DisplayList> = graph.makeRule {
            _ = position.value
            var combined = DisplayList.Key.defaultValue
            for weakNode in weakNodes where weakNode.isValid(in: graph) {
                let list = Attribute<DisplayList>(weakNode.toStrong()).value
                DisplayList.Key.reduce(value: &combined) { list }
            }
            return displayList(
                combined,
                applying: effect.value.effectValue(size: size.value.value)
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
        applying effect: DisplayList.Effect
    ) -> DisplayList {
        DisplayList.effect(effect, contents: source)
    }
}

// Renderer-effect modifier that marks a display list with an active content-transition state.
struct ContentTransitionEffect: _RendererEffect, MultiViewModifier {
    var state: ContentTransition.State

    init(state: ContentTransition.State) {
        self.state = state
    }

    func effectValue(size: CGSize) -> DisplayList.Effect {
        .contentTransition(state)
    }

    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        _RendererEffectSupport.makeView(
            effect: modifier,
            inputs: inputs,
            body: body
        )
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _RendererEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}
