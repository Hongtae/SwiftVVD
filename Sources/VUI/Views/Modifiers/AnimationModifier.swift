//
//  File: AnimationModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _AnimationModifier<Value>: PrimitiveViewModifier where Value: Equatable {
    public var animation: Animation?
    public var value: Value

    @inlinable public init(animation: Animation?, value: Value) {
        self.animation = animation
        self.value = value
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var modifiedInputs = inputs
        modifiedInputs.copyCaches()
        _makeInputs(modifier: modifier, inputs: &modifiedInputs.base)
        if modifiedInputs.needsGeometry {
            let cachedEnvironmentAttribute = modifiedInputs.base.cachedEnvironment
            var cachedEnvironment = cachedEnvironmentAttribute.value
            _ = cachedEnvironment.animatedPosition(for: modifiedInputs)
            _ = cachedEnvironment.animatedSize(for: modifiedInputs)
            cachedEnvironmentAttribute.value = cachedEnvironment
        }
        return body(_Graph(), modifiedInputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var modifiedInputs = inputs
        _makeInputs(modifier: modifier, inputs: &modifiedInputs.base)
        return body(_Graph(), modifiedInputs)
    }

    private static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeInputs called outside an active _AGGraph context.")
        }

        let observedValue = modifier[\.value]._attribute
        let animation = modifier[\.animation]._attribute
        let transactionSeed = transactionSeedAttribute(in: graph)
        let valueTransactionSeed: Attribute<UInt32> = graph.makeStatefulRule(
            ValueTransactionSeed(
                value: observedValue,
                transactionSeed: transactionSeed,
                oldValue: observedValue.value
            )
        )
        inputs.transaction = graph.makeRule(
            ChildTransaction(
                valueTransactionSeed: valueTransactionSeed,
                animation: animation,
                parent: inputs.transaction,
                transactionSeed: transactionSeed
            )
        )
    }

    private static func transactionSeedAttribute(in graph: _AGGraph) -> Attribute<UInt32> {
        if let ref = _AGGraphContext.current,
           let host = ref.context as? GraphHost {
            return host.data._transactionSeed
        }
        return graph.makeInput(value: UInt32.zero)
    }

    public typealias Body = Never
}

extension _AnimationModifier: Equatable {
}

@available(*, unavailable)
extension _AnimationModifier: Sendable {
}

private struct ValueTransactionSeed<Observed: Equatable>: StatefulRule, AsyncAttribute {
    typealias Value = UInt32

    var value: Attribute<Observed>
    var transactionSeed: Attribute<UInt32>
    var oldValue: Observed?

    mutating func updateValue() {
        let newValue = value.value
        let currentSeed = transactionSeed.value
        if oldValue != newValue {
            oldValue = newValue
            _AGGraph.setStatefulOutput(currentSeed)
        } else if let previousSeed = _AGGraph.currentStatefulOutput(UInt32.self) {
            _AGGraph.setStatefulOutput(previousSeed)
        } else {
            // Initial evaluation must not activate the modifier in this pass.
            _AGGraph.setStatefulOutput(currentSeed &- 1)
        }
    }
}

private struct ChildTransaction: Rule, AsyncAttribute {
    typealias Value = Transaction

    var valueTransactionSeed: Attribute<UInt32>
    var animation: Attribute<Animation?>
    var parent: Attribute<Transaction>
    var transactionSeed: Attribute<UInt32>

    var value: Transaction {
        var transaction = parent.value
        guard !transaction.disablesAnimations else {
            return transaction
        }

        let currentSeed = transactionSeed.value
        guard valueTransactionSeed.value == currentSeed else {
            return transaction
        }

        transaction.animation = animation.value
        precondition(
            transactionSeed.value == currentSeed,
            "Transaction seed changed while evaluating an animation modifier."
        )
        return transaction
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
