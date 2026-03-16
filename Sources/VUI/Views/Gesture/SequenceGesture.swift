//
//  File: SequenceGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct SequenceGesture<First, Second>: Gesture where First: Gesture, Second: Gesture {
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
        guard let graph = AttributeGraph.current else {
            fatalError("SequenceGesture._makeGesture requires AG context")
        }

        // First gesture must complete before second starts.
        // Both recognizers receive the same event stream; the combined phase rule
        // gates second's output on whether first has already ended.
        let firstOutputs = First._makeGesture(gesture: gesture[\.first], inputs: inputs)
        let secondOutputs = Second._makeGesture(gesture: gesture[\.second], inputs: inputs)

        let fp = firstOutputs.phase
        let sp = secondOutputs.phase

        // AG-safe storage for the first gesture's ended value.
        // Using an Attribute (not a MutableBox) so that:
        //  • the value survives first's recognizer resetting to .possible
        //  • dependency tracking correctly re-drives combinedPhase when this is written
        let firstEndedAttr: Attribute<First.Value?> = graph.makeInput(value: nil)

        let resetSeedAttr = inputs.resetSeed
        var lastResetSeed: UInt32 = 0

        // Side-effect rule: record first's ended value the moment it lands.
        // Fires synchronously inside the same setValue call stack as the event dispatch.
        graph.makeSideEffectRule { () -> Void in
            let currentSeed = resetSeedAttr.value
            if currentSeed != lastResetSeed {
                lastResetSeed = currentSeed
                firstEndedAttr.setValue(nil)
                return
            }
            // Write once: don't overwrite a valid firstEnded with a later re-evaluation.
            if case .ended(let v) = fp.value, firstEndedAttr.value == nil {
                firstEndedAttr.setValue(v)
            }
        }

        let combinedPhase: Attribute<GesturePhase<Value>> = graph.makeRule {
            // Read the persistent first-ended value first to establish the AG dependency.
            if let fv = firstEndedAttr.value {
                // First has completed; now follow second gesture's phase.
                switch sp.value {
                case .active(let sv): return .active(.second(fv, sv))
                case .ended(let sv):  return .ended(.second(fv, sv))
                case .failed:         return .ended(.second(fv, nil))
                case .possible:       return .active(.second(fv, nil))
                }
            }

            // First hasn't ended yet; follow first gesture's phase.
            switch fp.value {
            case .active(let v): return .active(.first(v))
            case .ended(let v):  return .active(.second(v, nil)) // transitioning frames
            case .failed:        return .failed
            case .possible:      return .possible(nil)
            }
        }

        var out = _GestureOutputs(phase: combinedPhase)
        for kv in firstOutputs.preferences.preferences { out.preferences.preferences.append(kv) }
        for kv in secondOutputs.preferences.preferences { out.preferences.preferences.append(kv) }
        return out
    }

    public typealias Body = Never
}

extension SequenceGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}
extension SequenceGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {}

extension Gesture {
    @inlinable public func sequenced<Other>(before other: Other) -> SequenceGesture<Self, Other> where Other: Gesture {
        SequenceGesture(self, other)
    }
}
