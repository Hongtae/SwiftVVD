//
//  File: AnyGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public struct AnyGesture<Value> : Gesture {
    fileprivate var storage: AnyGestureStorageBase<Value>
    public init<T>(_ gesture: T) where Value == T.Value, T : Gesture {
        self.storage = AnyGestureBox(gesture)
    }
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        fatalError()
    }
    public typealias Body = Never
}

@usableFromInline
class AnyGestureStorageBase<Value> {
    init<T>(_ gesture: T) where Value == T.Value, T : Gesture {
    }
    func _makeGesture(inputs: _GestureInputs) -> _GestureOutputs<Value> {
        fatalError()
    }
}

class AnyGestureBox<T : Gesture> : AnyGestureStorageBase<T.Value> {
    let gesture: T
    init(_ gesture: T) {
        self.gesture = gesture
        super.init(gesture)
    }
    override func _makeGesture(inputs: _GestureInputs) -> _GestureOutputs<T.Value> {
        fatalError()
    }
}
