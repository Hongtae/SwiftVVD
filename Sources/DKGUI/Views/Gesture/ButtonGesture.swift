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
    override var type: _PrimitiveGestureType { .button }
    override var isValid: Bool { true }

    let gesture: _ButtonGesture

    init(gesture: _ButtonGesture, inputs: _GestureInputs) {
        self.gesture = gesture
        super.init(inputs: inputs)
    }

    required init(inputs: _GestureInputs) {
        fatalError("init(inputs:) has not been implemented")
    }
}
