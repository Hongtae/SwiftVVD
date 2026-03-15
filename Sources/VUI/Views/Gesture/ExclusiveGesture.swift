//
//  File: ExclusiveGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ExclusiveGesture<First, Second>: Gesture where First: Gesture, Second: Gesture {
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
        guard let graph = AttributeGraph.current else {
            fatalError("ExclusiveGesture._makeGesture requires AG context")
        }

        // Both gestures are wired to the same inputs.
        // First has priority: if first is active/ended, second is suppressed.
        let firstOutputs = First._makeGesture(gesture: gesture[\.first], inputs: inputs)
        let secondOutputs = Second._makeGesture(gesture: gesture[\.second], inputs: inputs)

        let fp = firstOutputs.phase
        let sp = secondOutputs.phase

        let combinedPhase: Attribute<GesturePhase<Value>> = graph.makeRule {
            let f = fp.value
            let s = sp.value
            switch f {
            case .ended(let v): return .ended(.first(v))
            case .active(let v): return .active(.first(v))
            case .failed:
                // First failed — fall through to second
                switch s {
                case .ended(let v): return .ended(.second(v))
                case .active(let v): return .active(.second(v))
                case .failed: return .failed
                case .possible: return .possible(nil)
                }
            case .possible:
                // Still waiting for first
                return .possible(nil)
            }
        }

        var out = _GestureOutputs(phase: combinedPhase)
        for kv in firstOutputs.preferences.preferences { out.preferences.preferences.append(kv) }
        for kv in secondOutputs.preferences.preferences { out.preferences.preferences.append(kv) }
        return out
    }

    public typealias Body = Never
}

extension ExclusiveGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}
extension ExclusiveGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {}

extension Gesture {
    @inlinable public func exclusively<Other>(before other: Other) -> ExclusiveGesture<Self, Other> where Other: Gesture {
        ExclusiveGesture(self, other)
    }
}
