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

public struct _GestureInputs {
    weak var view: ViewContext?
    var endedCallbacks: [Any] = []
    var changedCallbacks: [Any] = []
    var pressableGestureCallbacks: [Any] = []
}

public struct _GestureOutputs<Value> {
    var recognizer: _GestureRecognizer<Value>
}

public struct GestureMask : OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let none = GestureMask([])
    public static let gesture = GestureMask(rawValue: 1)
    public static let subviews = GestureMask(rawValue: 2)
    public static let all = GestureMask(rawValue: 3)
    public typealias RawValue = UInt32
}
