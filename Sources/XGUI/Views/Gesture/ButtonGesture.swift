//
//  File: ButtonGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _ButtonGesture: Gesture {
    public var action: () -> Void
    public var pressingAction: ((Bool) -> Void)?

    public init(action: @escaping () -> Void, pressing: ((Bool) -> Void)? = nil) {
        self.action = action
        self.pressingAction = pressing
    }

    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        struct _Generator: _GestureRecognizerGenerator {
            let graph: _GraphValue<_ButtonGesture>
            let inputs: _GestureInputs
            func makeGesture(containerView: ViewContext) -> _GestureRecognizer<Value>? {
                if let gesture = containerView.value(atPath: self.graph) {
                    let callbacks = inputs.makeCallbacks(of: Value.self, containerView: containerView)
                    return _ButtonGestureRecognizer(graph: graph,
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
    public func _onButtonGesture(pressing: ((Bool) -> Void)? = nil, perform action: @escaping () -> Void) -> some View {
        self.gesture(_ButtonGesture(action: action, pressing: pressing))
    }
}

class _ButtonGestureRecognizer: _GestureRecognizer<_ButtonGesture.Value> {
    let gesture: _ButtonGesture
    var typeFilter: _PrimitiveGestureTypes = .all
    let buttonID: Int
    var deviceID: Int?
    var location: CGPoint
    var hover: Bool

    init(graph: _GraphValue<_ButtonGesture>, target: ViewContext?, callbacks: Callbacks, gesture: _ButtonGesture) {
        self.gesture = gesture
        self.location = .zero
        self.hover = false
        self.buttonID = 0
        super.init(graph: graph, target: target, callbacks: callbacks)
    }

    override var type: _PrimitiveGestureTypes { .button }
    override var isValid: Bool {
        typeFilter.contains(self.type) && view != nil
    }

    override func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        self.typeFilter = f
        return f.subtracting([.button, .tap, .longPress])
    }

    override func began(deviceID: Int, buttonID: Int, location: CGPoint) {
        if self.deviceID == nil, self.buttonID == buttonID, let view {
            let location = self.locationInView(location)
            self.deviceID = deviceID
            self.location = location
            self.hover = view.bounds.contains(location)
            self.state = .processing
            self.gesture.pressingAction?(self.hover)
        }
    }

    override func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
        let h = self.hover
        if self.deviceID == deviceID, self.buttonID == buttonID, let view {
            let location = self.locationInView(location)
            self.location = location
            self.state = .processing
            self.hover = view.bounds.contains(location)
        }
        if h != self.hover {
            self.gesture.pressingAction?(self.hover)
        }
    }

    override func ended(deviceID: Int, buttonID: Int) {
        var invokeAction = false
        if self.deviceID == deviceID, self.buttonID == buttonID, view != nil {
            invokeAction = self.hover
            self.deviceID = nil
            self.hover = false
            self.state = .done
        }
        if invokeAction {
            self.gesture.pressingAction?(false)
            self.gesture.action()
        }
    }

    override func cancelled(deviceID: Int, buttonID: Int) {
        if self.deviceID == deviceID, self.buttonID == buttonID {
            self.deviceID = nil
            self.hover = false
            self.state = .cancelled
        }
    }

    override func reset() {
        self.deviceID = nil
        self.hover = false
        self.state = .ready
    }
}
