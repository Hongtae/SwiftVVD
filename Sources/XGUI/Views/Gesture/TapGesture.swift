//
//  File: TapGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct TapGesture: Gesture {
    public var count: Int
    public init(count: Int = 1) {
        self.count = count
    }

    public static func _makeGesture(gesture: _GraphValue<TapGesture>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        struct _Generator: _GestureRecognizerGenerator {
            let graph: _GraphValue<TapGesture>
            let inputs: _GestureInputs
            func makeGesture(containerView: ViewContext) -> _GestureRecognizer<Value>? {
                if let gesture = containerView.value(atPath: self.graph) {
                    let callbacks = inputs.makeCallbacks(of: Value.self, containerView: containerView)
                    return TapGestureRecognizer(graph: graph,
                                                target: inputs.view,
                                                callbacks: callbacks,
                                                gesture: gesture)
                }
                fatalError("Unable to recover gesture: \(self.graph.valueType)")
            }
        }
        return _GestureOutputs(generator: _Generator(graph: gesture, inputs: inputs))
    }

    public typealias Body = Never
    public typealias Value = Void
}

extension View {
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        self.gesture(TapGesture(count: count).onEnded(action), including: .all)
    }
}

class TapGestureRecognizer: _GestureRecognizer<TapGesture.Value> {
    var typeFilter: _PrimitiveGestureTypes = .all
    let gesture: TapGesture
    let buttonID: Int
    var deviceID: Int?
    var count: Int
    let maximumInterval: ContinuousClock.Duration
    let maximumDuration: ContinuousClock.Duration
    let clock: ContinuousClock
    var timestamp: ContinuousClock.Instant

    init(graph: _GraphValue<TapGesture>, target: ViewContext?, callbacks: Callbacks, gesture: TapGesture) {
        self.gesture = gesture
        self.buttonID = 0
        self.count = 0
        self.maximumInterval = .seconds(0.5)
        self.maximumDuration = .seconds(1.0)
        self.clock = .continuous
        self.timestamp = .now
        super.init(graph: graph, target: target, callbacks: callbacks)
    }

    override var type: _PrimitiveGestureTypes { .tap }
    override var isValid: Bool {
        typeFilter.contains(self.type) && self.endedCallbacks.isEmpty == false
    }

    override func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        self.typeFilter = f
        return f.subtracting(.tap)
    }

    override func began(deviceID: Int, buttonID: Int, location: CGPoint) {
        if self.buttonID == buttonID {
            if self.deviceID == nil {
                self.deviceID = deviceID
                self.timestamp = self.clock.now
                self.count = 0
                self.state = .processing
            } else if self.deviceID == deviceID {
                let t = self.clock.now
                let d = self.timestamp.duration(to: t)
                self.timestamp = t
                if d > self.maximumInterval {
                    self.deviceID = nil
                    self.state = .failed
                } else {
                    self.deviceID = deviceID
                    self.state = .processing
                }
            }
        }
    }

    override func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
        if self.deviceID == deviceID, self.buttonID == buttonID {
            let d = self.timestamp.duration(to: self.clock.now)
            if d > self.maximumDuration {
                self.deviceID = nil
                self.state = .failed
            }
        }
    }

    override func ended(deviceID: Int, buttonID: Int) {
        if self.deviceID == deviceID, self.buttonID == buttonID {
            let t = self.clock.now
            let d = self.timestamp.duration(to: t)
            self.timestamp = t
            if d > self.maximumDuration {
                self.deviceID = nil
                self.state = .failed
            } else {
                count = count + 1

                if count == self.gesture.count {
                    self.deviceID = nil
                    self.state = .done
                    self.endedCallbacks.forEach {
                        $0.ended(())
                    }
                }
            }
        }
    }

    override func cancelled(deviceID: Int, buttonID: Int) {
        if self.deviceID == deviceID, self.buttonID == buttonID {
            self.deviceID = nil
            self.state = .cancelled
        }
    }

    override func reset() {
        self.deviceID = nil
        self.state = .ready
    }
}
