//
//  File: GestureTransforms.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - MapGesture / MapPhase

// MapGesture<A,B> creates MapPhase<A,B> to transform active/ended values.
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
        guard let graph = _AGGraph.current else {
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
        _AGGraph.setStatefulOutput(phase.map(transform))
    }
}

// MARK: - DurationGesture / DurationPhase

// DurationGesture<E> creates DurationPhase<E>.
// Output type is GesturePhase<Double> (Double, not E!)
// No E: EventType constraint is required, so DurationGesture<Void> is valid.
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
        guard let graph = _AGGraph.current else {
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

// DurationPhase<E>: StatefulRule that outputs GesturePhase<Double>.
// No E: EventType constraint is required, so DurationPhase<Void> is valid.
struct DurationPhase<E>: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<Double>

    var source: Attribute<GesturePhase<E>>
    var timeAttr: Attribute<Time>
    var minimumDuration: Double
    // DurationPhase does not use seed-based reset because seed never changes.
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
        _AGGraph.setStatefulOutput(GesturePhase<Double>.possible(nil))
    }

    mutating func updateValue() {
        let phase = source.value
        let now = timeAttr.value.seconds

        switch phase {
        case .possible:
            isTracking = false
            startTime = 0
            _AGGraph.setStatefulOutput(GesturePhase<Double>.possible(nil))
        case .active:
            if !isTracking {
                isTracking = true
                startTime = now
            }
            let elapsed = now - startTime
            if elapsed >= minimumDuration {
                _AGGraph.setStatefulOutput(GesturePhase<Double>.active(elapsed))
            } else {
                _AGGraph.setStatefulOutput(GesturePhase<Double>.possible(nil))
            }
        case .ended:
            let elapsed = now - startTime
            if elapsed >= minimumDuration {
                _AGGraph.setStatefulOutput(GesturePhase<Double>.ended(elapsed))
            } else {
                _AGGraph.setStatefulOutput(GesturePhase<Double>.failed)
            }
            isTracking = false
        case .failed:
            isTracking = false
            _AGGraph.setStatefulOutput(GesturePhase<Double>.failed)
        }
    }
}

// MARK: - CoordinateSpaceGesture / CoordinateSpacePhase

// Transforms GesturePhase<E>.location in body outputs to the target coordinateSpace.
// .global passes through, .local converts global to local via ViewTransform,
// and .named preserves the incoming location.
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

        // .global locations are already in global coordinates.
        if cs == .global { return bodyOutputs }

        guard let graph = _AGGraph.current else {
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

// CoordinateSpacePhase<E>: StatefulRule that transforms GesturePhase<E>.location.
struct CoordinateSpacePhase<E: EventType>: StatefulRule {
    typealias Value = GesturePhase<E>

    let source: Attribute<GesturePhase<E>>
    let transformAttr: Attribute<ViewTransform>
    let coordinateSpace: CoordinateSpace

    mutating func updateValue() {
        let phase = source.value
        switch coordinateSpace {
        case .global:
            // Pass through. CoordinateSpaceGesture.makeGesture filters .global early,
            // but guard here for the initial StatefulRule evaluation)
            _AGGraph.setStatefulOutput(phase)
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
            _AGGraph.setStatefulOutput(transformed)
        case .named:
            // Named coordinate space preserves the incoming location.
            _AGGraph.setStatefulOutput(phase)
        }
    }
}

// MARK: - Map2Gesture / Map2Phase

// Map2Gesture<A,B,C> merges two child gestures to produce a value of type C.
struct Map2Gesture<A, B, C>: GestureModifier {
    typealias BodyValue = A   // Value type of the primary body
    typealias Value = C
    typealias Body = Never

    // Stores the secondary gesture factory closure directly.
    var secondaryMakeGesture: (_GestureInputs) -> _GestureOutputs<B>
    var combine: (A, B) -> C

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<A>
    ) -> _GestureOutputs<C> {
        guard let graph = _AGGraph.current else {
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
        _AGGraph.setStatefulOutput(p1.and(p2, value: combine))
    }
}

// MARK: - StateContainerGesture / StateContainerPhase

// StateContainerGesture<S,E,V> stores a transform closure:
// (inout S, GesturePhase<E>) -> GesturePhase<V>
// StateContainerPhase<S,E,V> is a StatefulRule and ResettableGestureRule.
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
        guard let graph = _AGGraph.current else {
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

// StateContainerPhase<S,E,V>: StatefulRule, ResettableGestureRule.
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
        // Re-invoke the initialState closure from the modifier.
        state = modifierAttr.value.initialState()
        _AGGraph.setStatefulOutput(GesturePhase<V>.possible(nil))
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        let childPhase = childPhaseAttr.value
        // Invoke transform closure: (inout S, GesturePhase<E>) -> GesturePhase<V>.
        let newPhase = transform(&state, childPhase)
        _AGGraph.setStatefulOutput(newPhase)
    }
}

