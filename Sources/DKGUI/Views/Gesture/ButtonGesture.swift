//
//  File: ButtonGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct _ButtonGesture : Gesture {
    public var action: () -> Void
    public var pressingAction: ((Bool) -> Void)?

    public init(action: @escaping () -> Void, pressing: ((Bool) -> Void)? = nil) {
        self.action = action
        self.pressingAction = pressing
    }

    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Void> {
        _GestureOutputs<Void>(recognizer: _ButtonGestureRecognizer(gesture: gesture.value, inputs: inputs))
    }

    public typealias Body = Never
    public typealias Value = Void
}

extension View {
    public func _onButtonGesture(pressing: ((Bool) -> Void)? = nil, perform action: @escaping () -> Void) -> some View {
        self.gesture(_ButtonGesture(action: action, pressing: pressing))
    }
}

class _ButtonGestureRecognizer : _GestureRecognizer<_ButtonGesture.Value> {
    var typeFilter: _PrimitiveGestureTypes = .all

    override var type: _PrimitiveGestureTypes { .button }
    override var isValid: Bool {
        typeFilter.contains(self.type) && viewProxy != nil 
    }

    let gesture: _ButtonGesture

    init(gesture: _ButtonGesture, inputs: _GestureInputs) {
        self.gesture = gesture
        super.init(inputs: inputs)
    }

    required init(inputs: _GestureInputs) {
        fatalError("init(inputs:) has not been implemented")
    }

    override func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        self.typeFilter = f
        return self.typeFilter
    }

    let buttonID: Int = 0
    var deviceID: Int? = nil
    var location: CGPoint = .zero
    var hover: Bool = false
    override func began(deviceID: Int, buttonID: Int, location: CGPoint) {
        if self.deviceID == nil, self.buttonID == buttonID, let viewProxy {
            self.deviceID = deviceID
            self.location = location
            self.hover = viewProxy.bounds.contains(location)
            self.gesture.pressingAction?(self.hover)
            self.state = .processing
        }
    }

    override func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
        let h = self.hover
        if self.deviceID == deviceID, self.buttonID == buttonID, let viewProxy {
            self.location = location
            self.hover = viewProxy.bounds.contains(location)
            self.state = .processing
        }
        if h != self.hover {
            self.gesture.pressingAction?(self.hover)
        }
    }

    override func ended(deviceID: Int, buttonID: Int) {
        var invokeAction = false
        if self.deviceID == deviceID, self.buttonID == buttonID, viewProxy != nil {
            invokeAction = self.hover
            self.deviceID = nil
            self.hover = false
            self.state = .done
        }
        if invokeAction {
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
