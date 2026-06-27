//
//  File: TransactionModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _TransactionModifier: ViewModifier, _GraphInputsModifier {
    public var transform: (inout Transaction) -> Void

    @inlinable public init(transform: @escaping (inout Transaction) -> Void) {
        self.transform = transform
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeInputs called outside an active AttributeGraph context.")
        }
        let parentTransAttr = inputs.transaction
        let newTransAttr: Attribute<Transaction> = graph.makeRule {
            let m = modifier._attribute.value
            var t = parentTransAttr.value
            m.transform(&t)
            return t
        }
        inputs.transaction = newTransAttr
    }

    public typealias Body = Never
}

public struct _ValueTransactionModifier<Value>: ViewModifier, _GraphInputsModifier where Value: Equatable {
    public var value: Value
    public var transform: (inout Transaction) -> Void

    @inlinable public init(value: Value, transform: @escaping (inout Transaction) -> Void) {
        self.value = value
        self.transform = transform
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeInputs called outside an active AttributeGraph context.")
        }
        let parentTransAttr = inputs.transaction
        let newTransAttr: Attribute<Transaction> = graph.makeStatefulRule(
            ValueTransactionModifierTransactionRule(
                modifier: modifier._attribute,
                parent: parentTransAttr
            )
        )
        inputs.transaction = newTransAttr
    }

    public typealias Body = Never
}

private struct ValueTransactionModifierTransactionRule<Observed: Equatable>: StatefulRule {
    typealias Value = Transaction

    var modifier: Attribute<_ValueTransactionModifier<Observed>>
    var parent: Attribute<Transaction>
    var previousValue: Observed?

    mutating func updateValue() {
        let modifierValue = modifier.value
        var transaction = parent.value
        if let previousValue,
           previousValue != modifierValue.value {
            modifierValue.transform(&transaction)
        }
        previousValue = modifierValue.value
        AttributeGraph.setStatefulOutput(transaction)
    }
}

public struct _PushPopTransactionModifier<Content>: ViewModifier where Content: ViewModifier {
    public var content: Content
    public var base: _TransactionModifier

    @inlinable public init(content: Content, transform: @escaping (inout Transaction) -> Void) {
        self.content = content
        base = .init(transform: transform)
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let parentTransAttr = inputs.base.transaction
        let newTransAttr: Attribute<Transaction> = graph.makeRule {
            let m = modifier._attribute.value
            var t = parentTransAttr.value
            m.base.transform(&t)
            return t
        }
        var modifiedInputs = inputs
        modifiedInputs.base.transaction = newTransAttr
        return Content._makeView(modifier: modifier[\.content], inputs: modifiedInputs, body: body)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }
        let parentTransAttr = inputs.base.transaction
        let newTransAttr: Attribute<Transaction> = graph.makeRule {
            let m = modifier._attribute.value
            var t = parentTransAttr.value
            m.base.transform(&t)
            return t
        }
        var modifiedInputs = inputs
        modifiedInputs.base.transaction = newTransAttr
        return Content._makeViewList(modifier: modifier[\.content], inputs: modifiedInputs, body: body)
    }

    public typealias Body = Never
}

extension View {
    @inlinable public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View {
        return modifier(_TransactionModifier(transform: transform))
    }

    @inlinable public func transaction<V>(value: V, _ transform: @escaping (inout Transaction) -> Void) -> some View where V: Equatable {
        return modifier(_ValueTransactionModifier(value: value, transform: transform))
    }
}

extension ViewModifier {
    @inlinable public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some ViewModifier {
        return _PushPopTransactionModifier(content: self, transform: transform)
    }

    @inlinable public func animation(_ animation: Animation?) -> some ViewModifier {
        return transaction { t in
            if !t.disablesAnimations {
                t.animation = animation
            }
        }
    }
}