// MARK: - EndedByWrapper / EndedByWrapperPhase

// EndedByWrapper forces .failed when condition(event, startLocation) is true
// while the base gesture is active.
// Used by SingleLongPressGesture for _maximumDistance: when the pointer/touch moves
// more than maximumDistance from the initial press location, the gesture is cancelled.
struct EndedByWrapper<Base: Gesture>: Gesture {
    typealias Value = Base.Value
    typealias Body = Never

    var base: Base
    // condition: (currentEvent, startLocation) -> Bool
    // startLocation is tracked by EndedByWrapperPhase across AG evaluations.
    var condition: (TappableEvent, CGPoint?) -> Bool

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Base.Value> {
        guard let graph = _AGGraph.current else {
            fatalError("EndedByWrapper._makeGesture requires AG context")
        }
        let baseOutputs = Base._makeGesture(gesture: gesture[\.base], inputs: inputs)
        let phase = EndedByWrapperPhase<Base.Value>(
            basePhaseAttr: baseOutputs.phase,
            eventsAttr: inputs.events,
            condition: gesture._attribute.value.condition
        )
        let resultAttr = graph.makeStatefulRule(phase)
        return baseOutputs.withPhase(resultAttr)
    }
}

// EndedByWrapperPhase monitors base gesture phase and applies condition.
// Tracks startLocation internally so the condition can compare against initial press position.
struct EndedByWrapperPhase<V>: StatefulRule {
    typealias Value = GesturePhase<V>

    var basePhaseAttr: Attribute<GesturePhase<V>>
    var eventsAttr: Attribute<[EventID: any EventType]>
    var condition: (TappableEvent, CGPoint?) -> Bool
    var startLocation: CGPoint? = nil

    mutating func updateValue() {
        let base = basePhaseAttr.value
        switch base {
        case .possible:
            startLocation = nil
            _AGGraph.setStatefulOutput(base)
        case .failed, .ended:
            startLocation = nil
            _AGGraph.setStatefulOutput(base)
        case .active:
            let events = eventsAttr.value
            for (_, event) in events {
                guard let e = event as? TappableEvent else { continue }
                if startLocation == nil { startLocation = e.location }
                if condition(e, startLocation) {
                    startLocation = nil
                    _AGGraph.setStatefulOutput(GesturePhase<V>.failed)
                    return
                }
            }
            _AGGraph.setStatefulOutput(base)
        }
    }
}

extension Gesture {
    // Convenience wrapper to build EndedByWrapper with a (event, startLocation) condition.
    func endedBy(
        condition: @escaping (TappableEvent, CGPoint?) -> Bool
    ) -> EndedByWrapper<Self> {
        EndedByWrapper(base: self, condition: condition)
    }
}

// MARK: - CombineGesture / CombinePhase

// CombineGesture<A,B,C>: phase-level combiner for two gestures.
// Uses a direct phase closure (GesturePhase<A>, GesturePhase<B>) -> GesturePhase<C>
// so gated(by:) can combine phases without conflating value-level combining.
struct CombineGesture<A, B, C>: GestureModifier {
    typealias BodyValue = A
    typealias Value = C
    typealias Body = Never

