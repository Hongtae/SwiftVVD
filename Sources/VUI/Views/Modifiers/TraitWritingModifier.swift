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
        let newTraitAttr: Attribute<ViewTraitCollection> = graph.makeRule {
            var collection = parentTraitAttr.attribute?.value ?? ViewTraitCollection()
            collection[Trait.self] = modifier._attribute.value.value
            return collection
        }
        var modifiedInputs = inputs
        modifiedInputs._traits = OptionalAttribute(newTraitAttr)
        let bodyOut = body(_Graph(), modifiedInputs)

        // Convert the static body output to a dynamicList so the parent
        // Layout receives an Attribute<ViewList> as _traitsList for each child.
        if case .staticList(let elements) = bodyOut.views {
            let viewListAttr: Attribute<any ViewList> = graph.makeRule {
                let traits = newTraitAttr.value   // re-evaluate when trait value changes
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
