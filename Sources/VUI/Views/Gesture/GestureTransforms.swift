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

extension Gesture {
    func discrete(
        _ isDiscrete: Bool = true
    ) -> ModifierGesture<MapGesture<Value, Value>, Self> {
        modifier(MapGesture { phase in
            guard isDiscrete, case .active(let value) = phase else {
                return phase
            }
            return .possible(value)
        })
    }
}

// MARK: - DurationGesture / DurationPhase

struct DurationGesture<E>: GestureModifier {
    typealias BodyValue = E
    typealias Value = Double
    typealias Body = Never

    var minimumDuration: Double
    var maximumDuration: Double
    var trackFromEventStart: Bool

    init(
        minimumDuration: Double = 0,
        maximumDuration: Double = .infinity,
        trackFromEventStart: Bool = false
    ) {
        self.minimumDuration = minimumDuration
        self.maximumDuration = maximumDuration
        self.trackFromEventStart = trackFromEventStart
    }

    static func _makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<Double> {
        guard let graph = _AGGraph.current else {
            fatalError("DurationGesture.makeGesture requires AG context")
        }
        let outputs = body(inputs)
        let phase = graph.makeStatefulRule(DurationPhase<E>(
            _modifier: modifier._attribute,
            _childPhase: outputs.phase,
            _time: inputs.time,
            _resetSeed: inputs.resetSeed,
            useGestureGraph: inputs.options.contains(.gestureGraph),
            start: nil,
            lastResetSeed: 0
        ))
        return outputs.withPhase(phase)
    }
}

struct DurationPhase<E>: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<Double>
    typealias PhaseValue = Double

    var _modifier: Attribute<DurationGesture<E>>
    var _childPhase: Attribute<GesturePhase<E>>
    var _time: Attribute<Time>
    var _resetSeed: Attribute<UInt32>
    var useGestureGraph: Bool
    var start: Time?
    var lastResetSeed: UInt32

    var resetSeed: UInt32 { _resetSeed.value }

    mutating func resetPhase() {
        start = nil
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        let childPhase = _childPhase.value
        let modifier = _modifier.value
        let time = _time.value

        if start == nil &&
            (childPhase.isActive || modifier.trackFromEventStart) {
            start = time
        }

        let elapsed = start.map { time.seconds - $0.seconds } ?? 0
        let output: GesturePhase<Double>
        switch childPhase {
        case .possible, .active:
            if elapsed < modifier.minimumDuration {
                output = .possible(elapsed)
            } else if elapsed < modifier.maximumDuration {
                output = .active(elapsed)
            } else {
                output = .failed
            }
        case .ended:
            if elapsed >= modifier.minimumDuration &&
                elapsed < modifier.maximumDuration {
                output = .ended(elapsed)
            } else {
                output = .failed
            }
        case .failed:
            output = .failed
        }
        _AGGraph.setStatefulOutput(output)

        guard !output.isTerminal, let start else { return }
        let boundary = elapsed < modifier.minimumDuration
            ? modifier.minimumDuration
            : modifier.maximumDuration
        let deadline = start + boundary
        if useGestureGraph {
            let graph = GraphHost.currentHost as! GestureGraph
            graph.scheduleGestureUpdate(at: deadline)
        } else {
            let graph = GraphHost.currentHost as! ViewGraph
            graph.nextUpdate.gestures.at(deadline)
        }
    }
}

// MARK: - DistanceGesture

struct DistanceGesture: Gesture {
    var minimumDistance: CGFloat
    var maximumDistance: CGFloat

    init(
        minimumDistance: CGFloat = 0,
        maximumDistance: CGFloat = .infinity
    ) {
        self.minimumDistance = minimumDistance
        self.maximumDistance = maximumDistance
    }

    struct StateType: GestureStateProtocol {
        var start: CGPoint?
        var maxDistance: CGFloat

        init() {
            start = nil
            maxDistance = 0
        }
    }

    typealias Body = ModifierGesture<
        StateContainerGesture<StateType, SpatialEvent, CGFloat>,
        EventListener<SpatialEvent>
    >

