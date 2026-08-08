//
//  File: AnimatableAttribute.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Animatable {
    public static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeAnimatable called outside an active _AGGraph context.")
        }
        let attr: Attribute<Self> = graph.makeStatefulRule(
            AnimatableAttribute(
                source: value._attribute,
                phase: inputs.phase,
                time: inputs.time,
                transaction: inputs.transaction,
                environment: inputs.cachedEnvironment.value.environment
            )
        )
        attr.flags = .transactional
        value = _GraphValue(_attribute: attr)
    }
}

extension Attribute where Value: Animatable {
    func animated(inputs: _GraphInputs) -> Attribute<Value> {
        var value = _GraphValue(_attribute: self)
        Value._makeAnimatable(value: &value, inputs: inputs)
        return value._attribute
    }
}

private struct AnimatableAttribute<AnimatedValue: Animatable>:
    StatefulRule,
    ObservedAttribute,
    AsyncAttribute,
    CustomStringConvertible
{
    typealias Value = AnimatedValue

    var _source: Attribute<AnimatedValue>
    var _environment: Attribute<EnvironmentValues>
    var helper: AnimatableAttributeHelper<AnimatedValue>

    var description: String {
        "Animatable<\(AnimatedValue.self)>"
    }

    init(
        source: Attribute<AnimatedValue>,
        phase: Attribute<_GraphInputs.Phase>,
        time: Attribute<Time>,
        transaction: Attribute<Transaction>,
        environment: Attribute<EnvironmentValues>
    ) {
        self._source = source
        self._environment = environment
        self.helper = AnimatableAttributeHelper(
            _phase: phase,
            _time: time,
            _transaction: transaction
        )
    }

    mutating func updateValue() {
        guard _AGGraph.current != nil else {
            fatalError("AnimatableAttribute.updateValue called outside an active _AGGraph context.")
        }

        var value = _source.changedValue(options: [])
        helper.update(
            value: &value,
            defaultAnimation: nil,
            environment: _environment
        )
        if value.changed ||
            _AGGraph.currentStatefulOutput(AnimatedValue.self) == nil {
            _AGGraph.setStatefulOutput(value.value)
        }
    }

    mutating func destroy() {
        helper.removeListeners()
    }
}
