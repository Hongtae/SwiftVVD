//
//  File: DragGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

public struct DragGesture : Gesture {
    public struct Value : Equatable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint

        var _velocity: _Velocity<CGSize>

        public var translation: CGSize {
            CGSize(width: (location.x - startLocation.x).magnitude,
                   height: (location.y - startLocation.y).magnitude)
        }

        public var velocity: CGSize {
            let predicted = predictedEndLocation
            return CGSize(
                width: 4.0 * (predicted.x - location.x),
                height: 4.0 * (predicted.y - location.y))
        }
        public var predictedEndLocation: CGPoint {
            let x = location.x + _velocity.valuePerSecond.width * 0.25
            let y = location.y + _velocity.valuePerSecond.height * 0.25
            return CGPoint(x: x, y: y)
        }
        public var predictedEndTranslation: CGSize {
            let loc = predictedEndLocation
            return CGSize(width: (loc.x - startLocation.x).magnitude,
                          height: (loc.y - startLocation.y).magnitude)
        }

        //struct Platform : Equatable {}
        //let platform = Platform()
    }

    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace

    public init(minimumDistance: CGFloat = 10, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace.coordinateSpace
    }

    public static func _makeGesture(gesture: _GraphValue<DragGesture>, inputs: _GestureInputs) -> _GestureOutputs<DragGesture.Value> {
        struct _Generator : _GestureRecognizerGenerator {
            let graph: _GraphValue<DragGesture>
            let inputs: _GestureInputs
            func makeGesture<T>(encloser: T, graph: _GraphValue<T>) -> _GestureRecognizer<Value>? {
                if let gesture = graph.value(atPath: self.graph, from: encloser) {
                    let callbacks = inputs.makeCallbacks(of: Value.self, from: encloser, graph: graph)
                    return DragGestureRecognizer(gesture: gesture, callbacks: callbacks, target: inputs.view)
                }
                fatalError("Unable to recover gesture: \(self.graph.valueType)")
            }
        }
        return _GestureOutputs(generator: _Generator(graph: gesture, inputs: inputs))
    }

    public typealias Body = Never
}

class DragGestureRecognizer : _GestureRecognizer<DragGesture.Value> {
    let gesture: DragGesture
    var typeFilter: _PrimitiveGestureTypes = .all
    let buttonID: Int
    var deviceID: Int?
    var value: DragGesture.Value
    var dragging = false

    init(gesture: DragGesture, callbacks: Callbacks, target: ViewContext?) {
        self.gesture = gesture
        self.buttonID = 0
        self.value = .init(time: .now,
                           location: .zero,
                           startLocation: .zero,
                           _velocity: _Velocity(valuePerSecond: .zero))
        super.init(callbacks: callbacks, target: target)
    }

    override var type: _PrimitiveGestureTypes { .drag }
    override var isValid: Bool {
        typeFilter.contains(self.type) && view != nil
    }

    override func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        self.typeFilter = f
        return f.subtracting(.drag)
    }

    func convertLocation(_ location: CGPoint) -> CGPoint {
        if self.gesture.coordinateSpace.isLocal {
            return self.locationInView(location)
        }
        return location
    }

    override func began(deviceID: Int, buttonID: Int, location: CGPoint) {
        if self.deviceID == nil, self.buttonID == buttonID {
            let location = self.convertLocation(location)
            self.deviceID = deviceID
            self.value.time = .now
            self.value.startLocation = location
            self.value.location = location
            self.value._velocity.valuePerSecond = .zero
            self.dragging = false
            self.state = .processing
        }
    }

    override func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
        if self.deviceID == deviceID, self.buttonID == buttonID {
            let location = self.convertLocation(location)
            let now: Date = .now
            let interval = self.value.time.distance(to: now)
            if interval > .zero {
                let d = (location - self.value.location) / interval
                self.value._velocity.valuePerSecond = CGSize(width: d.x, height: d.y)
            }
            self.value.time = now
            self.value.location = location
            self.state = .processing

            if self.dragging == false {
                let distance = (location - self.value.startLocation).magnitude
                if distance >= self.gesture.minimumDistance {
                    self.dragging = true
                }
            }
            if self.dragging {
                self.changedCallbacks.forEach {
                    $0.changed(self.value)
                }
            }
        }
    }

    override func ended(deviceID: Int, buttonID: Int) {
        if self.deviceID == deviceID, self.buttonID == buttonID {
            self.deviceID = nil
            self.state = .done
            if self.dragging {
                self.endedCallbacks.forEach {
                    $0.ended(self.value)
                }
            }
            self.dragging = false
        }
    }

    override func cancelled(deviceID: Int, buttonID: Int) {
        if self.deviceID == deviceID, self.buttonID == buttonID {
            self.deviceID = nil
            self.dragging = false
            self.state = .cancelled
        }
    }

    override func reset() {
        self.deviceID = nil
        self.dragging = false
        self.state = .ready
    }
}
