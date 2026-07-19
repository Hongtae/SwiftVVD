//
//  File: LongPressGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - SingleLongPressGesture

/// Internal gesture type used by LongPressGesture.
/// Implements long-press recognition via an AG modifier chain.
///
/// body chain:
///   storedBody (B, outputs V=Bool) .gated(by: enabler)
///   enabler = EventListener<TappableEvent>().duration(minimum:).endedBy(maximumDistance)
///             -> GesturePhase<Double>
///   result  -> GesturePhase<V=Bool>
struct SingleLongPressGesture<V, B: Gesture>: Gesture where B.Value == V {
    var minimumDuration: Double
    var maximumDistance: CGFloat
    var storedBody: B   // created by LongPressGesture._makeGesture via longPressPhase()

    typealias Value = V

    // Enabler chain: EventListener<TappableEvent>.duration(min:).endedBy(maxDist) -> GesturePhase<Double>
    typealias EnablerBase = ModifierGesture<DurationGesture<MouseEvent>, EventListener<MouseEvent>>
    typealias Enabler     = EndedByWrapper<EnablerBase>
    typealias Body        = ModifierGesture<CombineGesture<V, Double, V>, B>

    var body: Body {
        let maxDist = maximumDistance
        let enabler = EventListener<MouseEvent>()
            .duration(minimum: minimumDuration)
            .endedBy { event, startLoc in
                guard let start = startLoc else { return false }
                let loc = event.location
                return hypot(loc.x - start.x, loc.y - start.y) > maxDist
            }
        return storedBody.gated(by: enabler)
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
            minimumDuration: minimumDuration,
            maximumDistance: _maximumDistance,
            storedBody: gate
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
                modifier: CallbacksGesture(
                    callbacks: PressableGestureCallbacks(pressing: onPressingChanged,
                                                         pressed: action)
                ),
                body: LongPressGesture(minimumDuration: minimumDuration,
                                       maximumDistance: maximumDistance)
            )
        )
    }
}