    // Factory for the secondary gesture outputs (captures the secondary gesture value).
    var secondaryMakeGesture: (_GestureInputs) -> _GestureOutputs<B>
    // Phase-level combine closure: decides output phase from both inputs.
    var combine: (GesturePhase<A>, GesturePhase<B>) -> GesturePhase<C>

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<A>
    ) -> _GestureOutputs<C> {
        guard let graph = _AGGraph.current else {
            fatalError("CombineGesture.makeGesture requires AG context")
        }
        let primaryOutputs = body(inputs)
        let self_ = modifier._attribute.value
        let secondaryOutputs = self_.secondaryMakeGesture(inputs)

        let phase = CombinePhase<A, B, C>(
            source1: primaryOutputs.phase,
            source2: secondaryOutputs.phase,
            combine: self_.combine
        )
        let resultAttr = graph.makeStatefulRule(phase)
        return primaryOutputs.withPhase(resultAttr)
    }
}

struct CombinePhase<A, B, C>: StatefulRule {
    typealias Value = GesturePhase<C>

    var source1: Attribute<GesturePhase<A>>
    var source2: Attribute<GesturePhase<B>>
    var combine: (GesturePhase<A>, GesturePhase<B>) -> GesturePhase<C>

    mutating func updateValue() {
        _AGGraph.setStatefulOutput(combine(source1.value, source2.value))
    }
}

// MARK: - Gesture builder extensions (4-7)

extension Gesture {

    // 4. Gesture.duration(minimum:maximum:)
    // Gesture.duration(minimum:maximum:) -> ModifierGesture<DurationGesture<Self.Value>, Self>
    // DurationGesture<E> outputs GesturePhase<Double> (elapsed time).
    func duration(
        minimum: Double,
        maximum: Double = .infinity
    ) -> ModifierGesture<DurationGesture<Value>, Self> {
        ModifierGesture(modifier: DurationGesture(minimumDuration: minimum), body: self)
    }

    // 5. Gesture.longPressPhase()
    // Gesture.longPressPhase() -> ModifierGesture<MapGesture<Self.Value, Bool>, Self>
    // .active(e) and .ended(e) become .active(true) and .ended(true).
    // .possible and .failed pass through.
    func longPressPhase() -> ModifierGesture<MapGesture<Value, Bool>, Self> {
        ModifierGesture(modifier: MapGesture(transform: { _ in true }), body: self)
    }

    // 6. Gesture.combined(with:body:)
    // Backed by CombineGesture with a phase-level closure.
    func combined<G: Gesture, V>(
        with other: G,
        body combineFn: @escaping (GesturePhase<Value>, GesturePhase<G.Value>) -> GesturePhase<V>
    ) -> ModifierGesture<CombineGesture<Value, G.Value, V>, Self> {
        let capturedOther = other
        let secondary: (_GestureInputs) -> _GestureOutputs<G.Value> = { inputs in
            guard let graph = _AGGraph.current else {
                fatalError("Gesture.combined secondary requires AG context")
            }
            let attr = graph.makeInput(value: capturedOther)
            return G._makeGesture(gesture: _GraphValue(_attribute: attr), inputs: inputs)
        }
        return ModifierGesture(
            modifier: CombineGesture(secondaryMakeGesture: secondary, combine: combineFn),
            body: self
        )
    }

    // 7. Gesture.gated(by:)
    // gated(by:) -> combined(with:body:) with enabler-gate semantics.
    // Output type = Self.Value (primary gesture value, not the enabler's).
    // Enabler active/ended pass self phase through. possible becomes .possible(nil)
    // and failed becomes .failed.
    func gated<G: Gesture>(
        by enabler: G
    ) -> ModifierGesture<CombineGesture<Value, G.Value, Value>, Self> {
        combined(with: enabler) { selfPhase, enablerPhase in
            switch enablerPhase {
            case .active:   return selfPhase
            case .ended:    return selfPhase
            case .possible: return .possible(nil)
            case .failed:   return .failed
            }
        }
    }
}
