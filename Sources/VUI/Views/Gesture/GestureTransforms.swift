//
//  File: GestureTransforms.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - MapGesture / MapPhase
// ─────────────────────────────────────────────────────────────────────────────

// MapGesture<A,B>._makeGesture -> creates MapPhase<A,B>: StatefulRule
struct MapGesture<A, B>: GestureModifier {
    typealias BodyValue = A
    typealias Value = B
    typealias Body = Never

    var transform: (A) -> B

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<A>
    ) -> _GestureOutputs<B> {
        guard let graph = AttributeGraph.current else {
            fatalError("MapGesture.makeGesture requires AG context")
        }
        let bodyOutputs = body(inputs)
        let sourceAttr = bodyOutputs.phase

        let mapPhase = MapPhase<A, B>(
            source: sourceAttr,
            transform: modifier._attribute.value.transform
        )
        let resultAttr = graph.makeStatefulRule(mapPhase)
        return bodyOutputs.withPhase(resultAttr)
    }
}

struct MapPhase<A, B>: StatefulRule {
    typealias Value = GesturePhase<B>

    var source: Attribute<GesturePhase<A>>
    var transform: (A) -> B
    var lastResetSeed: UInt32 = 0

    mutating func updateValue() {
        let phase = source.value
        AttributeGraph.setStatefulOutput(phase.map(transform))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - DurationGesture / DurationPhase
// ─────────────────────────────────────────────────────────────────────────────

// DurationGesture<E>._makeGesture -> creates DurationPhase<E>: StatefulRule
// Output type is GesturePhase<Double> (Double, not E!)
// No E: EventType constraint, so DurationGesture<Void> is valid in SingleLongPressGesture.body chain
struct DurationGesture<E>: GestureModifier {
    typealias BodyValue = E
    typealias Value = Double
    typealias Body = Never

    var minimumDuration: Double

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<Double> {
        guard let graph = AttributeGraph.current else {
            fatalError("DurationGesture.makeGesture requires AG context")
        }
        let bodyOutputs = body(inputs)

        let durationPhase = DurationPhase<E>(
            source: bodyOutputs.phase,
            timeAttr: inputs.time,
            minimumDuration: modifier._attribute.value.minimumDuration
        )
        let resultAttr = graph.makeStatefulRule(durationPhase)
        return bodyOutputs.withPhase(resultAttr)
    }
}

// DurationPhase<E>: StatefulRule outputs GesturePhase<Double>
// No E: EventType constraint, so DurationPhase<Void> is valid
struct DurationPhase<E>: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<Double>

    var source: Attribute<GesturePhase<E>>
    var timeAttr: Attribute<Time>
    var minimumDuration: Double
    // DurationPhase does not use seed-based reset and always returns 0
    var resetSeed: UInt32 { 0 }
    var lastResetSeed: UInt32 = 0
    var startTime: Double = 0
    var isTracking: Bool = false

    // ResettableGestureRule: Value == GesturePhase<Double> == GesturePhase<PhaseValue>
    typealias PhaseValue = Double
    // phaseValue default impl applies via the extension where Value == GesturePhase<PhaseValue>

    mutating func resetPhase() {
        startTime = 0
        isTracking = false
        AttributeGraph.setStatefulOutput(GesturePhase<Double>.possible(nil))
    }

    mutating func updateValue() {
        let phase = source.value
        let now = timeAttr.value.seconds

        switch phase {
        case .possible:
            isTracking = false
            startTime = 0
            AttributeGraph.setStatefulOutput(GesturePhase<Double>.possible(nil))
        case .active:
            if !isTracking {
                isTracking = true
                startTime = now
            }
            let elapsed = now - startTime
            if elapsed >= minimumDuration {
                AttributeGraph.setStatefulOutput(GesturePhase<Double>.active(elapsed))
            } else {
                AttributeGraph.setStatefulOutput(GesturePhase<Double>.possible(nil))
            }
        case .ended:
            let elapsed = now - startTime
            if elapsed >= minimumDuration {
                AttributeGraph.setStatefulOutput(GesturePhase<Double>.ended(elapsed))
            } else {
                AttributeGraph.setStatefulOutput(GesturePhase<Double>.failed)
            }
            isTracking = false
        case .failed:
            isTracking = false
            AttributeGraph.setStatefulOutput(GesturePhase<Double>.failed)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CoordinateSpaceGesture / CoordinateSpacePhase
// ─────────────────────────────────────────────────────────────────────────────

// CoordinateSpaceGesture<E>._makeGesture transforms location via animatedPosition pattern
// Transforms GesturePhase<E>.location in body outputs to the target coordinateSpace.
// .global -> pass-through, .local -> global-to-local via ViewTransform, .named -> stub.
struct CoordinateSpaceGesture<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    var coordinateSpace: CoordinateSpace

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        let bodyOutputs = body(inputs)
        let cs = modifier._attribute.value.coordinateSpace

        // .global: location is already in global coordinates, so pass through
        if cs == .global { return bodyOutputs }

        guard let graph = AttributeGraph.current else {
            fatalError("CoordinateSpaceGesture.makeGesture requires AG context")
        }
        let phase = CoordinateSpacePhase<E>(
            source: bodyOutputs.phase,
            transformAttr: inputs.transform,
            coordinateSpace: cs
        )
        let resultAttr = graph.makeStatefulRule(phase)
        return bodyOutputs.withPhase(resultAttr)
    }
}

// CoordinateSpacePhase<E>: StatefulRule transforms the location field of GesturePhase<E>
struct CoordinateSpacePhase<E: EventType>: StatefulRule {
    typealias Value = GesturePhase<E>

    let source: Attribute<GesturePhase<E>>
    let transformAttr: Attribute<ViewTransform>
    let coordinateSpace: CoordinateSpace

    mutating func updateValue() {
        let phase = source.value
        switch coordinateSpace {
        case .global:
            // pass-through (CoordinateSpaceGesture.makeGesture filters .global early,
            // but guard here for the initial StatefulRule evaluation)
            AttributeGraph.setStatefulOutput(phase)
        case .local:
            // Convert global coordinates to local: ViewTransform.convertGlobal(to: .local, points:)
            let transform = transformAttr.value
            let transformed = phase.map { event -> E in
                var e = event
                if let loc = e.location {
                    var pts = [loc]
                    transform.convertGlobal(to: .local, points: &pts)
                    e.location = pts[0]
                }
                return e
            }
            AttributeGraph.setStatefulOutput(transformed)
        case .named:
            // named coordinate space transform is not implemented yet, so pass through
            AttributeGraph.setStatefulOutput(phase)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Map2Gesture / Map2Phase
// ─────────────────────────────────────────────────────────────────────────────

// Map2Gesture<A,B,C>: merges two child gestures to produce a value of type C
struct Map2Gesture<A, B, C>: GestureModifier {
    typealias BodyValue = A   // Value type of the primary body
    typealias Value = C
    typealias Body = Never

    // secondary gesture factory closure
    var secondaryMakeGesture: (_GestureInputs) -> _GestureOutputs<B>
    var combine: (A, B) -> C

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<A>
    ) -> _GestureOutputs<C> {
        guard let graph = AttributeGraph.current else {
            fatalError("Map2Gesture.makeGesture requires AG context")
        }
        let body1Outputs = body(inputs)
        let self_ = modifier._attribute.value
        let body2Outputs = self_.secondaryMakeGesture(inputs)

        let map2Phase = Map2Phase<A, B, C>(
            source1: body1Outputs.phase,
            source2: body2Outputs.phase,
            combine: self_.combine
        )
        let resultAttr = graph.makeStatefulRule(map2Phase)
        return body1Outputs.withPhase(resultAttr)
    }
}

struct Map2Phase<A, B, C>: StatefulRule {
    typealias Value = GesturePhase<C>

    var source1: Attribute<GesturePhase<A>>
    var source2: Attribute<GesturePhase<B>>
    var combine: (A, B) -> C

    mutating func updateValue() {
        let p1 = source1.value
        let p2 = source2.value
        AttributeGraph.setStatefulOutput(p1.and(p2, value: combine))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - StateContainerGesture / StateContainerPhase
// ─────────────────────────────────────────────────────────────────────────────

// StateContainerGesture<S,E,V>: transform closure (inout S, GesturePhase<E>) -> GesturePhase<V>
// StateContainerPhase<S,E,V>: StatefulRule, ResettableGestureRule
struct StateContainerGesture<S, E: EventType, V>: GestureModifier {
    typealias BodyValue = E
    typealias Value = V
    typealias Body = Never

    var transform: (inout S, GesturePhase<E>) -> GesturePhase<V>
    var initialState: () -> S

    init(
        initialState: @autoclosure @escaping () -> S,
        transform: @escaping (inout S, GesturePhase<E>) -> GesturePhase<V>
    ) {
        self.initialState = initialState
        self.transform = transform
    }

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<V> {
        guard let graph = AttributeGraph.current else {
            fatalError("StateContainerGesture.makeGesture requires AG context")
        }
        let bodyOutputs = body(inputs)
        let self_ = modifier._attribute.value

        let phase = StateContainerPhase<S, E, V>(
            modifierAttr: modifier._attribute,
            childPhaseAttr: bodyOutputs.phase,
            resetSeedAttr: inputs.resetSeed,
            state: self_.initialState(),
            transform: self_.transform
        )
        let resultAttr = graph.makeStatefulRule(phase)
        return bodyOutputs.withPhase(resultAttr)
    }
}

// StateContainerPhase<S,E,V>: StatefulRule, ResettableGestureRule
struct StateContainerPhase<S, E: EventType, V>: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<V>

    let modifierAttr: Attribute<StateContainerGesture<S, E, V>>
    let childPhaseAttr: Attribute<GesturePhase<E>>
    let resetSeedAttr: Attribute<UInt32>

    var state: S
    var lastResetSeed: UInt32
    var transform: (inout S, GesturePhase<E>) -> GesturePhase<V>

    // ResettableGestureRule conformance
    typealias PhaseValue = V
    var resetSeed: UInt32 { resetSeedAttr.value }
    // Value == GesturePhase<V> == GesturePhase<PhaseValue>, so default phaseValue applies.

    init(
        modifierAttr: Attribute<StateContainerGesture<S, E, V>>,
        childPhaseAttr: Attribute<GesturePhase<E>>,
        resetSeedAttr: Attribute<UInt32>,
        state: S,
        transform: @escaping (inout S, GesturePhase<E>) -> GesturePhase<V>
    ) {
        self.modifierAttr = modifierAttr
        self.childPhaseAttr = childPhaseAttr
        self.resetSeedAttr = resetSeedAttr
        self.state = state
        self.lastResetSeed = 0
        self.transform = transform
    }

    mutating func resetPhase() {
        // restore initial state by re-invoking initialState() from modifierAttr
        state = modifierAttr.value.initialState()
        AttributeGraph.setStatefulOutput(GesturePhase<V>.possible(nil))
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        let childPhase = childPhaseAttr.value
        // invoke transform closure: (inout S, GesturePhase<E>) -> GesturePhase<V>
        let newPhase = transform(&state, childPhase)
        AttributeGraph.setStatefulOutput(newPhase)
    }
}
