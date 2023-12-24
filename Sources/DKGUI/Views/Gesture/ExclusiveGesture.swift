//
//  File: ExclusiveGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ExclusiveGesture<First, Second> : Gesture where First : Gesture, Second : Gesture {
    public enum Value {
        case first(First.Value)
        case second(Second.Value)
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

extension ExclusiveGesture.Value : Equatable where First.Value : Equatable, Second.Value : Equatable {
}

extension ExclusiveGesture.Value : Sendable where First.Value : Sendable, Second.Value : Sendable {
}

extension Gesture {
    @inlinable public func exclusively<Other>(before other: Other) -> ExclusiveGesture<Self, Other> where Other : Gesture {
        return ExclusiveGesture(self, other)
    }
}
