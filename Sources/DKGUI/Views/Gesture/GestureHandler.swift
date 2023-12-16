//
//  File: GestureHandler.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

enum _PrimitiveGestureType {
    case unknown
    case tap
    case longPress
    case drag
    case magnification
    case rotation
    case rotation3D
    case button
}

class _GestureHandler {
    enum State: Int {
        case possible
        case began
        case changed
        case ended
        case cancelled
        case failed
    }
    var state: State { .possible }
    weak var viewProxy: ViewProxy?

    var type: _PrimitiveGestureType { .unknown }
    var isValid: Bool { false }

    required init(inputs: _GestureInputs) {
    }

    func began(deviceID: Int, buttonID: Int, location: CGPoint) {
    }

    func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
    }

    func ended(deviceID: Int, buttonID: Int) {
    }

    func cancelled(deviceID: Int, buttonID: Int) {
    }

    func reset() {
    }

    func shouldRequireFailure(of: _PrimitiveGestureType) -> Bool {
        false
    }
}

class _GestureRecognizer<Value> : _GestureHandler {
    let endedCallbacks: [EndedCallbacks<Value>]
    let changedCallbacks: [ChangedCallbacks<Value>]
    let pressableGestureCallbacks : [PressableGestureCallbacks<Value>]

    required init(inputs: _GestureInputs) {
        self.endedCallbacks = inputs.endedCallbacks.compactMap { $0 as? EndedCallbacks<Value> }
        self.changedCallbacks = inputs.changedCallbacks.compactMap { $0 as? ChangedCallbacks<Value> }
        self.pressableGestureCallbacks = inputs.pressableGestureCallbacks.compactMap { $0 as? PressableGestureCallbacks<Value> }
        super.init(inputs: inputs)
    }
}
