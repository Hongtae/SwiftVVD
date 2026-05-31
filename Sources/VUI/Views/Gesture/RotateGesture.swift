//
//  File: RotateGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct RotateGesture: Gesture {
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var rotation: Angle
        public var velocity: Angle
        public var startAnchor: UnitPoint
        public var startLocation: CGPoint
    }

    public var minimumAngleDelta: Angle

    public init(minimumAngleDelta: Angle = .degrees(1)) {
        self.minimumAngleDelta = minimumAngleDelta
    }

    public typealias Body = Never

    public static func _makeGesture(
        gesture: _GraphValue<RotateGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("RotateGesture._makeGesture requires AG context")
        }
        let self_ = gesture._attribute.value
        typealias Chain = ModifierGesture<CategoryGesture<RotateEvent>, EventListener<RotateEvent>>
        let chain: Chain = EventListener<RotateEvent>().category(.rotate, includeChildren: false)
        let chainAttr: Attribute<Chain> = graph.makeInput(value: chain)
        let eventOutputs = Chain._makeGesture(gesture: _GraphValue(_attribute: chainAttr), inputs: inputs)
        let phase = RotateGesturePhase(
            source: eventOutputs.phase,
            sizeAttr: inputs.size,
            resetSeedAttr: inputs.resetSeed,
            minimumAngleDelta: self_.minimumAngleDelta
        )
        let phaseAttr = graph.makeStatefulRule(phase)
        return eventOutputs.withPhase(phaseAttr)
    }
}

extension RotateGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == RotateEvent.self
    }
}

public struct RotationGesture: Gesture {
    public var minimumAngleDelta: Angle

    public init(minimumAngleDelta: Angle = .degrees(1)) {
        self.minimumAngleDelta = minimumAngleDelta
    }

    public typealias Value = Angle
    public typealias Body = Never

    public static func _makeGesture(
        gesture: _GraphValue<RotationGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Angle> {
        guard let graph = AttributeGraph.current else {
            fatalError("RotationGesture._makeGesture requires AG context")
        }
        let rotate = RotateGesture(minimumAngleDelta: gesture._attribute.value.minimumAngleDelta)
        let rotateAttr: Attribute<RotateGesture> = graph.makeInput(value: rotate)
        let outputs = RotateGesture._makeGesture(
            gesture: _GraphValue(_attribute: rotateAttr),
            inputs: inputs
        )
        let mappedPhase: Attribute<GesturePhase<Angle>> = graph.makeRule {
            outputs.phase.value.map { $0.rotation }
        }
        return outputs.withPhase(mappedPhase)
    }
}

extension RotationGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == RotateEvent.self
    }
}

private struct RotateGesturePhase: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<RotateGesture.Value>
    typealias PhaseValue = RotateGesture.Value

    let source: Attribute<GesturePhase<RotateEvent>>
    let sizeAttr: Attribute<ViewSize>
    let resetSeedAttr: Attribute<UInt32>
    let minimumAngleDelta: Angle

    var lastResetSeed: UInt32 = 0
    var isTracking = false
    var hasRecognized = false
    var startLocation: CGPoint = .zero
    var startAnchor: UnitPoint = .center
    var lastTimestamp: Double?

    var resetSeed: UInt32 { resetSeedAttr.value }

    mutating func resetPhase() {
        isTracking = false
        hasRecognized = false
        startLocation = .zero
        startAnchor = .center
        lastTimestamp = nil
        AttributeGraph.setStatefulOutput(GesturePhase<RotateGesture.Value>.possible(nil))
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        switch source.value {
        case .possible:
            resetPhase()
        case .active(let event):
            AttributeGraph.setStatefulOutput(update(event: event, terminal: false))
        case .ended(let event):
            let phase = update(event: event, terminal: true)
            resetPhase()
            AttributeGraph.setStatefulOutput(phase)
        case .failed:
            resetPhase()
            AttributeGraph.setStatefulOutput(GesturePhase<RotateGesture.Value>.failed)
        }
    }

    private mutating func update(event: RotateEvent, terminal: Bool) -> GesturePhase<RotateGesture.Value> {
        let location = event.location ?? .zero
        if !isTracking {
            isTracking = true
            startLocation = location
            startAnchor = Self.anchor(for: location, size: sizeAttr.value.value)
        }

        if abs(event.rotation.radians) >= abs(minimumAngleDelta.radians) {
            hasRecognized = true
        }

        let velocity = Self.velocity(
            current: event.rotation,
            previous: event.previousRotation,
            timestamp: event.timestamp,
            previousTimestamp: lastTimestamp
        )
        lastTimestamp = event.timestamp

        let value = RotateGesture.Value(
            time: Date(),
            rotation: event.rotation,
            velocity: velocity,
            startAnchor: startAnchor,
            startLocation: startLocation
        )

        if terminal {
            return hasRecognized ? .ended(value) : .failed
        }
        return hasRecognized ? .active(value) : .possible(nil)
    }

    private static func anchor(for location: CGPoint, size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: location.x / size.width, y: location.y / size.height)
    }

    private static func velocity(
        current: Angle,
        previous: Angle,
        timestamp: Double,
        previousTimestamp: Double?
    ) -> Angle {
        guard let previousTimestamp else { return .zero }
        let dt = timestamp - previousTimestamp
        guard dt > 0 else { return .zero }
        return Angle(radians: (current.radians - previous.radians) / dt)
    }
}
