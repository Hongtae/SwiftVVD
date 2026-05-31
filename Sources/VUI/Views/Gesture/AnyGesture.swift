//
//  File: AnyGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// _MapGesture

/// A gesture that transforms another gesture's value via a phase-mapping AG rule.
struct _MapGesture<Content: Gesture, Value>: Gesture {
    var content: Content
    var transform: (Content.Value) -> Value

    static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("_MapGesture._makeGesture requires AG context")
        }
        let inner = Content._makeGesture(gesture: gesture[\.content], inputs: inputs)
        let innerPhase = inner.phase
        let selfAttr = gesture._attribute
        let mappedPhase: Attribute<GesturePhase<Value>> = graph.makeRule {
            innerPhase.value.map(selfAttr.value.transform)
        }
        return inner.withPhase(mappedPhase)
    }

    typealias Body = Never
    typealias Value = Value
}

extension _MapGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        gestureTypeAcceptsEvent(Content.self, eventType: eventType)
    }
}

extension _MapGesture: DynamicGestureEventTypeAccepting {
    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        gestureValueAcceptsEvent(content, eventType: eventType)
    }
}

// AnyGesture

public struct AnyGesture<Value>: Gesture {
    fileprivate var storage: AnyGestureStorageBase<Value>
    public init<T>(_ gesture: T) where Value == T.Value, T: Gesture {
        self.storage = AnyGestureBox(gesture)
    }
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        guard AttributeGraph.current != nil else {
            fatalError("AnyGesture._makeGesture requires AG context")
        }
        return gesture._attribute.value.storage.makeGestureImpl(
            anyAttr: gesture._attribute, inputs: inputs)
    }
    public typealias Body = Never
}

extension AnyGesture: DynamicGestureEventTypeAccepting {
    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        storage.acceptsEventType(eventType)
    }
}

@usableFromInline
class AnyGestureStorageBase<Value> {
    init<T>(_ gesture: T) where Value == T.Value, T: Gesture {}

    func makeGestureImpl(
        anyAttr: Attribute<AnyGesture<Value>>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Value> {
        fatalError("AnyGestureStorageBase.makeGestureImpl: must override in AnyGestureBox")
    }

    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        true
    }
}

class AnyGestureBox<T: Gesture>: AnyGestureStorageBase<T.Value> {
    let gesture: T
    init(_ gesture: T) {
        self.gesture = gesture
        super.init(gesture)
    }

    override func makeGestureImpl(
        anyAttr: Attribute<AnyGesture<T.Value>>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<T.Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("AnyGestureBox.makeGestureImpl requires AG context")
        }
        // Create an AG attribute for the concrete inner gesture T.
        // Re-evaluates if the AnyGesture's storage ever changes.
        let innerAttr: Attribute<T> = graph.makeRule {
            (anyAttr.value.storage as! AnyGestureBox<T>).gesture
        }
        return T._makeGesture(
            gesture: _GraphValue<T>(_attribute: innerAttr), inputs: inputs)
    }

    override func acceptsEventType(_ eventType: Any.Type) -> Bool {
        gestureValueAcceptsEvent(gesture, eventType: eventType)
    }
}
