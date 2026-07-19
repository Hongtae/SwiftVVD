//
//  File: RotateGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct RotateGesture: Gesture, PrimitiveGesture {
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
        guard let graph = _AGGraph.current else {
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

public struct RotationGesture: Gesture, PubliclyPrimitiveGesture {
    public var minimumAngleDelta: Angle

    public init(minimumAngleDelta: Angle = .degrees(1)) {
        self.minimumAngleDelta = minimumAngleDelta
    }

    public typealias Value = Angle
    public typealias Body = Never

    typealias InternalBody = _MapGesture<RotateGesture, Angle>

    var internalBody: InternalBody {
        _MapGesture(
            content: RotateGesture(minimumAngleDelta: minimumAngleDelta),
            transform: { $0.rotation }
        )
    }

    public static func _makeGesture(
        gesture: _GraphValue<RotationGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Angle> {
        makeGesture(gesture: gesture, inputs: inputs)
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
    var baselineAngle: Angle = .zero
    var velocitySampler = AnimatableVelocitySampler<Angle>()

    var resetSeed: UInt32 { resetSeedAttr.value }

    mutating func resetPhase() {
        isTracking = false
        hasRecognized = false
        startLocation = .zero
        startAnchor = .center
        baselineAngle = .zero
        velocitySampler = AnimatableVelocitySampler()
        _AGGraph.setStatefulOutput(GesturePhase<RotateGesture.Value>.possible(nil))
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        switch source.value {
        case .possible:
            resetPhase()
        case .active(let event):
            _AGGraph.setStatefulOutput(update(event: event, terminal: false))
        case .ended(let event):
            let phase = update(event: event, terminal: true)
            resetPhase()
            _AGGraph.setStatefulOutput(phase)
        case .failed:
            resetPhase()
            _AGGraph.setStatefulOutput(GesturePhase<RotateGesture.Value>.failed)
        }
    }

    private mutating func update(event: RotateEvent, terminal: Bool) -> GesturePhase<RotateGesture.Value> {
        let location = event.location
        if !isTracking {
            isTracking = true
            startLocation = location
            startAnchor = Self.anchor(for: location, size: sizeAttr.value.value)
            baselineAngle = event.initialAngle
            velocitySampler = AnimatableVelocitySampler()

            if terminal {
                return .failed
            }
            return .possible(nil)
        }

        let accumulatedAngle = event.initialAngle + event.angleDelta
        velocitySampler.addSample(
            accumulatedAngle,
            time: event.timestamp.seconds
        )
        if abs(accumulatedAngle.radians - baselineAngle.radians)
            > abs(minimumAngleDelta.radians) {
            hasRecognized = true
        }

        let rotation = accumulatedAngle - baselineAngle

        let value = RotateGesture.Value(
            time: Date(timeIntervalSinceReferenceDate: event.timestamp.seconds),
            rotation: rotation,
            velocity: velocitySampler.velocity(accumulatedAngle),
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

}
