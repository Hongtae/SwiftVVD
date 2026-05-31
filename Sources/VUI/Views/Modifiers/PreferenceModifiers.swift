//
//  File: PreferenceModifiers.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Writes a fixed value for a PreferenceKey into the view tree.
public struct _PreferenceWritingModifier<Key: PreferenceKey>: ViewModifier {
    public typealias Body = Never
    public var value: Key.Value

    public init(key _: Key.Type = Key.self, value: Key.Value) {
        self.value = value
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard AttributeGraph.current != nil else {
            fatalError("\(Self.self)._makeView called outside AttributeGraph context.")
        }
        var outputs = body(_Graph(), inputs)

        // Create reactive AG node for the preference value.
        let valueAttr: Attribute<Key.Value> = modifier[\.value]._attribute
        outputs.preferences.append(Key.self, node: valueAttr.identifier)
        return outputs
    }
}

/// Applies a transform closure to an existing PreferenceKey value flowing up the tree.
/// _makeView reads modifier[\.transform] as an Attribute, then calls
/// outputs.preferences.makePreferenceTransformer.
public struct _PreferenceTransformModifier<Key: PreferenceKey>: ViewModifier {
    public typealias Body = Never
    public var transform: (inout Key.Value) -> Void

    @inlinable
    public init(key _: Key.Type = Key.self,
                transform: @escaping (inout Key.Value) -> Void) {
        self.transform = transform
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Self.self)._makeView called outside AttributeGraph context.")
        }
        var outputs = body(_Graph(), inputs)

        // Get transform as a reactive AG attribute so updates to the modifier
        // field propagate downstream.
        let transformAttr: Attribute<(inout Key.Value) -> Void> = modifier[\.transform]._attribute
        outputs.preferences.makePreferenceTransformer(
            key: Key.self,
            transformAttr: transformAttr,
            graph: graph
        )
        return outputs
    }
}

extension View {
    /// Sets a preference value for the given key.
    @inlinable
    public func preference<K: PreferenceKey>(key: K.Type = K.self, value: K.Value) -> some View {
        modifier(_PreferenceWritingModifier<K>(value: value))
    }

    /// Applies a transform to the given preference key's value.
    @inlinable
    public func transformPreference<K: PreferenceKey>(
        _ key: K.Type = K.self,
        _ callback: @escaping (inout K.Value) -> Void
    ) -> some View {
        modifier(_PreferenceTransformModifier<K>(transform: callback))
    }
}
