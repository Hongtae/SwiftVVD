//
//  File: GestureModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// GestureModifier

/// Protocol for modifier gestures: gestures that wrap another gesture and transform
/// its inputs or output.
///
/// `ModifierGesture._makeGesture` dispatches to `Modifier._makeGesture(modifier:inputs:body:)`,
/// passing a closure that calls `Body._makeGesture` for the inner gesture.
protocol GestureModifier {
    associatedtype Value
    associatedtype BodyValue
    static func _makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<BodyValue>
    ) -> _GestureOutputs<Value>
}

// ModifierGesture

/// Applies a GestureModifier to a Gesture, producing a combined gesture whose Value
/// is the modifier's output type.
///
/// Stores the wrapped content and modifier.
/// _makeGesture dispatches to Modifier._makeGesture(modifier:inputs:body:), passing a
/// closure that calls Body._makeGesture for the inner gesture.
struct ModifierGesture<Modifier: GestureModifier, Body: Gesture>: Gesture,
    PrimitiveGesture, PrimitiveDebuggableGesture
    where Modifier.BodyValue == Body.Value
{
    var content: Body
    var modifier: Modifier

    typealias Value = Modifier.Value

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Modifier.Value> {
        Modifier._makeGesture(
            modifier: gesture[\.modifier],
            inputs: inputs,
            body: { modifiedInputs in
                Body._makeGesture(
                    gesture: gesture[\.content],
                    inputs: modifiedInputs
                )
            }
        )
    }
}
