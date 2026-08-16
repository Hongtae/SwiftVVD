//
//  File: LongPressGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - SingleLongPressGesture

struct SingleLongPressGesture<V, B: Gesture>: Gesture where B.Value == V {
    var base: B
    var minimumDuration: Double
    var maximumDistance: CGFloat

    typealias Value = V

    typealias Duration = ModifierGesture<
        DurationGesture<TappableEvent>,
        EventListener<TappableEvent>
    >
    typealias Distance = ModifierGesture<
        CoordinateSpaceGesture<CGFloat>,
        DistanceGesture
    >
    typealias Enabler = EndedByWrapper<Duration, Distance>
    typealias Gated = ModifierGesture<Map2Gesture<V, Enabler, V>, B>
    typealias Filtered = ModifierGesture<EventFilter<V>, Gated>
    typealias Body = ModifierGesture<DependentGesture<V>, Filtered>

    var body: Body {
        let enabler = EndedByWrapper(
            base: EventListener<TappableEvent>().duration(
                minimum: minimumDuration,
                maximum: .infinity
            ),
            condition: DistanceGesture(
                maximumDistance: maximumDistance
            ).coordinateSpace(.local)
        )
        return base
            .gated(by: enabler)
            .eventFilter(forType: MouseEvent.self) { event in
                event.button == .primary
            }
            .dependency(.pausedUntilFailed)
    }
}

// MARK: - LongPressGesture

// LongPressGesture builds SingleLongPressGesture and wraps it with CategoryGesture(.longPress).

public struct LongPressGesture: Gesture, PubliclyPrimitiveGesture {
    public var minimumDuration: Double
    public var maximumDistance: CGFloat {
        get { _maximumDistance }
        set { _maximumDistance = newValue }
    }

    var _maximumDistance: CGFloat

    public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration
        self._maximumDistance = maximumDistance
    }

    public typealias Value = Bool
    public typealias Body = Never

    typealias Gate = ModifierGesture<MapGesture<TappableEvent, Bool>, EventListener<TappableEvent>>
    typealias InternalBody = ModifierGesture<
        CategoryGesture<Bool>,
        SingleLongPressGesture<Bool, Gate>
    >

    var internalBody: InternalBody {
        let gate: Gate = EventListener<TappableEvent>().longPressPhase()
        return SingleLongPressGesture(
            base: gate,
            minimumDuration: minimumDuration,
            maximumDistance: _maximumDistance
        )
        .category(.longPress, includeChildren: false)
    }

    public static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Bool> {
        makeGesture(gesture: gesture, inputs: inputs)
    }
}

extension View {
    public func onLongPressGesture(
        minimumDuration: Double = 0.5,
        maximumDistance: CGFloat = 10,
        perform action: @escaping () -> Void,
        onPressingChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        self.gesture(
            ModifierGesture(
                content: LongPressGesture(minimumDuration: minimumDuration,
                                          maximumDistance: maximumDistance),
                modifier: CallbacksGesture(
                    callbacks: PressableGestureCallbacks(pressing: onPressingChanged,
                                                         pressed: action)
                )
            )
        )
    }
}
