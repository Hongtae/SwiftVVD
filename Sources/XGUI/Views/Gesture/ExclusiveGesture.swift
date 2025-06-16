//
//  File: ExclusiveGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
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
        let first = First._makeGesture(gesture: gesture[\.first], inputs: inputs)
        let second = Second._makeGesture(gesture: gesture[\.second], inputs: inputs)
        return _GestureOutputs(generator: _Generator(graph: gesture,
                                                     first: first,
                                                     second: second,
                                                     inputs: inputs))
    }

    public typealias Body = Never

    private struct _Generator: _GestureRecognizerGenerator {
        let graph: _GraphValue<ExclusiveGesture>
        let first: _GestureOutputs<First.Value>
        let second: _GestureOutputs<Second.Value>
        let inputs: _GestureInputs
        func makeGesture(containerView: ViewContext) -> _GestureRecognizer<Value>? {
            if let gesture = containerView.value(atPath: self.graph) {
                let first = self.first.generator.makeGesture(containerView: containerView)
                let second = self.second.generator.makeGesture(containerView: containerView)
                if let first, let second {
                    let callbacks = inputs.makeCallbacks(of: Value.self, containerView: containerView)
                    return ExclusiveGestureRecognizer(graph: graph,
                                                      target: inputs.view,
                                                      callbacks: callbacks,
                                                      gesture: gesture,
                                                      first: first,
                                                      second: second)
                }
                return nil
            }
            fatalError("Unable to recover gesture: \(self.graph.valueType)")
        }
    }
}

extension ExclusiveGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {
}

extension ExclusiveGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {
}

extension Gesture {
    @inlinable public func exclusively<Other>(before other: Other) -> ExclusiveGesture<Self, Other> where Other: Gesture {
        return ExclusiveGesture(self, other)
    }
}

class ExclusiveGestureRecognizer<First: Gesture, Second: Gesture>: _GestureRecognizer<ExclusiveGesture<First, Second>.Value> {
    let first: _GestureRecognizer<First.Value>
    let second: _GestureRecognizer<Second.Value>
    typealias Value = ExclusiveGesture<First, Second>.Value
    var firstGestureProcessing = false

    init(graph: _GraphValue<ExclusiveGesture<First, Second>>,
         target: ViewContext?,
         callbacks: Callbacks,
         gesture: ExclusiveGesture<First, Second>,
         first: _GestureRecognizer<First.Value>,
         second: _GestureRecognizer<Second.Value>) {

        self.first = first
        self.second = second
        super.init(graph: graph, target: target, callbacks: callbacks)

        self.first.endedCallbacks.append(EndedCallbacks<First.Value> { [weak self] in
            if let self, self.firstGestureProcessing {
                let value: Value = .first($0)
                self.endedCallbacks.forEach {
                    $0.ended(value)
                }
                self.state = .done
            }
        })
        self.first.changedCallbacks.append(ChangedCallbacks<First.Value> { [weak self] in
            if let self, self.firstGestureProcessing {
                let value: Value = .first($0)
                self.changedCallbacks.forEach {
                    $0.changed(value)
                }
            }
        })
        self.first.pressableGestureCallbacks.append(PressableGestureCallbacks<First.Value>(
            pressing: { [weak self] in
                if let self, self.firstGestureProcessing {
                    let value: Value = .first($0)
                    self.pressableGestureCallbacks.forEach {
                        $0.pressing?(value)
                    }
                }
            },
            pressed: { [weak self] in
                if let self, self.firstGestureProcessing {
                    self.pressableGestureCallbacks.forEach {
                        $0.pressed?()
                    }
                }
            })
        )

        self.second.endedCallbacks.append(EndedCallbacks<Second.Value> { [weak self] in
            if let self, self.firstGestureProcessing == false {
                let value: Value = .second($0)
                self.endedCallbacks.forEach {
                    $0.ended(value)
                }
                self.state = .done
            }
        })
        self.second.changedCallbacks.append(ChangedCallbacks<Second.Value> { [weak self] in
            if let self, self.firstGestureProcessing == false {
                let value: Value = .second($0)
                self.changedCallbacks.forEach {
                    $0.changed(value)
                }
            }
        })
        self.second.pressableGestureCallbacks.append(PressableGestureCallbacks<Second.Value>(
            pressing: { [weak self] in
                if let self, self.firstGestureProcessing == false {
                    let value: Value = .second($0)
                    self.pressableGestureCallbacks.forEach {
                        $0.pressing?(value)
                    }
                }
            },
            pressed: { [weak self] in
                if let self {
                    self.pressableGestureCallbacks.forEach { $0.pressed?() }
                }
            })
        )
    }

    override var type: _PrimitiveGestureTypes { .drag }
    override var isValid: Bool {
        self.first.isValid && self.second.isValid
    }

    override func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        let f1 = self.first.setTypeFilter(f)
        let f2 = self.second.setTypeFilter(f)
        return f1.intersection(f2)
    }

    func updateState() {
        if self.first.isValid && self.first.state != .cancelled && self.first.state != .failed {
            self.firstGestureProcessing = true
        } else {
            self.firstGestureProcessing = false
        }

        if self.firstGestureProcessing {
            self.state = self.first.state
            return
        }
        self.state = self.second.state
    }

    override func began(deviceID: Int, buttonID: Int, location: CGPoint) {
        if self.first.isPossible {
            self.first.began(deviceID: deviceID, buttonID: buttonID, location: location)
        }
        if self.second.isPossible {
            self.second.began(deviceID: deviceID, buttonID: buttonID, location: location)
        }
        self.updateState()
    }

    override func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
        if self.first.isPossible {
            self.first.moved(deviceID: deviceID, buttonID: buttonID, location: location)
        }
        if self.second.isPossible {
            self.second.moved(deviceID: deviceID, buttonID: buttonID, location: location)
        }
        self.updateState()
    }

    override func ended(deviceID: Int, buttonID: Int) {
        if self.first.isPossible {
            self.first.ended(deviceID: deviceID, buttonID: buttonID)
        }
        if self.second.isPossible {
            self.second.ended(deviceID: deviceID, buttonID: buttonID)
        }
        self.updateState()
    }

    override func cancelled(deviceID: Int, buttonID: Int) {
        if self.first.isPossible {
            self.first.cancelled(deviceID: deviceID, buttonID: buttonID)
        }
        if self.second.isPossible {
            self.second.cancelled(deviceID: deviceID, buttonID: buttonID)
        }
        self.reset()
        self.state = .cancelled
    }

    override func reset() {
        self.first.reset()
        self.second.reset()
    }
}
