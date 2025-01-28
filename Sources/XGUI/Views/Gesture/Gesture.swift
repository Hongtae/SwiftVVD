//
//  File: Gesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public protocol Gesture<Value> {
    associatedtype Value
    static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Self.Value>
    associatedtype Body : Gesture
    var body: Self.Body { get }
}

extension Never : Gesture {
    public typealias Value = Never
}

extension Gesture where Self.Value == Self.Body.Value {
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Self.Body.Value> {
        Self.Body._makeGesture(gesture: gesture[\.body], inputs: inputs)
    }
}

extension Gesture where Self.Body == Never {
    public var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }
}

extension Optional : Gesture where Wrapped : Gesture {
    public typealias Value = Wrapped.Value
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Wrapped.Value> {
        Wrapped._makeGesture(gesture: gesture[\.unsafelyUnwrapped], inputs: inputs)
    }
    public typealias Body = Never
}

protocol GestureCallbackGenerator {
    func _makeCallback(containerView: ViewContext) -> Any
}

public struct _GestureInputs {
    let view: ViewContext
    var endedCallbacks: [GestureCallbackGenerator] = []
    var changedCallbacks: [GestureCallbackGenerator] = []
    var pressableGestureCallbacks: [GestureCallbackGenerator] = []

    func makeCallbacks<Value>(of: Value.Type, containerView: ViewContext) -> _GestureRecognizer<Value>.Callbacks {
        var callbacks = _GestureRecognizer<Value>.Callbacks()
        callbacks.endedCallbacks = self.endedCallbacks.compactMap {
            $0._makeCallback(containerView: containerView) as? EndedCallbacks<Value>
        }
        callbacks.changedCallbacks = self.changedCallbacks.compactMap {
            $0._makeCallback(containerView: containerView) as? ChangedCallbacks<Value>
        }
        callbacks.pressableGestureCallbacks = self.pressableGestureCallbacks.compactMap {
            $0._makeCallback(containerView: containerView) as? PressableGestureCallbacks<Value>
        }
        return callbacks
    }
}

protocol _GestureRecognizerGenerator<Value> {
    associatedtype Value
    func makeGesture(containerView: ViewContext) -> _GestureRecognizer<Value>?
}

public struct _GestureOutputs<Value> {
    let generator: any _GestureRecognizerGenerator<Value>
}

public struct GestureMask : OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let none = GestureMask([])
    public static let gesture = GestureMask(rawValue: 1)
    public static let subviews = GestureMask(rawValue: 2)
    public static let all = GestureMask(rawValue: 3)
    public typealias RawValue = UInt32
}
