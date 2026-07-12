//
//  File: PanGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct WheelEvent: EventType, Equatable {
    var timestamp: Time
    var phase: EventPhase
    var binding: EventBinding?
    var offset: Double

    var eventPhase: EventPhase { phase }

    var location: CGPoint? {
        get { nil }
        set { _ = newValue }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.timestamp.seconds == rhs.timestamp.seconds &&
            lhs.phase == rhs.phase &&
            lhs.binding == rhs.binding &&
            lhs.offset == rhs.offset
    }
}

struct PanGesture: Gesture, PrimitiveGesture {
    struct Value: Equatable {
        var timestamp: Time
        var translation: CGSize
        var touchType: TouchType
        var velocity: _Velocity<CGSize>

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.timestamp.seconds == rhs.timestamp.seconds &&
                lhs.translation == rhs.translation &&
                lhs.touchType == rhs.touchType &&
                lhs.velocity == rhs.velocity
        }
    }

    var minimumDistance: CGFloat
    var allowedDirections: _EventDirections

    typealias Body = Never

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Value> {
        guard let graph = _AGGraph.current else {
            fatalError("PanGesture._makeGesture requires AG context")
        }
        let raw = graph.makeInput(value: RawPanGesture(
            minimumDistance: gesture._attribute.value.minimumDistance,
            allowedDirections: gesture._attribute.value.allowedDirections
        ))
        let modifier = graph.makeInput(value: DependentGesture<Value>(
            dependency: .pausedWhileActive
        ))
        return DependentGesture<Value>.makeGesture(
            modifier: _GraphValue(_attribute: modifier),
            inputs: inputs
        ) { inputs in
            RawPanGesture._makeGesture(
                gesture: _GraphValue(_attribute: raw),
                inputs: inputs
            )
        }
    }
}

extension PanGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == ScrollEvent.self
    }
}

struct RawPanGesture: Gesture, PrimitiveGesture {
    struct StateType {
        struct EventInfo {
            var globalTranslation: CGSize
            var translation: CGSize
        }

        var eventInfo: [EventID: EventInfo]
        var phase: GesturePhase<Void>
        var phaseValue: PanGesture.Value
        var globalTranslation: CGSize
    }

    var minimumDistance: CGFloat
    var allowedDirections: _EventDirections

    typealias Value = PanGesture.Value
    typealias Body = Never

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Value> {
        guard let graph = _AGGraph.current else {
            fatalError("RawPanGesture._makeGesture requires AG context")
        }
        let listener = graph.makeInput(value: EventListener<ScrollEvent>())
        let source = EventListener<ScrollEvent>._makeGesture(
            gesture: _GraphValue(_attribute: listener),
            inputs: inputs
        )
        let phase = graph.makeStatefulRule(RawPanGesturePhase(
            gesture: gesture._attribute,
            source: source.phase,
            time: inputs.time,
            resetSeedAttr: inputs.resetSeed
        ))
        return source.withPhase(phase)
    }
}

extension RawPanGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == ScrollEvent.self
    }
}

private struct RawPanGesturePhase: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<PanGesture.Value>
    typealias PhaseValue = PanGesture.Value

    var gesture: Attribute<RawPanGesture>
    var source: Attribute<GesturePhase<ScrollEvent>>
    var time: Attribute<Time>
    var resetSeedAttr: Attribute<UInt32>

    var lastResetSeed: UInt32 = 0
    var wasActive = false
    var lastTranslation = CGSize.zero
    var lastTime = Time.zero
    var lastValue = PanGesture.Value(
        timestamp: .zero,
        translation: .zero,
        touchType: .indirect,
        velocity: _Velocity(valuePerSecond: .zero)
    )

    var resetSeed: UInt32 { resetSeedAttr.value }

    var phaseValue: GesturePhase<PanGesture.Value> {
        (_AGGraph.currentStatefulOutput() as Value?) ?? .possible(nil)
    }

    mutating func resetPhase() {
        wasActive = false
        lastTranslation = .zero
        lastTime = .zero
        _AGGraph.setStatefulOutput(GesturePhase<PanGesture.Value>.possible(nil))
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        let configuration = gesture.value
        let currentTime = time.value
        switch source.value {
        case .possible:
            _AGGraph.setStatefulOutput(GesturePhase<PanGesture.Value>.possible(nil))

        case .active(let event):
            let translation = event.translation
            guard wasActive || accepts(
                translation: translation,
                minimumDistance: configuration.minimumDistance,
                allowedDirections: configuration.allowedDirections
            ) else {
                _AGGraph.setStatefulOutput(GesturePhase<PanGesture.Value>.possible(nil))
                return
            }
            let elapsed = currentTime.seconds - lastTime.seconds
            let delta = CGSize(
                width: translation.width - lastTranslation.width,
                height: translation.height - lastTranslation.height
            )
            let velocity: CGSize
            if wasActive, elapsed.isFinite, elapsed > 0 {
                velocity = CGSize(
                    width: delta.width / elapsed,
                    height: delta.height / elapsed
                )
            } else {
                velocity = event.delta
            }
            let value = PanGesture.Value(
                timestamp: currentTime,
                translation: translation,
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: velocity)
            )
            wasActive = true
            lastTranslation = translation
            lastTime = currentTime
            lastValue = value
            _AGGraph.setStatefulOutput(GesturePhase<PanGesture.Value>.active(value))

        case .ended(let event):
            guard wasActive else {
                _AGGraph.setStatefulOutput(GesturePhase<PanGesture.Value>.failed)
                return
            }
            let value = PanGesture.Value(
                timestamp: currentTime,
                translation: event.translation,
                touchType: .indirect,
                velocity: lastValue.velocity
            )
            wasActive = false
            lastValue = value
            _AGGraph.setStatefulOutput(GesturePhase<PanGesture.Value>.ended(value))

        case .failed:
            wasActive = false
            _AGGraph.setStatefulOutput(GesturePhase<PanGesture.Value>.failed)
        }
    }

    private func accepts(
        translation: CGSize,
        minimumDistance: CGFloat,
        allowedDirections: _EventDirections
    ) -> Bool {
        guard hypot(translation.width, translation.height) >= minimumDistance else {
            return false
        }
        if abs(translation.width) >= abs(translation.height) {
            let direction: _EventDirections = translation.width >= 0 ? .right : .left
            return allowedDirections.contains(direction)
        }
        let direction: _EventDirections = translation.height >= 0 ? .down : .up
        return allowedDirections.contains(direction)
    }
}
