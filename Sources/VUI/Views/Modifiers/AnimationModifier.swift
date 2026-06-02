//
//  File: AnimationModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _AnimationModifier<Value>: ViewModifier where Value: Equatable {
    public var animation: Animation?
    public var value: Value

    @inlinable public init(animation: Animation?, value: Value) {
        self.animation = animation
        self.value = value
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let parentTransAttr = inputs.base.transaction
        let newTransAttr: Attribute<Transaction> = graph.makeStatefulRule(
            AnimationModifierTransactionRule(
                modifier: modifier._attribute,
                parent: parentTransAttr
            )
        )
        var modifiedInputs = inputs
        modifiedInputs.base.transaction = newTransAttr
        return body(_Graph(), modifiedInputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }
        let parentTransAttr = inputs.base.transaction
        let newTransAttr: Attribute<Transaction> = graph.makeStatefulRule(
            AnimationModifierTransactionRule(
                modifier: modifier._attribute,
                parent: parentTransAttr
            )
        )
        var modifiedInputs = inputs
        modifiedInputs.base.transaction = newTransAttr
        return body(_Graph(), modifiedInputs)
    }

    public typealias Body = Never
}

extension _AnimationModifier: Equatable {
}

private struct AnimationModifierTransactionRule<Observed: Equatable>: StatefulRule {
    typealias Value = Transaction

    var modifier: Attribute<_AnimationModifier<Observed>>
    var parent: Attribute<Transaction>
    var previousValue: Observed?

    mutating func updateValue() {
        let modifierValue = modifier.value
        var transaction = parent.value
        if let previousValue,
           previousValue != modifierValue.value,
           !transaction.disablesAnimations {
            transaction.animation = modifierValue.animation
        }
        previousValue = modifierValue.value
        AttributeGraph.setStatefulOutput(transaction)
    }
}

extension View {
    @inlinable public func animation<V>(_ animation: Animation?, value: V) -> some View where V: Equatable {
        return modifier(_AnimationModifier(animation: animation, value: value))
    }
}

extension View where Self: Equatable {
    @inlinable public func animation(_ animation: Animation?) -> some View {
        return _AnimationView(content: self, animation: animation)
    }
}
