//
//  File: GestureModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

protocol _GestureInputsModifier {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs)
}

private struct _CallbackGenerator<Callback>: GestureCallbackGenerator {
    let graph: _GraphValue<Callback>
    func _makeCallback(containerView: ViewContext) -> Any {
        if let value = containerView.value(atPath: self.graph) {
            return value
        }
        fatalError("Unable to recover value: \(self.graph.valueType)")
    }
}

struct EndedCallbacks<Value>: _GestureInputsModifier {
    let ended: (Value)->Void
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs) {
        inputs.endedCallbacks.append(_CallbackGenerator(graph: modifier))
    }
}

struct ChangedCallbacks<Value>: _GestureInputsModifier {
    let changed: (Value)->Void
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs) {
        inputs.endedCallbacks.append(_CallbackGenerator(graph: modifier))
    }
}

struct PressableGestureCallbacks<Value>: _GestureInputsModifier {
    let pressing: ((Value)->Void)?
    let pressed: (()->Void)?
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs) {
        inputs.endedCallbacks.append(_CallbackGenerator(graph: modifier))
    }
}

struct CallbacksGesture<Callbacks>: _GestureInputsModifier where Callbacks: _GestureInputsModifier {
    let callbacks: Callbacks
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs) {
        Callbacks._makeInputs(modifier: modifier[\.callbacks], inputs: &inputs)
    }
}

struct ModifierGesture<Modifier, Content>: Gesture where Modifier: _GestureInputsModifier, Content: Gesture {
    let content: Content
    let modifier: Modifier

    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Content.Value> {
        var inputs = inputs
        Modifier._makeInputs(modifier: gesture[\.modifier], inputs: &inputs)
        return Content._makeGesture(gesture: gesture[\.content], inputs: inputs)
    }

    public typealias Body = Never
    public typealias Value = Content.Value
}

public struct _EndedGesture<Content> where Content: Gesture {
    public typealias Body = Never
    public typealias Value = Content.Value

    typealias _Body = ModifierGesture<CallbacksGesture<EndedCallbacks<Value>>, Content>
    let _body: _Body
}

extension _EndedGesture: Gesture {
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Content.Value> {
        _Body._makeGesture(gesture: gesture[\._body], inputs: inputs)
    }
}

public struct _ChangedGesture<Content> where Content: Gesture, Content.Value: Equatable {
    public typealias Body = Never
    public typealias Value = Content.Value

    typealias _Body = ModifierGesture<CallbacksGesture<ChangedCallbacks<Value>>, Content>
    let _body: _Body
}

extension _ChangedGesture: Gesture {
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Content.Value> {
        _Body._makeGesture(gesture: gesture[\._body], inputs: inputs)
    }
}

extension Gesture {
    public func onEnded(_ action: @escaping (Self.Value) -> Void) -> _EndedGesture<Self> {
        .init(_body: ModifierGesture(
            content: self,
            modifier: CallbacksGesture(
                callbacks: EndedCallbacks(ended: action))))
    }
}

extension Gesture where Self.Value: Equatable {
    public func onChanged(_ action: @escaping (Self.Value) -> Void) -> _ChangedGesture<Self> {
        .init(_body: ModifierGesture(
            content: self,
            modifier: CallbacksGesture(
                callbacks: ChangedCallbacks(changed: action))))
    }
}

struct AddGestureModifier<T>: ViewModifier where T: Gesture {
    let gesture: T
    let gestureMask: GestureMask

    typealias Body = Never
}

struct SimultaneousGestureModifier<T>: ViewModifier where T: Gesture {
    let gesture: T
    let gestureMask: GestureMask

    typealias Body = Never
}

struct HighPriorityGestureModifier<T>: ViewModifier where T: Gesture {
    let gesture: T
    let gestureMask: GestureMask

    typealias Body = Never
}

extension View {
    public func gesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T: Gesture {
        self.modifier(AddGestureModifier(gesture: gesture, gestureMask: mask))
    }

    public func highPriorityGesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T: Gesture {
        self.modifier(HighPriorityGestureModifier(gesture: gesture, gestureMask: mask))
    }

    public func simultaneousGesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T: Gesture {
        self.modifier(SimultaneousGestureModifier(gesture: gesture, gestureMask: mask))
    }
}

protocol _GestureGenerator {
    associatedtype T: Gesture
    var gesture: T { get }
    var gestureMask: GestureMask { get }
}

extension AddGestureModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view?.makeView() {
            let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                GestureViewContext(graph: graph, body: body, inputs: inputs)
            }
            return _ViewOutputs(view: view)
        }
        return outputs
    }
}

extension SimultaneousGestureModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view?.makeView() {
            let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                GestureViewContext(graph: graph, body: body, inputs: inputs)
            }
            return _ViewOutputs(view: view)
        }
        return outputs
    }
}

extension HighPriorityGestureModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view?.makeView() {
            let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                GestureViewContext(graph: graph, body: body, inputs: inputs)
            }
            return _ViewOutputs(view: view)
        }
        return outputs
    }
}

extension AddGestureModifier: _GestureGenerator {}
extension SimultaneousGestureModifier: _GestureGenerator {}
extension HighPriorityGestureModifier: _GestureGenerator {}


private class GestureViewContext<Modifier>: ViewModifierContext<Modifier> where Modifier: ViewModifier & _GestureGenerator  {

    enum _GestureOutput {
        case gesture(_GestureHandler)
        case simultaneousGesture(_GestureHandler)
        case highPriorityGesture(_GestureHandler)
        case none
    }

    override func updateView(_ view: inout Modifier) {
        super.updateView(&view)

        // restore gesture handlers if they already exist
        let gesture = graph[\.gesture]
        if let handler = self.sharedContext.gestureHandlers.first(where: { handler in
            handler.graph == gesture
        }) {
            handler.view = self
        }
    }

    func makeGesture(target: ViewContext) -> _GestureOutput {
        guard let modifier else { return .none }

        func _makeGesture<T: _GestureGenerator>(_ generator: T, graph: _GraphValue<T>) -> _GestureOutput {
            func _make<U: Gesture>(_ gesture: _GraphValue<U>) -> _GestureOutput {
                let inputs = _GestureInputs(view: target)
                let outputs = U._makeGesture(gesture: gesture, inputs: inputs)
                if let handler = outputs.generator.makeGesture(containerView: self) {
                    if self.modifier is HighPriorityGestureModifier<U> {
                        return .highPriorityGesture(handler)
                    }
                    if self.modifier is SimultaneousGestureModifier<U> {
                        return .simultaneousGesture(handler)
                    }
                    return .gesture(handler)
                }
                return .none
            }
            return _make(graph[\.gesture])
        }
        return _makeGesture(modifier, graph: self.graph)
    }

    override func gestureHandlers(at location: CGPoint) -> GestureHandlerOutputs {
        let outputs = super.gestureHandlers(at: location)

        if self.hitTest(location) != nil {
            var gestures: [_GestureHandler] = []
            var simGestures: [_GestureHandler] = []
            var hpGestures: [_GestureHandler] = []

            let gesture = self.makeGesture(target: self.body)
            if case let .highPriorityGesture(handler) = gesture {
                hpGestures.append(handler)
            } else if case let .simultaneousGesture(handler) = gesture {
                simGestures.append(handler)
            } else if case let .gesture(handler) = gesture {
                gestures.append(handler)
            }
            // prioritize inner view higher.
            return GestureHandlerOutputs(gestures: gestures,
                                         simultaneousGestures: simGestures,
                                         highPriorityGestures: hpGestures)
                                         .merge(outputs)
        }
        return outputs
    }
}
