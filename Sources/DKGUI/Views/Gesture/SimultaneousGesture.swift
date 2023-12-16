//
//  File: SimultaneousGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct SimultaneousGesture<First, Second> : Gesture where First : Gesture, Second : Gesture {
    public struct Value {
        public var first: First.Value?
        public var second: Second.Value?
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

extension SimultaneousGesture.Value : Equatable where First.Value : Equatable, Second.Value : Equatable {
}

extension SimultaneousGesture.Value : Hashable where First.Value : Hashable, Second.Value : Hashable {
}

extension Gesture {
    @inlinable public func simultaneously<Other>(with other: Other) -> SimultaneousGesture<Self, Other> where Other : Gesture {
        return SimultaneousGesture(self, other)
    }
}
