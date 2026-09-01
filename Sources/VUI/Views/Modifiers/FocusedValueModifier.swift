//
//  File: FocusedValueModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

private struct FocusedValueModifier<Content>: MultiViewModifier {
    typealias Body = Never

    var keyPath: WritableKeyPath<FocusedValues, Content?>
    var value: Content?
    var isSceneValue: Bool

    private struct Transform: StatefulRule {
        typealias Value = (inout FocusedValueList) -> Void

        var _viewPhase: Attribute<_GraphInputs.Phase>
        var _modifier: Attribute<FocusedValueModifier>
        var responder: DefaultLayoutViewResponder
        var _depth: Attribute<Int>
        var _focusItem: OptionalAttribute<FocusItem?>
        var content: Content?
        var isFocused: Bool
        var cycleDetector: UpdateCycleDetector
        var lastResetSeed: UInt32

        init(
            viewPhase: Attribute<_GraphInputs.Phase>,
            modifier: Attribute<FocusedValueModifier>,
            responder: DefaultLayoutViewResponder,
            depth: Attribute<Int>,
            focusItem: OptionalAttribute<FocusItem?>
        ) {
            _viewPhase = viewPhase
            _modifier = modifier
            self.responder = responder
            _depth = depth
            _focusItem = focusItem
            content = nil
            isFocused = false
            cycleDetector = UpdateCycleDetector()
            lastResetSeed = 0
        }

        mutating func updateValue() {
            let modifier = _modifier.changedValue(options: [])
            let resetSeed = _viewPhase.value.resetSeed
            var needsUpdate = !hasValue

            if lastResetSeed != resetSeed {
                lastResetSeed = resetSeed
                cycleDetector.reset()
                needsUpdate = true
            }

            if modifier.changed,
               !compareValues(
                    content,
                    modifier.value.value,
                    options: AGComparisonOptions(mode: .storedRepresentation)
               ) {
                content = modifier.value.value
                needsUpdate = true
            }

            let focusItem = _focusItem.changedValue(options: [])
            let nextIsFocused: Bool
            if let focusedResponder = focusItem?.value?.responder
                as? ViewResponder {
                nextIsFocused = focusedResponder.isDescendant(of: responder)
            } else {
                nextIsFocused = false
            }
            if isFocused != nextIsFocused {
                isFocused = nextIsFocused
                needsUpdate = true
            }

            guard needsUpdate,
                  cycleDetector.dispatch(label: "FocusedValue update") else {
                return
            }

            let content = content
            let keyPath = modifier.value.keyPath
            let isSceneValue = modifier.value.isSceneValue
            let depth = _depth.value
            let isFocused = isFocused
            let item = FocusedValueList.Item(
                version: DisplayList.Version(forUpdate: ()),
                isFocused: isFocused,
                update: { focusedValues in
                    guard let content else { return }
                    focusedValues.storageOptions = []
                    if isSceneValue {
                        focusedValues.storageOptions.insert(.scene)
                        focusedValues.navigationDepth = depth
                    }
                    if isFocused {
                        focusedValues.storageOptions.insert(
                            .inFocusedViewHierarchy
                        )
                    }
                    focusedValues[keyPath: keyPath] = content
                }
            )
            _AGGraph.setStatefulOutput { (list: inout FocusedValueList) in
                list.items.append(item)
            }
        }
    }

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "FocusedValueModifier._makeView called outside an active "
                    + "_AGGraph context."
            )
        }

        var outputs = body(_Graph(), inputs)
        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else {
            return outputs
        }

        let innerNodes = outputs.preferences.values(for: ViewRespondersKey.self)
        let innerResponders: Attribute<[ViewResponder]>
        if innerNodes.isEmpty {
            innerResponders = graph.makeInput(value: [])
        } else if innerNodes.count == 1 {
            innerResponders = Attribute(innerNodes[0])
        } else {
            innerResponders = graph.makeRule {
                var combined = ViewRespondersKey.defaultValue
                for node in innerNodes {
                    let next = Attribute<[ViewResponder]>(node).value
                    ViewRespondersKey.reduce(value: &combined) { next }
                }
                return combined
            }
        }

        let responder = DefaultLayoutViewResponder(inputs: inputs)
        let responderOutput = graph.makeStatefulRule(
            DefaultLayoutResponderFilter(
                children: innerResponders,
                responder: responder
            )
        )
        outputs.preferences.setValue(
            responderOutput.identifier,
            for: ViewRespondersKey.self
        )

        outputs.preferences.makePreferenceTransformer(
            inputs: inputs.preferences,
            key: FocusedValueList.Key.self,
            transform: graph.makeStatefulRule(
                Transform(
                    viewPhase: inputs.base.phase,
                    modifier: modifier._attribute,
                    responder: responder,
                    depth: inputs.base[
                        FocusedValueNavigationDepthInputKey.self
                    ],
                    focusItem: inputs[FocusedItemInputKey.self]
                )
            )
        )
        return outputs
    }
}

extension View {
    public func focusedValue<T>(
        _ keyPath: WritableKeyPath<FocusedValues, T?>,
        _ value: T
    ) -> some View {
        modifier(
            FocusedValueModifier(
                keyPath: keyPath,
                value: value,
                isSceneValue: false
            )
        )
    }

    public func focusedValue<T>(
        _ keyPath: WritableKeyPath<FocusedValues, T?>,
        _ value: T?
    ) -> some View {
        modifier(
            FocusedValueModifier(
                keyPath: keyPath,
                value: value,
                isSceneValue: false
            )
        )
    }

    public func focusedSceneValue<T>(
        _ keyPath: WritableKeyPath<FocusedValues, T?>,
        _ value: T
    ) -> some View {
        modifier(
            FocusedValueModifier(
                keyPath: keyPath,
                value: value,
                isSceneValue: true
            )
        )
    }

    public func focusedSceneValue<T>(
        _ keyPath: WritableKeyPath<FocusedValues, T?>,
        _ value: T?
    ) -> some View {
        modifier(
            FocusedValueModifier(
                keyPath: keyPath,
                value: value,
                isSceneValue: true
            )
        )
    }
}
