//
//  File: FocusedValuesViewGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// Receives the focused-values portion of the focus root contract. Focus item
// and focus-store ownership remain separate until their responder contracts
// are implemented.
final class FocusedValuesViewGraph: ViewGraphFeature {
    private(set) var _focusedValues = OptionalAttribute<FocusedValues>()

    func modifyViewInputs(inputs: inout _ViewInputs, graph: ViewGraph) {
        guard graph.requestedOutputs.contains(.focus) else { return }

        let focusedValues = graph.data.graph.makeInput(
            value: FocusedValues()
        )
        _focusedValues = OptionalAttribute(focusedValues)
        inputs[FocusedValuesInputKey.self] = _focusedValues
        inputs.preferences.add(FocusedValueList.Key.self)
    }

    func modifyViewOutputs(
        outputs: inout _ViewOutputs,
        inputs: _ViewInputs,
        graph: ViewGraph
    ) {
        let nodes = outputs.preferences.values(for: FocusedValueList.Key.self)
        guard !nodes.isEmpty else { return }

        let list: Attribute<FocusedValueList> = graph.data.graph.makeRule {
            var combined = FocusedValueList.Key.defaultValue
            for node in nodes {
                let next = Attribute<FocusedValueList>(node).value
                FocusedValueList.Key.reduce(value: &combined) { next }
            }
            return combined
        }
        graph.data.graph.makeSideEffectRule { [weak graph] in
            guard let host = graph?.rendererHost as? FocusedValueListHost else {
                return
            }
            host.focusedValueListDidChange(list.value)
        }
    }

    func setFocusedValues(_ values: FocusedValues) {
        guard let attribute = _focusedValues.attribute,
              attribute.value != values else {
            return
        }
        attribute.setValue(values)
    }
}

protocol FocusedValueListHost: AnyObject {
    func focusedValueListDidChange(_ list: FocusedValueList)
}
