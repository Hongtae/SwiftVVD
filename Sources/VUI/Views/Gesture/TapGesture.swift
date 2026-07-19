//
//  File: TapGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - SingleTapGesture

/// Internal gesture type used by TapGesture.
/// Implements single/multi-tap recognition via an AG modifier chain.
///
/// body chain (inner to outer):
///   EventListener<E>
///   -> CategoryGesture<E>         (GestureCategory.select)
///   -> RepeatGesture<E>           (requires count taps)
///   -> RequiredTapCountWriter<E>  (writes RequiredTapCountKey preference)
struct SingleTapGesture<E: TappableEventType>: Gesture {
    var count: Int

    typealias Value = E

    typealias Body = ModifierGesture<
        RequiredTapCountWriter<E>,
        ModifierGesture<
            RepeatGesture<E>,
            ModifierGesture<
                CategoryGesture<E>,
                EventListener<E>
            >
        >
    >

    var body: Body {
        ModifierGesture(
            modifier: RequiredTapCountWriter(count: count),
            body: ModifierGesture(
                modifier: RepeatGesture(count: count),
                body: ModifierGesture(
                    modifier: CategoryGesture(
                        category: .select,
                        includeChildren: false
                    ),
                    body: EventListener<E>()
                )
            )
        )
    }
}

// MARK: - TapGesture

// TapGesture builds SingleTapGesture<TappableEvent> and maps TappableEvent to Void.

public struct TapGesture: Gesture, PrimitiveGesture {
    public var count: Int
    public init(count: Int = 1) {
        self.count = count
    }

    public typealias Body = Never
    public typealias Value = Void

    public static func _makeGesture(
        gesture: _GraphValue<TapGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Void> {
        guard let graph = _AGGraph.current else {
            fatalError("TapGesture._makeGesture requires AG context")
        }
        let count = gesture._attribute.value.count
        let singleTap = SingleTapGesture<TappableEvent>(count: count)
        let singleTapAttr: Attribute<SingleTapGesture<TappableEvent>> = graph.makeInput(value: singleTap)
        let rawOutputs = SingleTapGesture<TappableEvent>._makeGesture(
            gesture: _GraphValue(_attribute: singleTapAttr),
            inputs: inputs
        )
        // Map TappableEvent to Void (TapGesture.Value = Void).
        let mappedPhase: Attribute<GesturePhase<Void>> = graph.makeRule {
            rawOutputs.phase.value.map { _ in () }
        }
        return rawOutputs.withPhase(mappedPhase)
    }
}

extension View {
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        self.gesture(TapGesture(count: count).onEnded(action), including: .all)
    }
}
