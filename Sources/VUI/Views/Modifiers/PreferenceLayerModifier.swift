//
//  File: PreferenceLayerModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

extension View {
    public func overlayPreferenceValue<Key: PreferenceKey, Overlay: View>(
        _ key: Key.Type,
        alignment: Alignment = .center,
        @ViewBuilder _ transform: @escaping (Key.Value) -> Overlay
    ) -> some View {
        modifier(_OverlayPreferenceModifier<Key, Overlay>(
            alignment: alignment, transform: transform
        ))
    }

    public func backgroundPreferenceValue<Key: PreferenceKey, Background: View>(
        _ key: Key.Type,
        alignment: Alignment = .center,
        @ViewBuilder _ transform: @escaping (Key.Value) -> Background
    ) -> some View {
        modifier(_BackgroundPreferenceModifier<Key, Background>(
            alignment: alignment, transform: transform
        ))
    }
}

public struct _OverlayPreferenceModifier<Key: PreferenceKey, Overlay: View>:
    MultiViewModifier, PrimitiveViewModifier {
    public var transform: (Key.Value) -> Overlay
    public var alignment: Alignment

    public init(alignment: Alignment, transform: @escaping (Key.Value) -> Overlay) {
        self.transform = transform
        self.alignment = alignment
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        makeSecondaryPreferenceView(
            modifier: modifier._attribute, inputs: inputs, body: body, flipOrder: false
        )
    }

    public typealias Body = Never
}

@available(*, unavailable)
extension _OverlayPreferenceModifier: Sendable {}

public struct _BackgroundPreferenceModifier<Key: PreferenceKey, Background: View>:
    MultiViewModifier, PrimitiveViewModifier {
    public var transform: (Key.Value) -> Background
    public var alignment: Alignment

    public init(alignment: Alignment, transform: @escaping (Key.Value) -> Background) {
        self.transform = transform
        self.alignment = alignment
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        makeSecondaryPreferenceView(
            modifier: modifier._attribute.unsafeBitCast(
                to: _OverlayPreferenceModifier<Key, Background>.self
            ),
            inputs: inputs, body: body, flipOrder: true
        )
    }

    public typealias Body = Never
}

@available(*, unavailable)
extension _BackgroundPreferenceModifier: Sendable {}

struct SecondaryChild<Key: PreferenceKey, Overlay: View>: Rule, AsyncAttribute {
    var _modifier: Attribute<_OverlayPreferenceModifier<Key, Overlay>>
    var _preferenceValue: OptionalAttribute<Key.Value>

    var value: Overlay {
        guard let graph = _AGGraph.current,
              let owner = _AGGraph.currentRuleContextAttribute else {
            fatalError("SecondaryChild evaluated outside an active rule context.")
        }
        let inbox = graph.inbox
        var result: Overlay!
        withObservationTracking {
            let modifier = _modifier.value
            let value = _preferenceValue.attribute?.value ?? Key.defaultValue
            result = modifier.transform(value)
        } onChange: { [weak inbox] in
            let transaction = UnsafeSendableBox(Transaction.current)
            inbox?.enqueue {
                _AGGraph.current?.markNeedsEvaluation(
                    owner, transaction: transaction.value,
                    propagateTransaction: !transaction.value.isEmpty
                )
            }
        }
        return result
    }
}

func makeSecondaryPreferenceView<Key: PreferenceKey, Overlay: View>(
    modifier: Attribute<_OverlayPreferenceModifier<Key, Overlay>>,
    inputs: _ViewInputs,
    body: (_Graph, _ViewInputs) -> _ViewOutputs,
    flipOrder: Bool
) -> _ViewOutputs {
    guard let graph = _AGGraph.current else {
        fatalError("makeSecondaryPreferenceView called outside an active _AGGraph context.")
    }
    var primaryInputs = inputs
    primaryInputs.preferences.add(Key.self)
    primaryInputs.base.pushStableIndex(0)
    let primaryOutputs = body(_Graph(), primaryInputs)
    let layoutDirection = inputs.base.cachedEnvironment.value.attribute(
        id: .layoutDirection, { $0.layoutDirection }
    )
    let geometry = graph.makeRule(SecondaryLayerGeometryQuery(
        _alignment: OptionalAttribute(modifier[keyPath: \.alignment]),
        _layoutDirection: layoutDirection,
        _primaryPosition: inputs.position,
        _primarySize: inputs.size,
        _primaryLayoutComputer: primaryOutputs._layoutComputer,
        _secondaryLayoutComputer: OptionalAttribute()
    ))
    var secondaryInputs = inputs
    secondaryInputs.copyCaches()
    secondaryInputs.implicitRootType = _ZStackLayout.self
    secondaryInputs.needsGeometry = true
    secondaryInputs.requestsLayoutComputer = true
    secondaryInputs.position = geometry[keyPath: \.origin]
    secondaryInputs.size = geometry[keyPath: \.dimensions.size]
    secondaryInputs.base.pushStableIndex(1)
    let child = graph.makeRule(SecondaryChild(
        _modifier: modifier,
        _preferenceValue: primaryOutputs.preferences
            .reducedValue(for: Key.self, in: graph)
            .map(OptionalAttribute.init) ?? OptionalAttribute()
    ))
    let secondaryOutputs = Overlay._makeView(
        view: _GraphValue(_attribute: child), inputs: secondaryInputs
    )
    graph.mutateRule(geometry.identifier, as: SecondaryLayerGeometryQuery.self,
                     invalidating: true) { query in
        query._secondaryLayoutComputer = secondaryOutputs._layoutComputer
    }
    var visitor = PairwisePreferenceCombinerVisitor(
        outputs: flipOrder
            ? (secondaryOutputs.preferences, primaryOutputs.preferences)
            : (primaryOutputs.preferences, secondaryOutputs.preferences),
        result: PreferencesOutputs()
    )
    for key in inputs.preferences.keys { key.visitKey(&visitor) }
    return _ViewOutputs(preferences: visitor.result,
                        layoutComputer: primaryOutputs._layoutComputer)
}
