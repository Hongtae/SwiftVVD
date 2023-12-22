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
    weak var viewProxy: ViewProxy?

    func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        f.subtracting(self.type)
    }

    var type: _PrimitiveGestureTypes { .none }
    var isValid: Bool { false }

    init(inputs: _GestureInputs) {
        self.viewProxy = inputs.viewProxy
    }

    @MainActor
    func began(deviceID: Int, buttonID: Int, location: CGPoint) {
    }

    @MainActor
    func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
    }

    @MainActor
    func ended(deviceID: Int, buttonID: Int) {
    }

    @MainActor
    func cancelled(deviceID: Int, buttonID: Int) {
    }

    @MainActor
    func reset() {
    }
}

class _GestureRecognizer<Value> : _GestureHandler {
    let endedCallbacks: [EndedCallbacks<Value>]
    let changedCallbacks: [ChangedCallbacks<Value>]
    let pressableGestureCallbacks : [PressableGestureCallbacks<Value>]

    override init(inputs: _GestureInputs) {
        self.endedCallbacks = inputs.endedCallbacks.compactMap { $0 as? EndedCallbacks<Value> }
        self.changedCallbacks = inputs.changedCallbacks.compactMap { $0 as? ChangedCallbacks<Value> }
        self.pressableGestureCallbacks = inputs.pressableGestureCallbacks.compactMap { $0 as? PressableGestureCallbacks<Value> }
        super.init(inputs: inputs)
    }
}
