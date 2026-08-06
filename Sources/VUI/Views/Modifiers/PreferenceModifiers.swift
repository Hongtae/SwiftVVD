//
//  File: PreferenceModifiers.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Writes a fixed value for a PreferenceKey into the view tree.
/// Conforms to MultiViewModifier; _makeViewList uses the MultiViewModifier
/// default unless the PreferredColorSchemeKey preview-context specialization applies.
/// _makeView: called per child during ModifiedElements materialization.
public struct _PreferenceWritingModifier<Key: PreferenceKey>: MultiViewModifier, PrimitiveViewModifier, _SceneModifier {
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
        guard _AGGraph.current != nil else {
            fatalError("\(Self.self)._makeView called outside _AGGraph context.")
        }
        var childInputs = inputs
        childInputs.preferences.keys.remove(Key.self)
        var outputs = body(_Graph(), childInputs)

        // Create reactive AG node for the preference value.
        let valueAttr: Attribute<Key.Value> = modifier[\.value]._attribute
        outputs.preferences.append(Key.self, node: valueAttr.identifier)
        return outputs
    }

    public static func _makeScene(
        modifier: _GraphValue<Self>,
        inputs: _SceneInputs,
        body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs
    ) -> _SceneOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(Self.self)._makeScene called outside _AGGraph context.")
        }
        var childInputs = inputs
        childInputs.preferences.keys.remove(Key.self)
        var outputs = body(_Graph(), childInputs)
        outputs.preferences.append(Key.self, node: modifier[\.value]._attribute.identifier)
        return outputs
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(Self.self)._makeViewList called outside an active _AGGraph context.")
        }

        if Key.self == PreferredColorSchemeKey.self,
           inputs.options.contains(.previewContext),
           let graph = _AGGraph.current {
            let modifierValueAttr = Attribute<ColorScheme?>(modifier[\.value]._attribute.identifier)
            let parentEnvAttr = inputs.base.cachedEnvironment.value.environment
            var childInputs = inputs

            childInputs._traits = OptionalAttribute(
                graph.makeRule(
                    _PreferenceWritingModifier<PreferredColorSchemeKey>.ColorSchemeTrait(
                        traitListAttr: inputs._traits,
                        modifierValueAttr: modifierValueAttr
                    )
                )
            )
            let environment = graph.makeRule(
                _PreferenceWritingModifier<PreferredColorSchemeKey>.ColorSchemeEnv(
                    parentEnvAttr: parentEnvAttr,
                    modifierValueAttr: modifierValueAttr
                )
            )
            childInputs.base.cachedEnvironment = MutableBox(
                CachedEnvironment(environment: environment)
            )
            childInputs.base.changedDebugProperties |= 0x20
            return body(_Graph(), childInputs)
        }

        return makeMultiViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

/// Applies a transform closure to an existing PreferenceKey value flowing up the tree.
/// Conforms to MultiViewModifier; _makeViewList uses the MultiViewModifier default.
/// _makeView: called per child during ModifiedElements materialization.
public struct _PreferenceTransformModifier<Key: PreferenceKey>: MultiViewModifier, PrimitiveViewModifier, _SceneModifier {
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
        guard _AGGraph.current != nil else {
            fatalError("\(Self.self)._makeView called outside _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)

        // Get transform as a reactive AG attribute so updates to the modifier
        // field propagate downstream through modifier[\.transform].
        let transformAttr: Attribute<(inout Key.Value) -> Void> = modifier[\.transform]._attribute
        outputs.preferences.makePreferenceTransformer(
            inputs: inputs.preferences,
            key: Key.self,
            transform: transformAttr
        )
        return outputs
    }

    public static func _makeScene(
        modifier: _GraphValue<Self>,
        inputs: _SceneInputs,
        body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs
    ) -> _SceneOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(Self.self)._makeScene called outside _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.preferences.makePreferenceTransformer(
            inputs: inputs.preferences,
            key: Key.self,
            transform: modifier[\.transform]._attribute
        )
        return outputs
    }
}

// MARK: - PreferredColorSchemeKey specialization

extension _PreferenceWritingModifier where Key == PreferredColorSchemeKey {

    /// Rule that derives EnvironmentValues for preview content from the modifier value.
    struct ColorSchemeEnv: Rule {
        typealias Value = EnvironmentValues
        var parentEnvAttr: Attribute<EnvironmentValues>
        var modifierValueAttr: Attribute<ColorScheme?>

        var value: EnvironmentValues {
            var env = parentEnvAttr.value.trackingCopy()
            if let cs = modifierValueAttr.value {
                env.colorScheme = cs
            }
            return env
        }
    }

    /// Rule that derives ViewTraitCollection for preview content from the modifier value.
    struct ColorSchemeTrait: Rule {
        typealias Value = ViewTraitCollection
        var traitListAttr: OptionalAttribute<ViewTraitCollection>
        var modifierValueAttr: Attribute<ColorScheme?>

        var value: ViewTraitCollection {
            var traits = traitListAttr.attribute?.value ?? ViewTraitCollection()
            traits[PreviewColorSchemeTraitKey.self] = modifierValueAttr.value
            return traits
        }
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
