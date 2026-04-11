//
//  File: GestureModifiers.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation


// MARK: - MapGesture / MapPhase

// MapGesture<A,B>._makeGesture creates MapPhase<A,B>: StatefulRule
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

// MARK: - DurationGesture / DurationPhase

// DurationGesture<E>._makeGesture -> DurationPhase<E>: StatefulRule
// output type is GesturePhase<Double>, not E
// no E: EventType constraint, so DurationGesture<Void> is valid in SingleLongPressGesture.body chain
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
// no E: EventType constraint, so DurationPhase<Void> is valid
struct DurationPhase<E>: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<Double>

    var source: Attribute<GesturePhase<E>>
    var timeAttr: Attribute<Time>
    var minimumDuration: Double
    // dummy reset seed because DurationPhase does not use seed-based reset
    var resetSeedAttr: Attribute<UInt32> { Attribute(AGAttribute(rawValue: 0)) }
    var lastResetSeed: UInt32 = 0
    var startTime: Double = 0
    var isTracking: Bool = false

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

// MARK: - DependentGesture / DependentPhase

// DependentGesture<E>._makeGesture -> DependentPhase<E>: Rule
// DependentPhase reads GestureDependency.Key preference to determine priority
struct DependentGesture<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        // GestureDependency handling is not implemented because ExclusiveGesture handles it separately
        // DependentGesture acts as pass-through
        body(inputs)
    }
}

// MARK: - EventFilter / EventFilterEvents

// EventFilter<E>._makeGesture -> EventFilterEvents<E>: Rule + filtered events attr
struct EventFilter<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    // EventFilter filters events before body input
    // currently pass-through without a predicate because type filtering happens in EventListenerPhase
    var predicate: ((E) -> Bool)?

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        // predicate filtering happens at EventListenerPhase level, so pass through
        body(inputs)
    }
}

// MARK: - CoordinateSpaceGesture

// CoordinateSpaceGesture<E>._makeGesture converts coordinates using the animatedPosition pattern
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
        // coordinate transform logic is not implemented, so pass through
        // EventListenerPhase already handles coordinate conversion through positionAttr/transformAttr
        body(inputs)
    }
}

// MARK: - Map2Gesture / Map2Phase

// Map2Gesture<A,B,C>: combines two child gestures into a C value
struct Map2Gesture<A, B, C>: GestureModifier {
    typealias BodyValue = A   // primary body value type
    typealias Value = C
    typealias Body = Never

    // secondary gesture accessed through PointerOffset pattern
    // body2 stores the secondary gesture directly
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

// MARK: - StateContainerGesture / StateContainerPhase

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
        // restore initial state through the transform closure's reset function (PAC 0xaf83)
        // call modifierAttr's initialState() closure again
        state = modifierAttr.value.initialState()
        AttributeGraph.setStatefulOutput(GesturePhase<V>.possible(nil))
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        let childPhase = childPhaseAttr.value
        // call transform closure: (inout S, GesturePhase<E>) -> GesturePhase<V>
        let newPhase = transform(&state, childPhase)
        AttributeGraph.setStatefulOutput(newPhase)
    }
}

// MARK: - RepeatGesture / RepeatResetSeed / RepeatPhase

// RepeatGesture<E>: handles multiple taps
// RepeatResetSeed: Rule -> Value=UInt32 by summing two attrs
// RepeatPhase<E>: StatefulRule counts multiple taps

struct RepeatGesture<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    var count: Int
    var maximumDelay: Double  // maximum allowed delay between taps

    init(count: Int, maximumDelay: Double = 0.5) {
        self.count = count
        self.maximumDelay = maximumDelay
    }

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        guard let graph = AttributeGraph.current else {
            fatalError("RepeatGesture.makeGesture requires AG context")
        }
        let bodyOutputs = body(inputs)
        let self_ = modifier._attribute.value

        // RepeatResetSeed sums global resetSeed and local tap-count modifier attr
        let tapCountAttr: Attribute<UInt32> = graph.makeInput(value: 0)
        let repeatResetSeed = RepeatResetSeed(
            globalSeedAttr: inputs.resetSeed,
            localCountAttr: tapCountAttr
        )
        let seedAttr = graph.makeRule { repeatResetSeed.value }

        let repeatPhase = RepeatPhase<E>(
            childPhaseAttr: bodyOutputs.phase,
            timeAttr: inputs.time,
            resetSeedAttr: seedAttr,
            tapCountAttr: tapCountAttr,
            requiredCount: self_.count,
            maximumDelay: self_.maximumDelay
        )
        let resultAttr = graph.makeStatefulRule(repeatPhase)
        return bodyOutputs.withPhase(resultAttr)
    }
}

