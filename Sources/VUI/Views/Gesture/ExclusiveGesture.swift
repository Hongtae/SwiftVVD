//
//  File: ExclusiveGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// ExclusiveState<A>: Rule
//
// AG Rule node injected into Second's _GestureInputs.inheritedPhase.
// Combines the parent inherited phase with the first gesture's current phase:
//   - clear the failed bit while First has not failed
//   - set the active bit while First is active
private struct ExclusiveState<A>: Rule {
    typealias Value = _GestureInputs.InheritedPhase

    // Separate inputs for the parent phase and First gesture phase.
    let parentInheritedPhaseAttr: Attribute<_GestureInputs.InheritedPhase>
    let firstPhaseAttr: Attribute<GesturePhase<A>>

    var value: _GestureInputs.InheritedPhase {
        let parentIP = parentInheritedPhaseAttr.value
        var result = parentIP.rawValue

        let firstPhase = firstPhaseAttr.value
        // bit0 (.failed): clear while First has not failed, so Second waits.
        if !firstPhase.isFailed {
            result &= ~1
        }
        // bit1 (.active): set while First is active, so Second waits.
        if firstPhase.isActive {
            result |= 2
        }
        return _GestureInputs.InheritedPhase(rawValue: result)
    }
}

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

    // ExclusivePhase<A, B>: Rule (nested to access ExclusiveGesture.Value)
    //
    // Combines first/second outputs into the exclusive combined phase.
    //
    // Decision tree:
    //   f.active -> .active(.first(v))
    //   f.ended  -> .ended(.first(v))
    //   f.failed -> delegate to second
    //   f.possible -> delegate to second, but s.failed remains .possible(nil)
    private struct ExclusivePhase: Rule {
        typealias Value = GesturePhase<ExclusiveGesture.Value>
        let firstPhase: Attribute<GesturePhase<First.Value>>
        let secondPhase: Attribute<GesturePhase<Second.Value>>

        var value: Value {
            let f = firstPhase.value
            let s = secondPhase.value
            switch f {
            case .ended(let v):  return .ended(.first(v))
            case .active(let v): return .active(.first(v))
            case .failed:
                switch s {
                case .ended(let v):  return .ended(.second(v))
                case .active(let v): return .active(.second(v))
                case .failed:        return .failed
                case .possible:      return .possible(nil)
                }
            case .possible:
                switch s {
                case .ended(let v):  return .ended(.second(v))
                case .active(let v): return .active(.second(v))
                case .failed:        return .possible(nil)
                case .possible:      return .possible(nil)
                }
            }
        }
    }

    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Self.Value> {
        guard let graph = _AGGraph.current else {
            fatalError("ExclusiveGesture._makeGesture requires AG context")
        }

        // Step 1: First gesture with original inputs.
        let firstOutputs = First._makeGesture(gesture: gesture[\.first], inputs: inputs)

        // Step 2: ExclusiveState AG rule reads firstOutputs.phase + parent inheritedPhase,
        // emits the InheritedPhase Second should see.
        let exclusiveStateAttr: Attribute<_GestureInputs.InheritedPhase> =
            graph.makeRule(ExclusiveState(
                parentInheritedPhaseAttr: inputs._inheritedPhase,
                firstPhaseAttr: firstOutputs.phase))

        // Step 3: Second gesture with modified inputs (inheritedPhase = ExclusiveState output).
        var secondInputs = inputs
        secondInputs._inheritedPhase = exclusiveStateAttr
        let secondOutputs = Second._makeGesture(gesture: gesture[\.second], inputs: secondInputs)

        // Step 4: ExclusivePhase AG rule combines both outputs into the final phase.
        let combinedPhaseAttr: Attribute<GesturePhase<Value>> =
            graph.makeRule(ExclusivePhase(
                firstPhase: firstOutputs.phase,
                secondPhase: secondOutputs.phase))

        var out = _GestureOutputs(phase: combinedPhaseAttr)
        for kv in firstOutputs.preferences.preferences  { out.preferences.preferences.append(kv) }
        for kv in secondOutputs.preferences.preferences { out.preferences.preferences.append(kv) }
        return out
    }

    public typealias Body = Never
}

extension ExclusiveGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}
extension ExclusiveGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {}

extension ExclusiveGesture: PrimitiveGesture, PrimitiveDebuggableGesture {}

@available(*, unavailable)
extension ExclusiveGesture: Sendable {}

extension Gesture {
    @inlinable public func exclusively<Other>(before other: Other) -> ExclusiveGesture<Self, Other> where Other: Gesture {
        ExclusiveGesture(self, other)
    }
}
