//
//  File: TagValueTrait.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

@usableFromInline
struct TagValueTraitKey<V>: _ViewTraitKey where V: Hashable {
    @usableFromInline
    enum Value {
        case untagged
        case tagged(V)
    }

    @inlinable static var defaultValue: TagValueTraitKey<V>.Value {
        .untagged
    }
}

@usableFromInline
struct IsAuxiliaryContentTraitKey: _ViewTraitKey {
    @inlinable static var defaultValue: Bool {
        false
    }

    @usableFromInline
    typealias Value = Bool
}

extension View {
    @inlinable public func tag<V>(_ tag: V, includeOptional: Bool = true) -> some View where V: Hashable {
        modifier(_TagTraitWritingModifier(tag: tag, includeOptional: includeOptional))
    }

    @inlinable public func _untagged() -> some View {
        return _trait(IsAuxiliaryContentTraitKey.self, true)
    }
}

public struct _TagTraitWritingModifier<TagValue: Hashable>: ViewModifier, PrimitiveViewModifier {
    public let tag: TagValue
    public let includeOptional: Bool

    public init(tag: TagValue, includeOptional: Bool) {
        self.tag = tag
        self.includeOptional = includeOptional
    }

    public static func _makeView(
        modifier: _GraphValue<Self>, inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>, inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("_TagTraitWritingModifier requires an active graph.")
        }
        var inputs = inputs
        inputs._traits = OptionalAttribute(graph.makeRule(AddTrait(
            _modifier: modifier._attribute, _traits: inputs._traits
        )))
        inputs.traitKeys?.insert(TagValueTraitKey<TagValue>.self)
        inputs.traitKeys?.insert(TagValueTraitKey<TagValue?>.self)
        let outputs = body(_Graph(), inputs)
        guard case .staticList = outputs.views else { return outputs }
        return _ViewListOutputs(
            views: .dynamicList(outputs.makeAttribute(inputs: inputs), nil),
            nextImplicitID: outputs.nextImplicitID,
            staticCount: outputs.staticCount
        )
    }

    public static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int? {
        body(inputs)
    }

    public typealias Body = Never

    private struct AddTrait: Rule, AsyncAttribute {
        var _modifier: Attribute<_TagTraitWritingModifier>
        var _traits: OptionalAttribute<ViewTraitCollection>

        var value: ViewTraitCollection {
            var traits = _traits.value ?? ViewTraitCollection()
            let modifier = _modifier.value
            traits[TagValueTraitKey<TagValue>.self] = .tagged(modifier.tag)
            traits[TagValueTraitKey<TagValue?>.self] = modifier.includeOptional
                ? .tagged(.some(modifier.tag)) : .untagged
            return traits
        }
    }
}
