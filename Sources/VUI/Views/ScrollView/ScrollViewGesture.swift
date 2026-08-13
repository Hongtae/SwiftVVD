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
    typealias CallbackGesture = ModifierGesture<CallbacksGesture<Self>, ScrollGesture>
    typealias ContentGesture = ModifierGesture<
        CoordinateSpaceGesture<ScrollGesture.Value>,
        CallbackGesture
    >

    var proxy: _ScrollViewProxy

    static var initialState: Void { () }
    var name: String? { nil }

    var gestureMask: GestureMask {
        guard proxy.config.isScrollEnabled else {
            return .gesture
        }
        return proxy.config.gestureProvider.gestureMask(proxy: proxy)
    }

    var gesture: ContentGesture {
        let node = proxy.node
        let scrollGesture = proxy.config.gestureProvider.gesture(proxy: proxy)
        let chain = CallbackGesture(
            modifier: CallbacksGesture(callbacks: self),
            body: scrollGesture
        )
        return ContentGesture(
            modifier: CoordinateSpaceGesture(
                coordinateSpace: .named(AnyHashable(ObjectIdentifier(node)))
            ),
            body: chain
        )
    }

    func dispatch(
        phase: GesturePhase<ScrollGesture.Value>,
        state: inout Void
    ) -> (() -> ())? {
        _ = state
        return { proxy._dispatchScrollGesturePhase(phase) }
    }

    func cancel(state: Void) -> (() -> ())? {
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
              (viewGraph.rendererHost as? WindowController)?.gestureGraph != nil else {
            return outputs
        }

        let responderNodes = outputs.preferences.preferences
            .filter { $0.key == ViewRespondersKey.self }
            .map(\.value)
        let responders: Attribute<[ViewResponder]>
        if responderNodes.isEmpty {
            responders = graph.makeInput(value: [])
        } else if responderNodes.count == 1 {
            responders = Attribute<[ViewResponder]>(responderNodes[0])
        } else {
            responders = graph.makeRule {
                var result = ViewRespondersKey.defaultValue
                for identifier in responderNodes {
                    ViewRespondersKey.reduce(value: &result) {
                        Attribute<[ViewResponder]>(identifier).value
                    }
                }
                return result
            }
        }

        let filter = GestureFilter<Self>(
            viewRespondersAttr: responders,
            modifierAttr: modifier._attribute,
            inputs: inputs,
            subgraph: AGSubgraph()
        )
        let responder = graph.makeStatefulRule(filter)
        outputs.preferences.preferences.removeAll { $0.key == ViewRespondersKey.self }
        outputs.preferences.append(ViewRespondersKey.self, node: responder.identifier)
        return outputs
    }
}
