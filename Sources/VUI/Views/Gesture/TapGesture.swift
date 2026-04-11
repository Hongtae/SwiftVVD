//
//  File: TapGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// TapGesture
//
// _makeGesture -> create SingleTapGesture<TappableEvent> -> map TappableEvent to Void
//
// TapGesture._makeGesture -> SingleTapGesture<TappableEvent>._makeGesture -> map { _ in () }

public struct TapGesture: Gesture {
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
        guard let graph = AttributeGraph.current else {
            fatalError("TapGesture._makeGesture requires AG context")
        }
        // create SingleTapGesture<TappableEvent> -> AG input node -> run body chain
        let count = gesture._attribute.value.count
        let singleTap = SingleTapGesture<TappableEvent>(count: count)
        let singleTapAttr: Attribute<SingleTapGesture<TappableEvent>> = graph.makeInput(value: singleTap)
        let rawOutputs = SingleTapGesture<TappableEvent>._makeGesture(
            gesture: _GraphValue(_attribute: singleTapAttr),
            inputs: inputs
        )
        // map TappableEvent to Void (TapGesture.Value = Void)
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
