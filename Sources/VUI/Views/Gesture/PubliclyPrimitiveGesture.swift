//
//  File: PubliclyPrimitiveGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - PubliclyPrimitiveGesture Protocol

/// Marker protocol for gesture types that implement recognition via `body` computed property.
///
/// Implementation: the default Gesture extension where Self.Value == Self.Body.Value
/// handles body-based _makeGesture through a gesture[\.body] keypath-derived node.
/// GestureBodyAccessor StaticBody/DynamicBody is simplified.
protocol PubliclyPrimitiveGesture: Gesture {}

// MARK: - TappableEventType

/// Protocol for tap/click event types that carry a button identifier.
protocol TappableEventType: EventType {
    var buttonID: Int { get }
}

extension TappableEvent: TappableEventType {}

// MARK: - SingleTapGesture

/// Internal gesture type used by TapGesture.
/// Implements single/multi-tap recognition via an AG modifier chain.
///
/// body chain (inner -> outer):
///   EventListener<E>
///   -> CategoryGesture<E>         (GestureCategory.select)
///   -> RepeatGesture<E>           (requires count taps)
///   -> RequiredTapCountWriter<E>  (records RequiredTapCountKey preference)
struct SingleTapGesture<E: EventType>: Gesture, PubliclyPrimitiveGesture {
    var count: Int

    typealias Value = E

    typealias Body = ModifierGesture<
        RequiredTapCountWriter<E>,
        ModifierGesture<
            RepeatGesture<E>,
            ModifierGesture<
                CategoryGesture<E>,
                EventListener<E>
            >
        >
    >

    var body: Body {
        ModifierGesture(
            modifier: RequiredTapCountWriter(count: count),
            body: ModifierGesture(
                modifier: RepeatGesture(count: count),
                body: ModifierGesture(
                    modifier: CategoryGesture(category: .select),
                    body: EventListener<E>()
                )
            )
        )
    }
}

// MARK: - SpatialDragGesture

/// Internal gesture type used by DragGesture.
/// Implements drag recognition via an AG modifier chain.
///
/// Implementation: GestureGraph converts platform MouseEvent to TappableEvent,
/// so EventListener<TappableEvent> is used instead.
///
/// body chain (inner -> outer):
///   EventListener<TappableEvent>
///   -> EventFilter<TappableEvent>              (button filtering)
///   -> CoordinateSpaceGesture<TappableEvent>   (coordinate-space conversion)
///   -> StateContainerGesture<InternalState, TappableEvent, DragGesture.Value>
struct SpatialDragGesture: Gesture, PubliclyPrimitiveGesture {
    var minimumDistance: CGFloat
    var coordinateSpace: CoordinateSpace

    typealias Value = DragGesture.Value

    /// Intermediate state during drag recognition.
    struct InternalState {
        var startLocation: CGPoint = .zero
        var currentLocation: CGPoint = .zero
        var startTime: Date = Date()
        var velocity: _Velocity<CGSize> = _Velocity(valuePerSecond: .zero)
        var isDragging: Bool = false
    }

    typealias Body = ModifierGesture<
        StateContainerGesture<InternalState, TappableEvent, DragGesture.Value>,
        ModifierGesture<
            CoordinateSpaceGesture<TappableEvent>,
            ModifierGesture<
                EventFilter<TappableEvent>,
                EventListener<TappableEvent>
            >
        >
    >

    var body: Body {
        let minDist = minimumDistance
        let cs = coordinateSpace
        let transform: (inout InternalState, GesturePhase<TappableEvent>) -> GesturePhase<DragGesture.Value> = {
            SpatialDragGesture.applyPhase(minimumDistance: minDist, state: &$0, phase: $1)
        }
        return ModifierGesture(
            modifier: StateContainerGesture(
                initialState: InternalState(),
                transform: transform
            ),
            body: ModifierGesture(
                modifier: CoordinateSpaceGesture(coordinateSpace: cs),
                body: ModifierGesture(
                    modifier: EventFilter(),
                    body: EventListener<TappableEvent>()
                )
            )
        )
    }

    /// StateContainerGesture.transform closure.
    static func applyPhase(
        minimumDistance: CGFloat,
        state: inout InternalState,
        phase: GesturePhase<TappableEvent>
    ) -> GesturePhase<DragGesture.Value> {
        switch phase {
        case .possible:
            return .possible(nil)
        case .active(let event):
            guard let location = event.location else { return .possible(nil) }
            if !state.isDragging && state.startLocation == .zero {
                state.startLocation = location
                state.startTime = Date()
            }
            let prev = state.currentLocation
            state.currentLocation = location
            if prev != .zero {
                let delta = CGSize(width: location.x - prev.x, height: location.y - prev.y)
                state.velocity = _Velocity(valuePerSecond: delta)
            }
            let dist = hypot(location.x - state.startLocation.x, location.y - state.startLocation.y)
            guard dist >= minimumDistance else { return .possible(nil) }
            state.isDragging = true
            let value = DragGesture.Value(
                time: state.startTime,
                location: location,
                startLocation: state.startLocation,
                _velocity: state.velocity
            )
            return .active(value)
        case .ended(let event):
            guard let location = event.location else { return .failed }
            let value = DragGesture.Value(
                time: state.startTime,
                location: location,
                startLocation: state.startLocation,
                _velocity: state.velocity
            )
            return .ended(value)
        case .failed:
            return .failed
        }
    }
}

// MARK: - SingleLongPressGesture

/// Internal gesture type used by LongPressGesture.
/// Implements long-press recognition via an AG modifier chain.
///
/// body chain (inner -> outer):
///   EventListener<E>
///   -> MapGesture<E, Void>      (discards event value)
///   -> DurationGesture<Void>    (GesturePhase<Void> -> GesturePhase<Double>, elapsed time)
///   -> MapGesture<Double, Bool> (elapsed >= minimumDuration -> true)
struct SingleLongPressGesture<E: EventType>: Gesture, PubliclyPrimitiveGesture {
    var minimumDuration: Double

    typealias Value = Bool

    typealias Body = ModifierGesture<
        MapGesture<Double, Bool>,
        ModifierGesture<
            DurationGesture<Void>,
            ModifierGesture<
                MapGesture<E, Void>,
                EventListener<E>
            >
        >
    >

    var body: Body {
        let minDur = minimumDuration
        return ModifierGesture(
            modifier: MapGesture(transform: { elapsed in elapsed >= minDur }),
            body: ModifierGesture(
                modifier: DurationGesture(minimumDuration: minimumDuration),
                body: ModifierGesture(
                    modifier: MapGesture(transform: { (_: E) in () }),
                    body: EventListener<E>()
                )
            )
        )
    }
}