// RepeatResetSeed: Rule -> Value=UInt32 by summing globalSeed and localCount
struct RepeatResetSeed {
    var globalSeedAttr: Attribute<UInt32>
    var localCountAttr: Attribute<UInt32>

    var value: UInt32 {
        globalSeedAttr.value &+ localCountAttr.value
    }
}

struct RepeatPhase<E: EventType>: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<E>

    let childPhaseAttr: Attribute<GesturePhase<E>>
    let timeAttr: Attribute<Time>
    let resetSeedAttr: Attribute<UInt32>
    var tapCountAttr: Attribute<UInt32>

    let requiredCount: Int
    let maximumDelay: Double

    var lastResetSeed: UInt32 = 0
    var lastTapTime: Double = 0        // last tap completion time
    var isFirstTap: Bool = true        // true means waiting for the first tap
    var completedTaps: Int = 0
    var lastActivePhase: GesturePhase<E> = .possible(nil)

    mutating func resetPhase() {
        lastTapTime = 0
        isFirstTap = true
        completedTaps = 0
        AttributeGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        let now = timeAttr.value.seconds
        let childPhase = childPhaseAttr.value

        // check timer expiration after maximumDelay since previous tap
        if !isFirstTap && lastTapTime > 0 && (now - lastTapTime) > maximumDelay {
            // tap interval exceeded, fail
            isFirstTap = true
            completedTaps = 0
            AttributeGraph.setStatefulOutput(GesturePhase<E>.failed)
            return
        }

        switch childPhase {
        case .possible:
            if completedTaps == 0 {
                AttributeGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
            }
            // keep possible while tap is in progress
        case .active(let v):
            lastActivePhase = childPhase
            if completedTaps == 0 {
                isFirstTap = false
            }
            // if count == 1, become active immediately
            if requiredCount == 1 {
                AttributeGraph.setStatefulOutput(GesturePhase<E>.active(v))
            } else {
                AttributeGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
            }
        case .ended(let v):
            completedTaps += 1
            lastTapTime = now

            if completedTaps >= requiredCount {
                // required tap count reached, succeed
                completedTaps = 0
                isFirstTap = true
                // increment tapCountAttr to signal RepeatResetSeed
                let newCount = tapCountAttr.value &+ 1
                tapCountAttr.setValue(newCount)
                AttributeGraph.setStatefulOutput(GesturePhase<E>.ended(v))
            } else {
                // more taps needed, keep possible
                AttributeGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
            }
        case .failed:
            completedTaps = 0
            isFirstTap = true
            AttributeGraph.setStatefulOutput(GesturePhase<E>.failed)
        }
    }
}

// MARK: - CategoryGesture

// CategoryGesture<E>: calls body directly, then injects GestureCategory.Key preference
struct CategoryGesture<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    var category: GestureCategory

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        // inject GestureCategory.Key preference into outputs
        // preference injection will be implemented later, currently pass-through
        body(inputs)
    }
}

// MARK: - RequiredTapCountKey / RequiredTapCountWriter

// RequiredTapCountKey: PreferenceKey propagates required tap count through the view tree
enum RequiredTapCountKey: PreferenceKey {
    typealias Value = Int?
    static var defaultValue: Int? { nil }
    static func reduce(value: inout Int?, nextValue: () -> Int?) {
        value = value ?? nextValue()
    }
}

// RequiredTapCountWriter<E>._makeGesture records RequiredTapCountKey preference
struct RequiredTapCountWriter<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    var count: Int

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        guard let graph = AttributeGraph.current else {
            fatalError("RequiredTapCountWriter.makeGesture requires AG context")
        }
        var bodyOutputs = body(inputs)

        let countAttr: Attribute<Int?> = graph.makeInput(value: modifier._attribute.value.count)
        bodyOutputs.appendPreference(key: RequiredTapCountKey.self, value: countAttr)
        return bodyOutputs
    }
}
