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

/// Input chain for the logical hosting scroll view. Pointer/touch scrolling
/// retains the pan recognizer, while discrete wheels bypass its distance gate.
struct SystemScrollGesture: Gesture {
    typealias Value = ScrollGesture.Value
    typealias Body = ModifierGesture<
        CombineGesture<PanGesture.Value, SystemWheelEvent, Value>,
        PanGesture
    >

    var minimumDistance: CGFloat
    var allowedDirections: _EventDirections

    var body: Body {
        PanGesture(
            minimumDistance: minimumDistance,
            allowedDirections: allowedDirections
        ).combined(with: EventListener<SystemWheelEvent>()) { panPhase, wheelPhase in
            switch wheelPhase {
            case .possible(let event):
                if let event {
                    return .possible(.wheel(event.delta))
                }
                return panPhase.map(Value.pan)
            case .active(let event):
                return .active(.wheel(event.delta))
            case .ended(let event):
                return .ended(.wheel(event.delta))
            case .failed:
                return panPhase.map(Value.pan)
            }
        }
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
        guard let node = proxy.node else {
            fatalError("ScrollViewGesture requires a live ScrollViewNode")
        }
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

// Connects the public logical scroll host to the shared gesture pipeline without
// routing it through the owning scroll node.
struct SystemScrollViewGesture: GestureViewModifier, GestureCallbacks {
    typealias Combiner = DefaultGestureCombiner
    typealias Value = ScrollGesture.Value
    typealias StateType = Void
    typealias Body = Never
    typealias ContentGesture = ModifierGesture<
        CallbacksGesture<Self>,
        SystemScrollGesture
    >

    var scrollView: HostingScrollView

    static var initialState: Void { () }
    var name: String? { nil }

    var gestureMask: GestureMask {
        scrollView.properties.isEnabled && (scrollView.configuration.isScrollEnabled ?? true)
            ? .all
            : .gesture
    }

    var gesture: ContentGesture {
        let axes = scrollView.configuration.axes
        var directions: _EventDirections = []
        if axes.contains(.horizontal) {
            directions.formUnion(.horizontal)
        }
        if axes.contains(.vertical) {
            directions.formUnion(.vertical)
        }
        return ContentGesture(
            modifier: CallbacksGesture(callbacks: self),
            body: SystemScrollGesture(
                minimumDistance: 10,
                allowedDirections: directions
            )
        )
    }

    func dispatch(
        phase: GesturePhase<ScrollGesture.Value>,
        state: inout Void
    ) -> (() -> Void)? {
        _ = state
        return { scrollView.dispatchScrollGesturePhase(phase) }
    }

    func cancel(state: Void) -> (() -> Void)? {
        { scrollView.dispatchScrollGesturePhase(.failed) }
    }

    static func makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("SystemScrollViewGesture.makeView requires AG context")
        }

        var outputs = body(_Graph(), inputs)
        guard inputs.preferences.keys.contains(ViewRespondersKey.self),
              let viewGraph = _AGGraphContext.current?.context as? ViewGraph,
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
