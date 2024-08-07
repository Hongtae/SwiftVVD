//
//  File: GestureModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

protocol _GestureInputsModifier {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs)
}

struct EndedCallbacks<Value> : _GestureInputsModifier {
    let ended: (Value)->Void
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs) {
        inputs.endedCallbacks.append(modifier.value)
    }
}

struct ChangedCallbacks<Value> : _GestureInputsModifier {
    let changed: (Value)->Void
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs) {
        inputs.changedCallbacks.append(modifier.value)
    }
}

struct PressableGestureCallbacks<Value> : _GestureInputsModifier {
    let pressing: ((Value)->Void)?
    let pressed: (()->Void)?
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs) {
        inputs.pressableGestureCallbacks.append(modifier.value)
    }
}

struct CallbacksGesture<Callbacks> : _GestureInputsModifier where Callbacks : _GestureInputsModifier {
    let callbacks: Callbacks
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs) {
        Callbacks._makeInputs(modifier: modifier[\.callbacks], inputs: &inputs)
    }
}

struct ModifierGesture<Modifier, Content> : Gesture where Modifier : _GestureInputsModifier, Content: Gesture {
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

public struct _EndedGesture<Content> where Content : Gesture {
    public typealias Body = Never
    public typealias Value = Content.Value

    typealias _Body = ModifierGesture<CallbacksGesture<EndedCallbacks<Value>>, Content>
    let _body: _Body
}

extension _EndedGesture : Gesture {
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Content.Value> {
        _Body._makeGesture(gesture: gesture[\._body], inputs: inputs)
    }
}

public struct _ChangedGesture<Content> where Content : Gesture, Content.Value : Equatable {
    public typealias Body = Never
    public typealias Value = Content.Value

    typealias _Body = ModifierGesture<CallbacksGesture<ChangedCallbacks<Value>>, Content>
    let _body: _Body
}

extension _ChangedGesture : Gesture {
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

extension Gesture where Self.Value : Equatable {
    public func onChanged(_ action: @escaping (Self.Value) -> Void) -> _ChangedGesture<Self> {
        .init(_body: ModifierGesture(
            content: self,
            modifier: CallbacksGesture(
                callbacks: ChangedCallbacks(changed: action))))
    }
}

struct AddGestureModifier<T> : ViewModifier where T : Gesture {
    let gesture: T
    let gestureMask: GestureMask

    typealias Body = Never
}

extension AddGestureModifier : _ViewInputsModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        inputs.gestures.append(modifier[\.gesture].value)
    }
}

struct SimultaneousGestureModifier<T> : ViewModifier where T : Gesture {
    let gesture: T
    let gestureMask: GestureMask

    typealias Body = Never
}

extension SimultaneousGestureModifier : _ViewInputsModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        inputs.simultaneousGestures.append(modifier[\.gesture].value)
    }
}

struct HighPriorityGestureModifier<T> : ViewModifier where T : Gesture {
    let gesture: T
    let gestureMask: GestureMask

    typealias Body = Never
}

extension HighPriorityGestureModifier : _ViewInputsModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        inputs.highPriorityGestures.append(modifier[\.gesture].value)
    }
}

extension View {
    public func gesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T : Gesture {
        self.modifier(AddGestureModifier(gesture: gesture, gestureMask: mask))
    }

    public func highPriorityGesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T : Gesture {
        self.modifier(HighPriorityGestureModifier(gesture: gesture, gestureMask: mask))
    }

    public func simultaneousGesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T : Gesture {
        self.modifier(SimultaneousGestureModifier(gesture: gesture, gestureMask: mask))
    }
}
