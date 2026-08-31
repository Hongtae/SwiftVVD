//
//  File: FocusViewGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

final class FocusViewGraph: ViewGraphFeature {
    private(set) var _focusedItem = OptionalAttribute<FocusItem?>()
    private(set) var _focusedValues = OptionalAttribute<FocusedValues>()
    private(set) var _focusStore = OptionalAttribute<FocusStore>()
    private(set) var _isFocusSystemEnabled = OptionalAttribute<Bool>()
    var needsFocusUpdate = false
    var wasFocusSystemEnabled = false
    var needsFocusSystemEnabledUpdate = false

    private var bridge: FocusBridge?

    func modifyViewInputs(inputs: inout _ViewInputs, graph: ViewGraph) {
        guard graph.requestedOutputs.contains(.focus) else { return }

        let focusedItem = graph.data.graph.makeInput(
            value: Optional<FocusItem>.none
        )
        let focusedValues = graph.data.graph.makeInput(
            value: FocusedValues()
        )
        let focusStore = graph.data.graph.makeInput(
            value: FocusStore()
        )
        let isFocusSystemEnabled = graph.data.graph.makeInput(value: false)
        let bridge = FocusBridge(
            host: graph.rendererHost as? any FocusStoreHost
        )
        let bridgeAttribute = graph.data.graph.makeInput(
            value: Optional(bridge)
        )

        _focusedItem = OptionalAttribute(focusedItem)
        _focusedValues = OptionalAttribute(focusedValues)
        _focusStore = OptionalAttribute(focusStore)
        _isFocusSystemEnabled = OptionalAttribute(isFocusSystemEnabled)
        self.bridge = bridge

        inputs[FocusedItemInputKey.self] = _focusedItem
        inputs[FocusedValuesInputKey.self] = _focusedValues
        inputs[FocusStoreInputKey.self] = _focusStore
        inputs[FocusBridgeInputKey.self] = OptionalAttribute(bridgeAttribute)
        inputs.preferences.add(FocusedValueList.Key.self)
        inputs.preferences.add(FocusStoreList.Key.self)
    }

    func modifyViewOutputs(
        outputs: inout _ViewOutputs,
        inputs: _ViewInputs,
        graph: ViewGraph
    ) {
        installFocusedValueOutput(outputs: outputs, graph: graph)
        installFocusStoreOutput(outputs: outputs, graph: graph)
    }

    func setFocusedItem(_ item: FocusItem?) {
        _focusedItem.attribute?.setValue(item)
    }

    func setFocusedValues(_ values: FocusedValues) {
        guard let attribute = _focusedValues.attribute,
              attribute.value != values else {
            return
        }
        attribute.setValue(values)
    }

    func setFocusStore(_ store: FocusStore) {
        guard let attribute = _focusStore.attribute,
              attribute.value != store else {
            return
        }
        attribute.setValue(store)
    }

    private func installFocusedValueOutput(
        outputs: _ViewOutputs,
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

    private func installFocusStoreOutput(
        outputs: _ViewOutputs,
        graph: ViewGraph
    ) {
        let nodes = outputs.preferences.values(for: FocusStoreList.Key.self)
        guard !nodes.isEmpty else { return }

        let list: Attribute<FocusStoreList> = graph.data.graph.makeRule {
            var combined = FocusStoreList.Key.defaultValue
            for node in nodes {
                let next = Attribute<FocusStoreList>(node).value
                FocusStoreList.Key.reduce(value: &combined) { next }
            }
            return combined
        }
        let bridge = bridge
        graph.data.graph.makeSideEffectRule {
            bridge?.preferencesDidChange(list.value)
        }
    }
}

protocol FocusedValueListHost: AnyObject {
    func focusedValueListDidChange(_ list: FocusedValueList)
}
