//
//  File: FocusedValueModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

private struct FocusedValueModifier<Value>: MultiViewModifier {
    typealias Body = Never

    var keyPath: WritableKeyPath<FocusedValues, Value?>
    var value: Value?
    var isSceneValue: Bool

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
        let transform: Attribute<(inout FocusedValueList) -> Void> =
            graph.makeRule {
                let modifier = modifier._attribute.value
                let item = FocusedValueList.Item(
                    version: DisplayList.Version(forUpdate: ()),
                    isFocused: modifier.isSceneValue,
                    update: { focusedValues in
                        guard let value = modifier.value else { return }
                        focusedValues[keyPath: modifier.keyPath] = value
                    }
                )
                return { list in
                    list.items.append(item)
                }
            }
        outputs.preferences.makePreferenceTransformer(
            inputs: inputs.preferences,
            key: FocusedValueList.Key.self,
            transform: transform
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
