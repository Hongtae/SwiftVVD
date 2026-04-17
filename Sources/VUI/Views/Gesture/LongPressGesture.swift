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
/// Body chain:
///   storedBody (B, outputs V=Bool) .gated(by: enabler)
///   enabler = EventListener<TappableEvent>().duration(minimum:).endedBy(maximumDistance)
///             -> GesturePhase<Double>
///   result -> GesturePhase<V=Bool>
struct SingleLongPressGesture<V, B: Gesture>: Gesture, PubliclyPrimitiveGesture where B.Value == V {
    var minimumDuration: Double
    var maximumDistance: CGFloat
    var storedBody: B   // created by LongPressGesture._makeGesture via longPressPhase()

    typealias Value = V

    // Enabler chain: EventListener<TappableEvent>.duration(min:).endedBy(maxDist) -> GesturePhase<Double>.
    typealias EnablerBase = ModifierGesture<DurationGesture<TappableEvent>, EventListener<TappableEvent>>
    typealias Enabler     = EndedByWrapper<EnablerBase>
    typealias Body        = ModifierGesture<CombineGesture<V, Double, V>, B>

    var body: Body {
        let maxDist = maximumDistance
        let enabler = EventListener<TappableEvent>()
            .duration(minimum: minimumDuration)
            .endedBy { event, startLoc in
                guard let loc = event.location, let start = startLoc else { return false }
                return hypot(loc.x - start.x, loc.y - start.y) > maxDist
            }
        return storedBody.gated(by: enabler)
    }
}

// MARK: - LongPressGesture

// _makeGesture -> SingleLongPressGesture<TappableEvent> wrapped with CategoryGesture(.longPress).

public struct LongPressGesture: Gesture {
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

    public static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Bool> {
        guard let graph = AttributeGraph.current else {
            fatalError("LongPressGesture._makeGesture requires AG context")
        }
        // storedBody = EventListener<TappableEvent>().longPressPhase().
        let self_ = gesture._attribute.value
        typealias GateType = ModifierGesture<MapGesture<TappableEvent, Bool>, EventListener<TappableEvent>>
        let storedBody: GateType = EventListener<TappableEvent>().longPressPhase()
        let inner = SingleLongPressGesture<Bool, GateType>(
            minimumDuration: self_.minimumDuration,
            maximumDistance: self_._maximumDistance,
            storedBody: storedBody
        )
        let categorized = inner.category(.longPress, includeChildren: false)
        typealias Chain = ModifierGesture<CategoryGesture<Bool>, SingleLongPressGesture<Bool, GateType>>
        let attr: Attribute<Chain> = graph.makeInput(value: categorized)
        return Chain._makeGesture(gesture: _GraphValue(_attribute: attr), inputs: inputs)
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
