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
        if case .staticList(let elements) = bodyOut.views {
            let viewListAttr: Attribute<any ViewList> = graph.makeRule {
                let traits = newTraitAttr.value
                return BaseViewList(elements: elements, traits: traits)
            }
            return _ViewListOutputs(views: .dynamicList(viewListAttr, nil),
                                    nextImplicitID: 0, staticCount: nil)
        }
        return bodyOut
    }

    public typealias Body = Never
}

extension View {
    public func _trait<K>(_ key: K.Type, _ value: K.Value) -> some View where K: _ViewTraitKey {
        return modifier(_TraitWritingModifier<K>(value: value))
    }
}
