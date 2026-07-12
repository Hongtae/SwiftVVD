//
//  File: ScrollViewGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct ScrollGesture: Gesture {
    enum Value: Equatable {
        case pan(PanGesture.Value)
        case wheel(CGSize)
    }

    var minimumDistance: CGFloat
    var allowedDirections: _EventDirections

    typealias Body = ModifierGesture<
        CombineGesture<PanGesture.Value, WheelEvent, Value>,
        PanGesture
    >

    var body: Body {
        PanGesture(
            minimumDistance: minimumDistance,
            allowedDirections: allowedDirections
        ).combined(with: EventListener<WheelEvent>()) { panPhase, wheelPhase in
            Self.selectPhase(pan: panPhase, wheel: wheelPhase)
        }
    }

    static func selectPhase(
        pan: GesturePhase<PanGesture.Value>,
        wheel: GesturePhase<WheelEvent>
    ) -> GesturePhase<Value> {
        switch wheel {
        case .possible(let wheel):
            if let wheel {
                return .possible(.wheel(wheelTranslation(wheel)))
            }
            return pan.map(Value.pan)
        case .active(let wheel):
            return .active(.wheel(wheelTranslation(wheel)))
        case .ended(let wheel):
            return .ended(.wheel(wheelTranslation(wheel)))
        case .failed:
            return pan.map(Value.pan)
        }
    }

    private static func wheelTranslation(_ event: WheelEvent) -> CGSize {
        CGSize(width: 0, height: -event.offset)
    }
}

extension ScrollGesture: DynamicGestureEventTypeAccepting {
    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == ScrollEvent.self || eventType == WheelEvent.self
    }
}

extension _ScrollViewGestureProvider {
    func gesture(proxy: _ScrollViewProxy) -> ScrollGesture {
        ScrollGesture(
            minimumDistance: proxy.isMostlyDecelerating ? 0 : 10,
            allowedDirections: scrollableDirections(proxy: proxy)
        )
    }
}

struct ScrollViewGesture: GestureViewModifier, GestureCallbacks {
    typealias Combiner = DefaultGestureCombiner
    typealias Value = ScrollGesture.Value
    typealias StateType = Void
    typealias Body = Never

    var proxy: _ScrollViewProxy

    static var initialState: Void { () }

    var gestureMask: GestureMask {
        guard proxy.config.isScrollEnabled else {
            return .gesture
        }
        return proxy.config.gestureProvider.gestureMask(proxy: proxy)
    }

    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == ScrollEvent.self || eventType == WheelEvent.self
    }

    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        Self.acceptsEventType(eventType)
    }

    static func _makeSessionGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<()> {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollViewGesture._makeSessionGesture requires AG context")
        }
        let current = modifier._attribute.value
        guard let node = current.proxy.node else {
            fatalError("ScrollViewGesture requires a live ScrollViewNode")
        }
        let scrollGesture = current.proxy.config.gestureProvider.gesture(proxy: current.proxy)
        typealias Chain = ModifierGesture<CallbacksGesture<ScrollViewGesture>, ScrollGesture>
        let chain = Chain(
            modifier: CallbacksGesture(callbacks: current),
            body: scrollGesture
        )
        typealias CoordinateChain = ModifierGesture<
            CoordinateSpaceGesture<ScrollGesture.Value>,
            Chain
        >
        let coordinateChain = CoordinateChain(
            modifier: CoordinateSpaceGesture(
                coordinateSpace: .named(AnyHashable(ObjectIdentifier(node)))
            ),
            body: chain
        )
        let chainAttribute = graph.makeInput(value: coordinateChain)
        let outputs = CoordinateChain._makeGesture(
            gesture: _GraphValue(_attribute: chainAttribute),
            inputs: inputs
        )
        let mapped: Attribute<GesturePhase<()>> = graph.makeRule {
            outputs.phase.value.map { _ in () }
        }
        return outputs.withPhase(mapped)
    }

    func dispatch(
        phase: GesturePhase<ScrollGesture.Value>,
        state: inout Void
    ) -> (() -> ())? {
        _ = state
        guard proxy.node != nil else { return nil }
        return { proxy._dispatchScrollGesturePhase(phase) }
    }

    func cancel(state: Void) -> (() -> ())? {
        guard proxy.node != nil else { return nil }
        return { proxy._dispatchScrollGesturePhase(.failed) }
    }

    static func makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollViewGesture.makeView requires AG context")
        }

        var outputs = body(_Graph(), inputs)
        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else {
            return outputs
        }
        guard let viewGraph = _AGGraphContext.current?.context as? ViewGraph,
              viewGraph.rendererHost?.gestureGraph != nil else {
            return outputs
        }

        let responderNodes = outputs.preferences.preferences
            .filter { $0.key == ViewRespondersKey.self }
            .map(\.value)
        let responders: Attribute<[any ViewResponder]>
        if responderNodes.isEmpty {
            responders = graph.makeInput(value: [])
        } else if responderNodes.count == 1 {
            responders = Attribute<[any ViewResponder]>(responderNodes[0])
        } else {
            responders = graph.makeRule {
                var result = ViewRespondersKey.defaultValue
                for identifier in responderNodes {
                    ViewRespondersKey.reduce(value: &result) {
                        Attribute<[any ViewResponder]>(identifier).value
                    }
                }
                return result
            }
        }

        let filter = GestureFilter<Self>(
            modifierAttr: modifier._attribute,
            innerRespondersAttr: responders,
            viewInputs: inputs,
            exclusionPolicy: Combiner.exclusionPolicy,
            subgraph: AGSubgraph()
        )
        let responder = graph.makeStatefulRule(filter)
        outputs.preferences.preferences.removeAll { $0.key == ViewRespondersKey.self }
        outputs.preferences.append(ViewRespondersKey.self, node: responder.identifier)
        return outputs
    }
}
