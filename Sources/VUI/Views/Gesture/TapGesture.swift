//
//  File: TapGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private let tapMovementThreshold: CGFloat = {
#if os(iOS)
    45
#else
    5
#endif
}()

// MARK: - SingleTapGesture

struct SingleTapGesture<E: TappableEventType>: Gesture {
    typealias Value = E

    typealias Listener = ModifierGesture<
        DependentGesture<E>,
        ModifierGesture<
            MapGesture<E, E>,
            EventListener<E>
        >
    >

    typealias DurationGate = ModifierGesture<
        Map2Gesture<
            E,
            ModifierGesture<DurationGesture<E>, EventListener<E>>,
            E
        >,
        Listener
    >

    typealias DistanceGate = ModifierGesture<
        Map2Gesture<
            E,
            ModifierGesture<CoordinateSpaceGesture<CGFloat>, DistanceGesture>,
            E
        >,
        DurationGate
    >

    typealias Body = ModifierGesture<EventFilter<E>, DistanceGate>

    var body: Body {
        EventListener<E>()
            .discrete(true)
            .dependency(.failIfActive)
            .gated(by: EventListener<E>().modifier(DurationGesture(
                minimumDuration: 0,
                maximumDuration: 0.75,
                trackFromEventStart: false
            )))
            .gated(by: DistanceGesture(
                minimumDistance: 0,
                maximumDistance: tapMovementThreshold
            ).coordinateSpace(.local))
            .eventFilter(forType: MouseEvent.self) { event in
                event.button == .primary
            }
    }
}

// MARK: - TapGesture

public struct TapGesture: Gesture, PrimitiveGesture {
    public var count: Int
    public init(count: Int = 1) {
        self.count = count
    }

    public typealias Body = Never
    public typealias Value = Void

    struct Child: Rule {
        typealias Value = ModifierGesture<
            RequiredTapCountWriter<TappableEvent>,
            ModifierGesture<
                CategoryGesture<TappableEvent>,
                ModifierGesture<
                    RepeatGesture<TappableEvent>,
                    SingleTapGesture<TappableEvent>
                >
            >
        >

        var _gesture: Attribute<TapGesture>

        var value: Value {
            let count = _gesture.value.count
            guard count > 0 else {
                fatalError("count must be positive")
            }
            return ModifierGesture(
                content: ModifierGesture(
                    content: ModifierGesture(
                        content: SingleTapGesture(),
                        modifier: RepeatGesture(
                            count: count,
                            maximumDelay: 0.35
                        )
                    ),
                    modifier: CategoryGesture(
                        category: .select,
                        includeChildren: true
                    )
                ),
                modifier: RequiredTapCountWriter(count: count)
            )
        }
    }

    struct Phase: Rule {
        var _phase: Attribute<GesturePhase<TappableEvent>>

        var value: GesturePhase<Void> {
            _phase.value.withValue(())
        }
    }

    public static func _makeGesture(
        gesture: _GraphValue<TapGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Void> {
        guard let graph = _AGGraph.current else {
            fatalError("TapGesture._makeGesture requires AG context")
        }
        let child = graph.makeRule(Child(_gesture: gesture._attribute))
        let outputs = Child.Value._makeGesture(
            gesture: _GraphValue(_attribute: child),
            inputs: inputs
        )
        let phase = graph.makeRule(Phase(_phase: outputs.phase))
        return outputs.withPhase(phase)
    }
}

extension View {
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        self.gesture(TapGesture(count: count).onEnded(action), including: .all)
    }
}
