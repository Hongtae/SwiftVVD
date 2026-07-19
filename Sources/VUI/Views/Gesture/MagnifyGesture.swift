//
//  File: MagnifyGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct MagnifyGesture: Gesture, PrimitiveGesture {
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var magnification: CGFloat
        public var velocity: CGFloat
        public var startAnchor: UnitPoint
        public var startLocation: CGPoint
    }

    public var minimumScaleDelta: CGFloat

    public init(minimumScaleDelta: CGFloat = 0.01) {
        self.minimumScaleDelta = minimumScaleDelta
    }

    public typealias Body = Never

    public static func _makeGesture(
        gesture: _GraphValue<MagnifyGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Value> {
        guard let graph = _AGGraph.current else {
            fatalError("MagnifyGesture._makeGesture requires AG context")
        }
        let self_ = gesture._attribute.value
        typealias Chain = ModifierGesture<CategoryGesture<MagnifyEvent>, EventListener<MagnifyEvent>>
        let chain: Chain = EventListener<MagnifyEvent>().category(.magnify, includeChildren: false)
        let chainAttr: Attribute<Chain> = graph.makeInput(value: chain)
        let eventOutputs = Chain._makeGesture(gesture: _GraphValue(_attribute: chainAttr), inputs: inputs)
        let phase = MagnifyGesturePhase(
            source: eventOutputs.phase,
            sizeAttr: inputs.size,
            resetSeedAttr: inputs.resetSeed,
            minimumScaleDelta: self_.minimumScaleDelta
        )
        let phaseAttr = graph.makeStatefulRule(phase)
        return eventOutputs.withPhase(phaseAttr)
    }
}

public struct MagnificationGesture: Gesture, PubliclyPrimitiveGesture {
    public var minimumScaleDelta: CGFloat

    public init(minimumScaleDelta: CGFloat = 0.01) {
        self.minimumScaleDelta = minimumScaleDelta
    }

    public typealias Value = CGFloat
    public typealias Body = Never

    typealias InternalBody = _MapGesture<MagnifyGesture, CGFloat>

    var internalBody: InternalBody {
        _MapGesture(
            content: MagnifyGesture(minimumScaleDelta: minimumScaleDelta),
            transform: { $0.magnification }
        )
    }

    public static func _makeGesture(
        gesture: _GraphValue<MagnificationGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<CGFloat> {
        makeGesture(gesture: gesture, inputs: inputs)
    }
}

private struct MagnifyGesturePhase: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<MagnifyGesture.Value>
    typealias PhaseValue = MagnifyGesture.Value

    let source: Attribute<GesturePhase<MagnifyEvent>>
    let sizeAttr: Attribute<ViewSize>
    let resetSeedAttr: Attribute<UInt32>
    let minimumScaleDelta: CGFloat

    var lastResetSeed: UInt32 = 0
    var isTracking = false
    var hasRecognized = false
    var startLocation: CGPoint = .zero
    var startAnchor: UnitPoint = .center
    var baselineScale: CGFloat = 1.0
    var velocitySampler = VelocitySampler<CGFloat>()

    var resetSeed: UInt32 { resetSeedAttr.value }

    mutating func resetPhase() {
        isTracking = false
        hasRecognized = false
        startLocation = .zero
        startAnchor = .center
        baselineScale = 1.0
        velocitySampler.reset()
        _AGGraph.setStatefulOutput(GesturePhase<MagnifyGesture.Value>.possible(nil))
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
            _AGGraph.setStatefulOutput(GesturePhase<MagnifyGesture.Value>.failed)
        }
    }

    private mutating func update(event: MagnifyEvent, terminal: Bool) -> GesturePhase<MagnifyGesture.Value> {
        let location = event.location
        if !isTracking {
            isTracking = true
            startLocation = location
            startAnchor = Self.anchor(for: location, size: sizeAttr.value.value)
            baselineScale = event.initialScale
            velocitySampler.reset()

            if terminal {
                return .failed
            }
            return .possible(nil)
        }

        let accumulatedScale = event.initialScale + event.scaleDelta
        velocitySampler.addSample(
            accumulatedScale,
            time: event.timestamp.seconds
        )
        if abs(accumulatedScale - baselineScale) > minimumScaleDelta {
            hasRecognized = true
        }

        let magnification = max(
            accumulatedScale + 1.0 - baselineScale,
            0.0
        )

        let value = MagnifyGesture.Value(
            time: Date(timeIntervalSinceReferenceDate: event.timestamp.seconds),
            magnification: magnification,
            velocity: velocitySampler.velocity.valuePerSecond,
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
