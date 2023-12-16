//
//  File: SequenceGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct SequenceGesture<First, Second> : Gesture where First : Gesture, Second : Gesture {
    public enum Value {
        case first(First.Value)
        case second(First.Value, Second.Value?)
    }
    public var first: First
    public var second: Second
    @inlinable public init(_ first: First, _ second: Second) {
        (self.first, self.second) = (first, second)
    }
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Self.Value> {
        fatalError()
    }
    public typealias Body = Never
}

extension SequenceGesture.Value : Equatable where First.Value : Equatable, Second.Value : Equatable {
}

extension Gesture {
    @inlinable public func sequenced<Other>(before other: Other) -> SequenceGesture<Self, Other> where Other : Gesture {
        return SequenceGesture(self, other)
    }
}
