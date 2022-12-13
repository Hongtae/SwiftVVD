//
//  File: Transaction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct Transaction {
    public init() {
        self.animation = nil
        self.isContinuous = false
        self.disablesAnimations = false
    }

    public var isContinuous: Bool

    public init(animation: Animation?) {
        self.animation = animation
        self.isContinuous = false
        self.disablesAnimations = false
    }

    public var animation: Animation?
    public var disablesAnimations: Bool
}
