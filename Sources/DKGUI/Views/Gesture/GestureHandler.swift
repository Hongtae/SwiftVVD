//
//  File: GestureHandler.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

struct _PrimitiveGestureTypes : OptionSet {
    let rawValue: UInt
    static let tap              = Self(rawValue: 1 << 0)
    static let longPress        = Self(rawValue: 1 << 1)
    static let drag             = Self(rawValue: 1 << 2)
    static let magnification    = Self(rawValue: 1 << 3)
    static let rotation         = Self(rawValue: 1 << 4)
    static let rotation3D       = Self(rawValue: 1 << 5)
    static let button           = Self(rawValue: 1 << 6)

    static let all = Self(rawValue: .max)
    static let none: Self = []
}

class _GestureHandler {
    enum State: Int {
        case ready
        case processing
        case cancelled
        case failed
        case done
    }
    var state: State = .ready
    weak var view: ViewContext?

    func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        f.subtracting(self.type)
    }

    var type: _PrimitiveGestureTypes { .none }
    var isValid: Bool { false }
    var isPossible: Bool {
        self.isValid && (self.state == .ready || self.state == .processing)
    }

    init(inputs: _GestureInputs) {
        self.view = inputs.view
    }

    func locationInView(_ location: CGPoint) -> CGPoint {
        if let view {
            let transform = view.transformByRoot.inverted()
            return location.applying(transform)
        }
        return location
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
}

class _GestureRecognizer<Value> : _GestureHandler {
    var endedCallbacks: [EndedCallbacks<Value>]
    var changedCallbacks: [ChangedCallbacks<Value>]
    var pressableGestureCallbacks : [PressableGestureCallbacks<Value>]

    override init(inputs: _GestureInputs) {
        self.endedCallbacks = inputs.endedCallbacks.compactMap { $0 as? EndedCallbacks<Value> }
        self.changedCallbacks = inputs.changedCallbacks.compactMap { $0 as? ChangedCallbacks<Value> }
        self.pressableGestureCallbacks = inputs.pressableGestureCallbacks.compactMap { $0 as? PressableGestureCallbacks<Value> }
        super.init(inputs: inputs)
    }
}
