//
//  File: PreferenceModifiers.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Writes a fixed value for a PreferenceKey into the view tree.
/// Conforms to MultiViewModifier; _makeViewList uses the MultiViewModifier
/// default unless the PreferredColorSchemeKey static-list specialization applies.
/// _makeView: called per child during ModifiedElements materialization.
public struct _PreferenceWritingModifier<Key: PreferenceKey>: MultiViewModifier {
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

    // PreferredColorSchemeKey has a static-list specialization. Static child
    // generators get per-child ColorSchemeEnv / ColorSchemeTrait rules, while
    // dynamic lists must fall through to the generic ModifiedViewList.ListModifier path.
    //
    // All other keys use the generic MultiViewModifier._makeViewList path:
    // body call + _ViewListOutputs.multiModifier wrapping.
    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard AttributeGraph.current != nil else {
            fatalError("\(Self.self)._makeViewList called outside an active AttributeGraph context.")
        }

        let innerOutputs = body(_Graph(), inputs)

        // Path 1: PreferredColorSchemeKey staticList. Set per-child
        // ColorSchemeEnv / ColorSchemeTrait rules.
        if Key.self == PreferredColorSchemeKey.self,
           let graph = AttributeGraph.current,
           case .staticList(let innerElements) = innerOutputs.views {
            // Safe: runtime guard above confirms Key.Value == ColorScheme?; reinterpret ID only.
            let modifierValueAttr = Attribute<ColorScheme?>(modifier[\.value]._attribute.identifier)
            let parentEnvAttr = inputs.base.cachedEnvironment.value.environment
            let updatedElements = _applyColorSchemeEnvToElements(
                innerElements,
                graph: graph,
                parentEnvAttr: parentEnvAttr,
                modifierValueAttr: modifierValueAttr
            )
            let modElements = ModifiedElements.make(base: updatedElements, modifier: modifier, inputs: inputs.base)
            return _ViewListOutputs(
                views: .staticList(.modified(modElements)),
                nextImplicitID: innerOutputs.nextImplicitID,
                staticCount: innerOutputs.staticCount
            )
        }

        // Path 2: generic path, equivalent to MultiViewModifier._makeViewList.
        // Handles both staticList and dynamicList. Dynamic PCS must take this path:
        // ModifiedViewList.ListModifier + ApplyModifiers + pred chain.
        var outputs = innerOutputs
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

/// Applies a transform closure to an existing PreferenceKey value flowing up the tree.
/// Conforms to MultiViewModifier; _makeViewList uses the MultiViewModifier default.
/// _makeView: called per child during ModifiedElements materialization.
public struct _PreferenceTransformModifier<Key: PreferenceKey>: MultiViewModifier {
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
        // field propagate downstream through modifier[\.transform].
        let transformAttr: Attribute<(inout Key.Value) -> Void> = modifier[\.transform]._attribute
        outputs.preferences.makePreferenceTransformer(
            key: Key.self,
            transformAttr: transformAttr,
            transactionAttr: inputs.base.transaction,
            graph: graph
        )
        return outputs
    }
}

// MARK: - PreferredColorSchemeKey specialization

// Free functions host the PreferredColorSchemeKey static-list specialization.
// The unconstrained generic _makeViewList can call these after checking Key.self.

// File-private free function, not a static method on the where-constrained extension because
// Swift cannot call `where Key == PreferredColorSchemeKey` methods from the unconstrained
// generic _makeViewList, even inside `if Key.self == PreferredColorSchemeKey.self`.
// References _PreferenceWritingModifier<PreferredColorSchemeKey>.ColorSchemeEnv / ColorSchemeTrait.
private func _applyColorSchemeEnvToElements(
    _ elements: ViewListElements,
    graph: AttributeGraph,
    parentEnvAttr: Attribute<EnvironmentValues>,
    modifierValueAttr: Attribute<ColorScheme?>
) -> ViewListElements {
    switch elements {
    case .unaryElements(let unary):
        guard var gen = unary.typedGenerator else {
            return .unaryElements(unary)
        }
        let envRule = _PreferenceWritingModifier<PreferredColorSchemeKey>.ColorSchemeEnv(
            parentEnvAttr: parentEnvAttr, modifierValueAttr: modifierValueAttr)
        let traitRule = _PreferenceWritingModifier<PreferredColorSchemeKey>.ColorSchemeTrait(
            traitListAttr: gen.traitListAttr, modifierValueAttr: modifierValueAttr)
        gen.envAttr = OptionalAttribute(graph.makeRule(envRule))
        gen.traitListAttr = OptionalAttribute(graph.makeRule(traitRule))
        return .unaryElements(UnaryElements(generator: gen))
    case .modified(var mod):
        guard let baseEls = mod.base as? ViewListElements else { return .modified(mod) }
        mod.base = _applyColorSchemeEnvToElements(baseEls, graph: graph,
                                                   parentEnvAttr: parentEnvAttr,
                                                   modifierValueAttr: modifierValueAttr)
        return .modified(mod)
    case .merged(let outputs):
        let updated = outputs.map { output -> _ViewListOutputs in
            guard case .staticList(let els) = output.views else { return output }
            return _ViewListOutputs(
                views: .staticList(_applyColorSchemeEnvToElements(els, graph: graph,
                                                                   parentEnvAttr: parentEnvAttr,
                                                                   modifierValueAttr: modifierValueAttr)),
                nextImplicitID: output.nextImplicitID,
                staticCount: output.staticCount
            )
        }
        return .merged(updated)
    }
}

extension _PreferenceWritingModifier where Key == PreferredColorSchemeKey {

    /// Rule that derives EnvironmentValues for a child from the PCS modifier value.
    /// Reads the PCS modifier value and the parent EnvironmentValues, returning derived
    /// EnvironmentValues with colorScheme applied. Set as each child's envAttr so the
    /// child re-evaluates reactively when either the parent env or the color scheme changes.
    struct ColorSchemeEnv: Rule {
        typealias Value = EnvironmentValues
        var parentEnvAttr: Attribute<EnvironmentValues>
        var modifierValueAttr: Attribute<ColorScheme?>

        func updateValue() -> EnvironmentValues {
            var env = parentEnvAttr.value
            if let cs = modifierValueAttr.value {
                env.colorScheme = cs
            }
            return env
        }
    }

    /// Rule that derives ViewTraitCollection for a child from the PCS modifier value.
    /// Reads the PCS modifier value and the child's ViewTraitCollection, returning derived
    /// ViewTraitCollection with PreviewColorSchemeTraitKey applied.
    struct ColorSchemeTrait: Rule {
        typealias Value = ViewTraitCollection
        var traitListAttr: OptionalAttribute<ViewTraitCollection>
        var modifierValueAttr: Attribute<ColorScheme?>

        func updateValue() -> ViewTraitCollection {
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
