//
//  File: LongPressGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

public struct LongPressGesture : Gesture {
    public var minimumDuration: Double
    public var maximumDistance: CGFloat {
        get { _maximumDistance }
        set { _maximumDistance = newValue }
    }

    var _maximumDistance: CGFloat
    public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration
        self._maximumDistance = maximumDistance
    }

    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        struct _Generator : _GestureRecognizerGenerator {
            let graph: _GraphValue<LongPressGesture>
            let inputs: _GestureInputs
            func makeGesture<T>(encloser: T, graph: _GraphValue<T>) -> _GestureRecognizer<Value>? {
                if let gesture = graph.value(atPath: self.graph, from: encloser) {
                    let callbacks = inputs.makeCallbacks(of: Value.self, from: encloser, graph: graph)
                    return LongPressGestureRecognizer(gesture: gesture, callbacks: callbacks, target: inputs.view)
                }
                fatalError("Unable to recover gesture: \(self.graph.valueType)")
            }
        }
        return _GestureOutputs(generator: _Generator(graph: gesture, inputs: inputs))
    }

    public typealias Value = Bool
    public typealias Body = Never
}

extension View {
    public func onLongPressGesture(minimumDuration: Double = 0.5,
                                   maximumDistance: CGFloat = 10,
                                   perform action: @escaping () -> Void,
                                   onPressingChanged: ((Bool) -> Void)? = nil) -> some View {
        self.gesture(
            ModifierGesture(
                content: LongPressGesture(minimumDuration: minimumDuration,
                                          maximumDistance: maximumDistance),
                modifier: CallbacksGesture(
                    callbacks: PressableGestureCallbacks(pressing: onPressingChanged,
                                                         pressed: action)
                )
            )
        )
    }
}

class LongPressGestureRecognizer : _GestureRecognizer<LongPressGesture.Value> {
    let gesture: LongPressGesture
    var typeFilter: _PrimitiveGestureTypes = .all
    let buttonID: Int
    var deviceID: Int?
    var location: CGPoint
    let clock: ContinuousClock
    var timestamp: ContinuousClock.Instant
    var task: Task<Void, Never>?

    init(gesture: LongPressGesture, callbacks: Callbacks, target: ViewContext?) {
        self.gesture = gesture
        self.buttonID = 0
        self.location = .zero
        self.clock = .continuous
        self.timestamp = .now
        super.init(callbacks: callbacks, target: target)
    }

    override var type: _PrimitiveGestureTypes { .longPress }
    override var isValid: Bool {
        typeFilter.contains(self.type) && view != nil
    }

    override func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        self.typeFilter = f
        return f.subtracting(.longPress)
    }

    override func began(deviceID: Int, buttonID: Int, location: CGPoint) {
        if self.deviceID == nil, self.buttonID == buttonID {
            let location = self.locationInView(location)
            self.deviceID = deviceID
            self.location = location
            self.state = .processing

            let fire = clock.now + .seconds(self.gesture.minimumDuration)

            self.pressableGestureCallbacks.forEach {
                $0.pressing?(true)
            }

            self.task = Task { @MainActor in
                try? await Task.sleep(until: fire, clock: self.clock)
                if Task.isCancelled {
                    self.state = .cancelled
                } else {
                    self.deviceID = nil
                    self.state = .done
                    self.pressableGestureCallbacks.forEach {
                        $0.pressing?(false)
                        $0.pressed?()
                    }
                    self.endedCallbacks.forEach {
                        $0.ended(true)
                    }
                }
            }
        }
    }

    override func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
        if self.deviceID == deviceID, self.buttonID == buttonID {
            let location = self.locationInView(location)
            let d = (self.location - location).magnitude
            if d > self.gesture.maximumDistance {
                self.task?.cancel()
                self.task = nil
                self.state = .failed
                self.pressableGestureCallbacks.forEach {
                    $0.pressing?(false)
                }
            }
        }
    }

    override func ended(deviceID: Int, buttonID: Int) {
        if self.deviceID == deviceID, self.buttonID == buttonID {
            self.task?.cancel()
            self.task = nil
            self.deviceID = nil
            self.state = .failed
            self.pressableGestureCallbacks.forEach {
                $0.pressing?(false)
            }
        }
    }

    override func cancelled(deviceID: Int, buttonID: Int) {
        if self.deviceID == deviceID, self.buttonID == buttonID {
            self.task?.cancel()
            self.task = nil
            self.deviceID = nil
            self.state = .cancelled
            self.pressableGestureCallbacks.forEach {
                $0.pressing?(false)
            }
        }
    }

    override func reset() {
        self.task?.cancel()
        self.task = nil
        self.deviceID = nil
        self.state = .ready
    }
}
