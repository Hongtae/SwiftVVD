//
//  File: OpacityEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

enum _OpacityEffectSupport {
    static func makeView<Modifier>(
        modifier: _GraphValue<Modifier>,
        opacity: _GraphValue<Double>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs where Modifier: ViewModifier {
        guard let graph = _AGGraph.current else {
            fatalError("\(Modifier.self)._makeView called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        applyOpacity(to: &outputs.preferences, opacity: opacity, graph: graph)
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

    private static func applyOpacity(
        to preferences: inout PreferencesOutputs,
        opacity: _GraphValue<Double>,
        graph: _AGGraph
    ) {
        let displayNodes = preferences.values(for: DisplayList.Key.self)
        guard !displayNodes.isEmpty else { return }

        let weakNodes = displayNodes.compactMap { graph.weakAttributeIfValid(for: $0) }
        let opacityAttr: Attribute<Double> = opacity._attribute
        let transformedAttr: Attribute<DisplayList> = graph.makeRule {
            var combined = DisplayList.Key.defaultValue
            for weakNode in weakNodes where weakNode.isValid(in: graph) {
                let list = Attribute<DisplayList>(weakNode.toStrong()).value
                DisplayList.Key.reduce(value: &combined) { list }
            }
            return displayList(combined, applyingOpacity: opacityAttr.value)
        }

        let displayKeyID = ObjectIdentifier(DisplayList.Key.self)
        preferences.preferences.removeAll {
            ObjectIdentifier($0.key) == displayKeyID
        }
        preferences.append(DisplayList.Key.self, node: transformedAttr.identifier)
    }

    private static func displayList(_ source: DisplayList, applyingOpacity opacity: Double) -> DisplayList {
        var result = DisplayList()
        result.debugItems.append(contentsOf: source.debugItems)
        result.recordInterpolationBounds(source.interpolationBounds)
        for effect in source.effects {
            result.appendEffect(
                effect.effect,
                contents: displayList(effect.contents, applyingOpacity: opacity)
            )
        }

        guard !source.renderItems.isEmpty else { return result }
        guard opacity > 0 else { return result }
        guard opacity != 1 else {
            result.items.append(contentsOf: source.renderItems)
            return result
        }

        result.appendOpacityItem(
            bounds: source.interpolationBounds,
            opacity: opacity,
            contents: source.renderItemList
        )
        return result
    }
}

public struct _OpacityEffect: Equatable, Animatable, ViewModifier, Sendable {
    public var opacity: Double

    @inlinable public init(opacity: Double) {
        self.opacity = opacity
    }

    public var animatableData: Double {
        get { opacity }
        set { opacity = newValue }
    }

    public typealias Body = Never

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        return _OpacityEffectSupport.makeView(
            modifier: modifier,
            opacity: modifier[\.opacity],
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        _OpacityEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

extension _OpacityEffect: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        let value = Float(opacity)
        if value != 1 {
            encoder.encodeFloatFieldAlways(1, value)
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var opacity = 1.0
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            if fieldNumber == 1 {
                opacity = Double(try decoder.decodeFloatField(wireType: wireType))
            } else {
                try decoder.skipField(wireType: wireType)
            }
        }
        self.init(opacity: opacity)
    }
}

struct OpacityRendererEffect: Equatable, Animatable, ViewModifier {
    var opacity: Double

    var animatableData: Double {
        get { opacity }
        set { opacity = newValue }
    }

    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        return _OpacityEffectSupport.makeView(
            modifier: modifier,
            opacity: modifier[\.opacity],
            inputs: inputs,
            body: body
        )
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _OpacityEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

extension View {
    @inlinable public func opacity(_ opacity: Double) -> some View {
        modifier(_OpacityEffect(opacity: opacity))
    }
}
