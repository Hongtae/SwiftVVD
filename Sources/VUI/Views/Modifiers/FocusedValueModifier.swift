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
        var content: Content?
        var isFocused: Bool
        var cycleDetector: UpdateCycleDetector
        var lastResetSeed: UInt32

        init(
            viewPhase: Attribute<_GraphInputs.Phase>,
            modifier: Attribute<FocusedValueModifier>
        ) {
            _viewPhase = viewPhase
            _modifier = modifier
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

            let nextIsFocused = modifier.value.isSceneValue
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
            let item = FocusedValueList.Item(
                version: DisplayList.Version(forUpdate: ()),
                isFocused: isFocused,
                update: { focusedValues in
                    guard let content else { return }
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
        outputs.preferences.makePreferenceTransformer(
            inputs: inputs.preferences,
            key: FocusedValueList.Key.self,
            transform: graph.makeStatefulRule(
                Transform(
                    viewPhase: inputs.base.phase,
                    modifier: modifier._attribute
                )
            )
        )
        return outputs
    }
}

extension View {
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
