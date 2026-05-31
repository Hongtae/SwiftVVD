//
//  File: OpacityEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _OpacityEffect: ViewModifier {
    public var opacity: Double
    
    @inlinable public init(opacity: Double) {
        self.opacity = opacity
    }

    public typealias Body = Never

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        applyOpacity(to: &outputs.preferences, modifier: modifier, graph: graph)
        return outputs
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard AttributeGraph.current != nil else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }

    private static func applyOpacity(to preferences: inout PreferencesOutputs,
                                     modifier: _GraphValue<Self>,
                                     graph: AttributeGraph) {
        let displayNodes = preferences.values(for: DisplayList.Key.self)
        guard !displayNodes.isEmpty else { return }

        let weakNodes = displayNodes.compactMap { graph.weakAttributeIfValid(for: $0) }
        let opacityAttr: Attribute<Double> = modifier[\.opacity]._attribute
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

        guard !source.items.isEmpty else { return result }
        guard opacity > 0 else { return result }
        guard opacity != 1 else {
            result.items.append(contentsOf: source.items)
            return result
        }

        let items = source.items
        result.items.append { context in
            var context = context
            context.opacity *= opacity
            guard context.opacity > 0 else { return }
            context.drawLayer { layerContext in
                for item in items {
                    item(layerContext)
                }
            }
        }
        return result
    }
}

extension View {
    @inlinable public func opacity(_ opacity: Double) -> some View {
        modifier(_OpacityEffect(opacity: opacity))
    }
}
