//
//  File: GestureTransforms.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - MapGesture / MapPhase

struct MapGesture<A, B>: GestureModifier {
    typealias BodyValue = A
    typealias Value = B
    typealias Body = Never

    var body: (GesturePhase<A>) -> GesturePhase<B>

    static func _makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<A>
    ) -> _GestureOutputs<B> {
        guard let graph = _AGGraph.current else {
            fatalError("MapGesture.makeGesture requires AG context")
        }
        let bodyOutputs = body(inputs)
        let mapPhase = MapPhase<A, B>(
            _modifier: modifier._attribute,
            _phase: bodyOutputs.phase,
            _resetSeed: inputs.resetSeed,
            lastResetSeed: 0
        )
        let resultAttr = graph.makeStatefulRule(mapPhase)
        return bodyOutputs.withPhase(resultAttr)
    }
}

struct MapPhase<A, B>: StatefulRule, ResettableGestureRule,
    CustomStringConvertible
{
    typealias Value = GesturePhase<B>
    typealias PhaseValue = B

    var _modifier: Attribute<MapGesture<A, B>>
    var _phase: Attribute<GesturePhase<A>>
    var _resetSeed: Attribute<UInt32>
    var lastResetSeed: UInt32 = 0

    var resetSeed: UInt32 { _resetSeed.value }

    mutating func resetPhase() {
        value = .possible(nil)
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }
        value = _modifier.value.body(_phase.value)
    }

    var description: String { "Map → \(B.self)" }
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

    static func _makeGesture(
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

// MARK: - CoordinateSpaceGesture / CoordinateSpaceEvents

struct CoordinateSpaceGesture<E>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    var coordinateSpace: CoordinateSpace

    static func _makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        guard let graph = _AGGraph.current else {
            fatalError("CoordinateSpaceGesture.makeGesture requires AG context")
        }
        var convertedInputs = inputs
        convertedInputs._events = graph.makeRule(CoordinateSpaceEvents(
            _modifier: modifier._attribute,
            _events: inputs.events,
            _position: inputs.position,
            _transform: inputs.transform
        ))
        convertedInputs.options.insert(.preconvertedEventLocations)
        return body(convertedInputs)
    }
}

struct CoordinateSpaceEvents<E>: Rule {
    typealias Value = [EventID: any EventType]

    var _modifier: Attribute<CoordinateSpaceGesture<E>>
    var _events: Attribute<[EventID: any EventType]>
    var _position: Attribute<CGPoint>
    var _transform: Attribute<ViewTransform>

    var value: [EventID: any EventType] {
        let coordinateSpace = _modifier.value.coordinateSpace
        var events = _events.value
        var transform = _transform.value
        transform.appendPosition(_position.value)
        for (id, event) in events {
            guard var spatialEvent = event as? any SpatialEventType else {
                continue
            }
            var points = [spatialEvent.globalLocation]
            transform.convertGlobal(to: coordinateSpace, points: &points)
            spatialEvent.location = points[0]
            events[id] = spatialEvent
        }
        return events
    }
}

extension Gesture {
    func coordinateSpace(
        _ coordinateSpace: CoordinateSpace
    ) -> ModifierGesture<CoordinateSpaceGesture<Value>, Self> {
        ModifierGesture(
            modifier: CoordinateSpaceGesture(coordinateSpace: coordinateSpace),
            body: self
        )
    }
}

// MARK: - Map2Gesture / Map2Phase

struct Map2Gesture<A, B: Gesture, C>: GestureModifier {
    typealias BodyValue = A
    typealias Value = C
    typealias Body = Never

    var content: B
    var body: (GesturePhase<A>, GesturePhase<B.Value>) -> GesturePhase<C>

    static func _makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<A>
    ) -> _GestureOutputs<C> {
        guard let graph = _AGGraph.current else {
            fatalError("Map2Gesture.makeGesture requires AG context")
        }
        let body1Outputs = body(inputs)
        let body2Outputs = B._makeGesture(
            gesture: modifier[\.content],
            inputs: inputs
        )

        let map2Phase = Map2Phase<A, B.Value, C>(
            _body: modifier[\.body]._attribute,
            _phase1: body1Outputs.phase,
            _phase2: body2Outputs.phase,
            _resetSeed: inputs.resetSeed,
            lastResetSeed: 0
        )
        let resultAttr = graph.makeStatefulRule(map2Phase)
        return body1Outputs.withPhase(resultAttr)
    }
}

struct Map2Phase<A, B, C>: StatefulRule, ResettableGestureRule,
    CustomStringConvertible
{
    typealias Value = GesturePhase<C>
    typealias PhaseValue = C

    var _body: Attribute<(GesturePhase<A>, GesturePhase<B>) -> GesturePhase<C>>
    var _phase1: Attribute<GesturePhase<A>>
    var _phase2: Attribute<GesturePhase<B>>
    var _resetSeed: Attribute<UInt32>
    var lastResetSeed: UInt32

    var resetSeed: UInt32 { _resetSeed.value }

    mutating func resetPhase() {
        value = .possible(nil)
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }
        value = _body.value(_phase1.value, _phase2.value)
    }

    var description: String { "Map2 → \(C.self)" }
}

// MARK: - StateContainerGesture / StateContainerPhase

protocol GestureStateProtocol {
    init()
}

struct StateContainerGesture<S: GestureStateProtocol, E, V>: GestureModifier {
    typealias BodyValue = E
    typealias Value = V
    typealias Body = Never

    var body: (inout S, GesturePhase<E>) -> GesturePhase<V>

    static func _makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<V> {
        guard let graph = _AGGraph.current else {
            fatalError("StateContainerGesture.makeGesture requires AG context")
        }
        let bodyOutputs = body(inputs)
        let phase = StateContainerPhase<S, E, V>(
            _modifier: modifier._attribute,
            _childPhase: bodyOutputs.phase,
            _resetSeed: inputs.resetSeed,
            state: S(),
            lastResetSeed: 0
        )
        let resultAttr = graph.makeStatefulRule(phase)
        return bodyOutputs.withPhase(resultAttr)
    }
}

struct StateContainerPhase<S: GestureStateProtocol, E, V>: StatefulRule,
    ResettableGestureRule, CustomStringConvertible
{
    typealias Value = GesturePhase<V>

    var _modifier: Attribute<StateContainerGesture<S, E, V>>
    var _childPhase: Attribute<GesturePhase<E>>
    var _resetSeed: Attribute<UInt32>
    var state: S
    var lastResetSeed: UInt32

    typealias PhaseValue = V
    var resetSeed: UInt32 { _resetSeed.value }

    mutating func resetPhase() {
        state = S()
        value = .possible(nil)
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        value = _modifier.value.body(&state, _childPhase.value)
    }

    var description: String { "State → \(V.self)" }
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
    var condition: (MouseEvent, CGPoint?) -> Bool

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
    var condition: (MouseEvent, CGPoint?) -> Bool
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
                guard let e = event as? MouseEvent else { continue }
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
        condition: @escaping (MouseEvent, CGPoint?) -> Bool
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

    static func _makeGesture(
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
        ModifierGesture(modifier: MapGesture(body: { phase in
            phase.map { _ in true }
        }), body: self)
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
