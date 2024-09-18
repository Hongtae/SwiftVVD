//
//  File: SimultaneousGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

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
        let first = First._makeGesture(gesture: gesture[\.first], inputs: inputs)
        let second = Second._makeGesture(gesture: gesture[\.second], inputs: inputs)
        return _GestureOutputs(generator: _Generator(graph: gesture,
                                                     first: first,
                                                     second: second,
                                                     inputs: inputs))
    }

    public typealias Body = Never

    private struct _Generator : _GestureRecognizerGenerator {
        let graph: _GraphValue<SimultaneousGesture>
        let first: _GestureOutputs<First.Value>
        let second: _GestureOutputs<Second.Value>
        let inputs: _GestureInputs
        func makeGesture<T>(encloser: T, graph: _GraphValue<T>) -> _GestureRecognizer<Value>? {
            if let gesture = graph.value(atPath: self.graph, from: encloser) {
                let first = self.first.generator.makeGesture(encloser: gesture, graph: self.graph)
                let second = self.second.generator.makeGesture(encloser: gesture, graph: self.graph)
                if let first, let second {
                    let callbacks = inputs.makeCallbacks(of: Value.self, from: encloser, graph: graph)
                    return SimultaneousGestureRecognizer(first: first, second: second, callbacks: callbacks, target: inputs.view)
                }
                return nil
            }
            fatalError("Unable to recover gesture: \(self.graph.valueType)")
        }
    }
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

class SimultaneousGestureRecognizer<First : Gesture, Second : Gesture> : _GestureRecognizer<SimultaneousGesture<First, Second>.Value> {
    let first: _GestureRecognizer<First.Value>
    let second: _GestureRecognizer<Second.Value>
    typealias Value = SimultaneousGesture<First, Second>.Value

    init(first: _GestureRecognizer<First.Value>, second: _GestureRecognizer<Second.Value>, callbacks: Callbacks, target: ViewContext?) {
        self.first = first
        self.second = second
        super.init(callbacks: callbacks, target: target)

        self.first.endedCallbacks.append(EndedCallbacks<First.Value> {
            [weak self] in
            if let self {
                let value = Value(first: $0, second: nil)
                self.updateState()
                self.endedCallbacks.forEach { $0.ended(value) }
            }
        })
        self.first.changedCallbacks.append(ChangedCallbacks<First.Value> {
            [weak self] in
            if let self {
                let value = Value(first: $0, second: nil)
                self.changedCallbacks.forEach { $0.changed(value) }
            }
        })
        self.first.pressableGestureCallbacks.append(PressableGestureCallbacks<First.Value>(
            pressing: { [weak self] in
                if let self {
                    let value = Value(first: $0, second: nil)
                    self.pressableGestureCallbacks.forEach { $0.pressing?(value) }
                }
            }, 
            pressed: { [weak self] in
                if let self {
                    self.pressableGestureCallbacks.forEach { $0.pressed?() }
                }
            })
        )

        self.second.endedCallbacks.append(EndedCallbacks<Second.Value> {
            [weak self] in
            if let self {
                let value = Value(first: nil, second: $0)
                self.updateState()
                self.endedCallbacks.forEach { $0.ended(value) }
            }
        })
        self.second.changedCallbacks.append(ChangedCallbacks<Second.Value> {
            [weak self] in
            if let self {
                let value = Value(first: nil, second: $0)
                self.changedCallbacks.forEach { $0.changed(value) }
            }
        })
        self.second.pressableGestureCallbacks.append(PressableGestureCallbacks<Second.Value>(
            pressing: { [weak self] in
                if let self {
                    let value = Value(first: nil, second: $0)
                    self.pressableGestureCallbacks.forEach { $0.pressing?(value) }
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
        self.first.isValid || self.second.isValid
    }

    override func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        let f1 = self.first.setTypeFilter(f)
        let f2 = self.second.setTypeFilter(f)
        return f1.intersection(f2)
    }

    func updateState() {
        if self.first.state == .ready && self.second.state == .ready {
            self.state = .ready
            return
        }
        if self.first.state == .done && self.second.state == .done {
            self.state = .done
            return
        }
        if self.first.state == .cancelled && self.second.state == .cancelled {
            self.state = .cancelled
            return
        }
        if self.first.state == .failed && self.second.state == .failed {
            self.state = .failed
            return
        }
        self.state = .processing
    }

    override func began(deviceID: Int, buttonID: Int, location: CGPoint) {
        if self.first.isPossible {
            self.first.began(deviceID: deviceID, buttonID: buttonID, location: location)
        }
        if self.second.isPossible {
            self.second.began(deviceID: deviceID, buttonID: buttonID, location: location)
        }
        updateState()
    }

    override func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
        if self.first.isPossible {
            self.first.moved(deviceID: deviceID, buttonID: buttonID, location: location)
        }
        if self.second.isPossible {
            self.second.moved(deviceID: deviceID, buttonID: buttonID, location: location)
        }
        updateState()
    }

    override func ended(deviceID: Int, buttonID: Int) {
        if self.first.isPossible {
            self.first.ended(deviceID: deviceID, buttonID: buttonID)
        }
        if self.second.isPossible {
            self.second.ended(deviceID: deviceID, buttonID: buttonID)
        }
        updateState()
    }

    override func cancelled(deviceID: Int, buttonID: Int) {
        if self.first.isPossible {
            self.first.cancelled(deviceID: deviceID, buttonID: buttonID)
        }
        if self.second.isPossible {
            self.second.cancelled(deviceID: deviceID, buttonID: buttonID)
        }
        self.state = .cancelled
    }

    override func reset() {
        self.first.reset()
        self.second.reset()
    }
}
