//
//  File: MagnifyGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct MagnifyGesture: Gesture {
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

extension MagnifyGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == MagnifyEvent.self
    }
}

public struct MagnificationGesture: Gesture {
    public var minimumScaleDelta: CGFloat

    public init(minimumScaleDelta: CGFloat = 0.01) {
        self.minimumScaleDelta = minimumScaleDelta
    }

    public typealias Value = CGFloat
    public typealias Body = Never

    public static func _makeGesture(
        gesture: _GraphValue<MagnificationGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<CGFloat> {
        guard let graph = _AGGraph.current else {
            fatalError("MagnificationGesture._makeGesture requires AG context")
        }
        let magnify = MagnifyGesture(minimumScaleDelta: gesture._attribute.value.minimumScaleDelta)
        let magnifyAttr: Attribute<MagnifyGesture> = graph.makeInput(value: magnify)
        let outputs = MagnifyGesture._makeGesture(
            gesture: _GraphValue(_attribute: magnifyAttr),
            inputs: inputs
        )
        let mappedPhase: Attribute<GesturePhase<CGFloat>> = graph.makeRule {
            outputs.phase.value.map { $0.magnification }
        }
        return outputs.withPhase(mappedPhase)
    }
}

extension MagnificationGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == MagnifyEvent.self
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
    var lastTimestamp: Double?

    var resetSeed: UInt32 { resetSeedAttr.value }

    mutating func resetPhase() {
        isTracking = false
        hasRecognized = false
        startLocation = .zero
        startAnchor = .center
        lastTimestamp = nil
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
        let location = event.location ?? .zero
        if !isTracking {
            isTracking = true
            startLocation = location
            startAnchor = Self.anchor(for: location, size: sizeAttr.value.value)
        }

        let magnitude = abs(event.magnification - 1.0)
        if magnitude >= minimumScaleDelta {
            hasRecognized = true
        }

        let velocity = Self.velocity(
            current: event.magnification,
            previous: event.previousMagnification,
            timestamp: event.timestamp,
            previousTimestamp: lastTimestamp
        )
        lastTimestamp = event.timestamp

        let value = MagnifyGesture.Value(
            time: Date(),
            magnification: event.magnification,
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
        current: CGFloat,
        previous: CGFloat,
        timestamp: Double,
        previousTimestamp: Double?
    ) -> CGFloat {
        guard let previousTimestamp else { return 0 }
        let dt = timestamp - previousTimestamp
        guard dt > 0 else { return 0 }
        return (current - previous) / dt
    }
}
