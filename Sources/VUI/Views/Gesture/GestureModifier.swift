//
//  File: GestureModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// GestureModifier

/// Protocol for modifier gestures: gestures that wrap another gesture and transform
/// its inputs or output. Inherits Gesture so conformers have associated Value/Body.
///
/// `ModifierGesture._makeGesture` dispatches to `Modifier.makeGesture(modifier:inputs:body:)`,
/// passing a closure that calls `Body._makeGesture` for the inner gesture.
protocol GestureModifier: Gesture {
    associatedtype BodyValue
    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<BodyValue>
    ) -> _GestureOutputs<Value>
}

extension GestureModifier {
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        fatalError("\(Self.self) is a GestureModifier - use it as Modifier inside ModifierGesture, not standalone")
    }
}

// ModifierGesture

/// Applies a GestureModifier to a Gesture, producing a combined gesture whose Value
/// is the modifier's output type.
///
/// Stores the modifier and wrapped body.
/// _makeGesture dispatches to Modifier.makeGesture(modifier:inputs:body:), passing a
/// closure that calls Body._makeGesture for the inner gesture.
struct ModifierGesture<Modifier: GestureModifier, Body: Gesture>: Gesture
    where Modifier.BodyValue == Body.Value
{
    var modifier: Modifier
    var body: Body

    typealias Value = Modifier.Value

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Modifier.Value> {
        Modifier.makeGesture(
            modifier: gesture[\.modifier],
            inputs: inputs,
            body: { modifiedInputs in
                Body._makeGesture(gesture: gesture[\.body], inputs: modifiedInputs)
            }
        )
    }
}

extension ModifierGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        gestureTypeAcceptsEvent(Body.self, eventType: eventType)
    }
}

extension ModifierGesture: DynamicGestureEventTypeAccepting {
    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        gestureValueAcceptsEvent(body, eventType: eventType)
    }
}
