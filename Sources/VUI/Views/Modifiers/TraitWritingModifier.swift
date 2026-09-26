//
//  File: TraitWritingModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol _ViewTraitKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}


public struct _TraitWritingModifier<Trait>: ViewModifier where Trait: _ViewTraitKey {
    public let value: Trait.Value
    public init(value: Trait.Value) {
        self.value = value
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }
        let parentTraitAttr = inputs._traits
        // Keep the merged collection in the graph. Descendant list values read
        // this node, so changing only the written value invalidates them.
        let newTraitAttr: Attribute<ViewTraitCollection> = graph.makeRule {
            var collection = parentTraitAttr.attribute?.value ?? ViewTraitCollection()
            collection[Trait.self] = modifier._attribute.value.value
            return collection
        }
        var modifiedInputs = inputs
        modifiedInputs._traits = OptionalAttribute(newTraitAttr)
        let bodyOut = body(_Graph(), modifiedInputs)

        // A static element tree cannot carry a live trait dependency by value.
        // Wrap it in a list attribute whose identity is retained by each
        // LayoutProxyAttributes value. LayoutProxy then reads that list
        // relative to the layout rule that owns the proxy.
        if case .staticList = bodyOut.views {
            return _ViewListOutputs(
                views: .dynamicList(
                    bodyOut.makeAttribute(inputs: modifiedInputs),
                    nil
                ),
                nextImplicitID: bodyOut.nextImplicitID,
                staticCount: bodyOut.staticCount
            )
        }
        return bodyOut
    }

    public typealias Body = Never
}

struct TraitTransformerModifier<Trait>: ViewModifier
where Trait: _ViewTraitKey {
    var transform: (inout Trait.Value) -> Void

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "TraitTransformerModifier._makeViewList called outside " +
                "an active graph."
            )
        }
        var modifiedInputs = inputs
        let traits: Attribute<ViewTraitCollection> = graph.makeRule {
            var collection = inputs._traits.value ?? ViewTraitCollection()
            var value = collection[Trait.self]
            modifier._attribute.value.transform(&value)
            collection[Trait.self] = value
            return collection
        }
        modifiedInputs._traits = OptionalAttribute(traits)
        modifiedInputs.traitKeys?.insert(Trait.self)
        let outputs = body(_Graph(), modifiedInputs)
        guard case .staticList = outputs.views else { return outputs }
        return _ViewListOutputs(
            views: .dynamicList(outputs.makeAttribute(inputs: modifiedInputs), nil),
            nextImplicitID: outputs.nextImplicitID,
            staticCount: outputs.staticCount
        )
    }

    typealias Body = Never
}

extension View {
    public func _trait<K>(_ key: K.Type, _ value: K.Value) -> some View where K: _ViewTraitKey {
        return modifier(_TraitWritingModifier<K>(value: value))
    }
}