    var body: Body {
        let minimumDistance = minimumDistance
        let maximumDistance = maximumDistance
        return EventListener<SpatialEvent>().modifier(
            StateContainerGesture { state, phase in
                let event: SpatialEvent
                switch phase {
                case .possible(let value):
                    guard let value else { return .possible(nil) }
                    event = value
                case .active(let value), .ended(let value):
                    event = value
                case .failed:
                    return .failed
                }

                if let start = state.start {
                    state.maxDistance = max(
                        state.maxDistance,
                        hypot(
                            start.x - event.location.x,
                            start.y - event.location.y
                        )
                    )
                } else {
                    state.start = event.location
                    state.maxDistance = 0
                }

                let distance = state.maxDistance
                switch phase {
                case .possible:
                    return .possible(distance)
                case .active:
                    guard distance <= maximumDistance else {
                        return .failed
                    }
                    if distance >= minimumDistance {
                        return .active(distance)
                    }
                    return .possible(distance)
                case .ended:
                    guard distance >= minimumDistance,
                          distance < maximumDistance else {
                        return .failed
                    }
                    return .ended(distance)
                case .failed:
                    return .failed
                }
            }
        )
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
            content: self,
            modifier: CoordinateSpaceGesture(coordinateSpace: coordinateSpace)
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
        var outputs = _GestureOutputs<C>(phase: resultAttr)
        outputs.preferences = PreferencesOutputs.merge(
            [body1Outputs.preferences, body2Outputs.preferences],
            in: graph
        )
        return outputs
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

// MARK: - EndedByWrapper

struct EndedByWrapper<Base: Gesture, Condition: Gesture>: PrimitiveGesture {
    typealias Value = Base.Value
    typealias Body = Never

    var base: Base
    var condition: Condition

    struct Child: Rule {
        typealias Value = ModifierGesture<
            Map2Gesture<Base.Value, Condition, Base.Value>,
            Base
        >

        var _wrapper: Attribute<EndedByWrapper>
        var hasChangedCallbacks: Bool

        var value: Value {
            let wrapper = _wrapper.value
            return wrapper.base.ended(
                by: wrapper.condition,
                advanceImmediately: hasChangedCallbacks
            )
        }
    }

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Base.Value> {
        guard let graph = _AGGraph.current else {
            fatalError("EndedByWrapper._makeGesture requires AG context")
        }
        let child = graph.makeRule(Child(
            _wrapper: gesture._attribute,
            hasChangedCallbacks: inputs.options.contains(.hasChangedCallbacks)
        ))
        return Child.Value._makeGesture(
            gesture: _GraphValue(_attribute: child),
            inputs: inputs
        )
    }
}

extension Gesture {
    func ended<Condition: Gesture>(
        by condition: Condition,
        advanceImmediately: Bool = false
    ) -> ModifierGesture<Map2Gesture<Value, Condition, Value>, Self> {
        combined(with: condition) { phase, conditionPhase in
            switch conditionPhase {
            case .active, .ended:
                return phase
            case .failed:
                return .failed
            case .possible:
                let pausesWhileConditionIsPossible: Bool
#if os(iOS)
                pausesWhileConditionIsPossible = GestureContainerFeature.isEnabled
#else
                pausesWhileConditionIsPossible = isLinkedOnOrAfter(.v6)
#endif
                if !advanceImmediately && pausesWhileConditionIsPossible {
                    return phase.paused()
                }
                if case .ended(let value) = phase {
                    return .active(value)
                }
                return .failed
            }
        }
    }
}

// MARK: - Gesture builder extensions (4-7)

extension Gesture {

    func modifier<M: GestureModifier>(
        _ modifier: M
    ) -> ModifierGesture<M, Self> where M.BodyValue == Value {
        ModifierGesture(content: self, modifier: modifier)
    }

    // 4. Gesture.duration(minimum:maximum:)
    // Gesture.duration(minimum:maximum:) -> ModifierGesture<DurationGesture<Self.Value>, Self>
    // DurationGesture<E> outputs GesturePhase<Double> (elapsed time).
    func duration(
        minimum: Double,
        maximum: Double = .infinity
    ) -> ModifierGesture<DurationGesture<Value>, Self> {
        ModifierGesture(
            content: self,
            modifier: DurationGesture(
                minimumDuration: minimum,
                maximumDuration: maximum
            )
        )
    }

    // 5. Gesture.longPressPhase()
    // Gesture.longPressPhase() -> ModifierGesture<MapGesture<Self.Value, Bool>, Self>
    // .active(e) and .ended(e) become .active(true) and .ended(true).
    // .possible and .failed pass through.
    func longPressPhase() -> ModifierGesture<MapGesture<Value, Bool>, Self> {
        ModifierGesture(
            content: self,
            modifier: MapGesture(body: { phase in
                phase.map { _ in true }
            })
        )
    }

    func combined<G: Gesture, V>(
        with other: G,
        body: @escaping (
            GesturePhase<Value>,
            GesturePhase<G.Value>
        ) -> GesturePhase<V>
    ) -> ModifierGesture<Map2Gesture<Value, G, V>, Self> {
        modifier(
            Map2Gesture(content: other, body: body)
        )
    }

    func gated<G: Gesture>(
        by enabler: G
    ) -> ModifierGesture<Map2Gesture<Value, G, Value>, Self> {
        combined(with: enabler) { phase, enablerPhase in
            if case .failed = enablerPhase {
                return .failed
            }
            return phase
        }
    }
}
