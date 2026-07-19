//
//  File: SimultaneousGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct SimultaneousGesture<First, Second>: Gesture, PrimitiveGesture,
    PrimitiveDebuggableGesture where First: Gesture, Second: Gesture {
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
        guard let graph = _AGGraph.current else {
            fatalError("SimultaneousGesture._makeGesture requires AG context")
        }

        // Both gestures receive identical inputs, so they run simultaneously.
        let firstOutputs = First._makeGesture(gesture: gesture[\.first], inputs: inputs)
        let secondOutputs = Second._makeGesture(gesture: gesture[\.second], inputs: inputs)

        let firstPhase = firstOutputs.phase
        let secondPhase = secondOutputs.phase

        // Combined phase: active when either is active, ended when either ends,
        // failed only when both fail.
        let combinedPhase: Attribute<GesturePhase<Value>> = graph.makeRule {
            let fp = firstPhase.value
            let sp = secondPhase.value
            switch (fp, sp) {
            case (.ended(let fv), _):
                return .ended(Value(first: fv, second: nil))
            case (_, .ended(let sv)):
                return .ended(Value(first: nil, second: sv))
            case (.active(let fv), _):
                return .active(Value(first: fv, second: nil))
            case (_, .active(let sv)):
                return .active(Value(first: nil, second: sv))
            case (.failed, .failed):
                return .failed
            default:
                return .possible(nil)
            }
        }

        var out = _GestureOutputs(phase: combinedPhase)
        // Merge preferences from both sub-gestures
        for kv in firstOutputs.preferences.preferences { out.preferences.preferences.append(kv) }
        for kv in secondOutputs.preferences.preferences { out.preferences.preferences.append(kv) }
        return out
    }

    public typealias Body = Never
}

extension SimultaneousGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}
extension SimultaneousGesture.Value: Hashable where First.Value: Hashable, Second.Value: Hashable {}
extension SimultaneousGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {}

extension Gesture {
    @inlinable public func simultaneously<Other>(with other: Other) -> SimultaneousGesture<Self, Other> where Other: Gesture {
        SimultaneousGesture(self, other)
    }
}
