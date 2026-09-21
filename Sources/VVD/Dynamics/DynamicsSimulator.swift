//
//  File: DynamicsSimulator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Coordinates the independent rigid-body and XPBD simulation pipelines.
public final class DynamicsSimulator {
    public let rigidBodies: RigidBodySimulator
    public let xpbd: XPBDSimulator

    public init(rigidBodies: RigidBodySimulator = RigidBodySimulator(),
                xpbd: XPBDSimulator = XPBDSimulator()) {
        self.rigidBodies = rigidBodies
        self.xpbd = xpbd
    }

    public func step(timeStep: Scalar) {
        guard timeStep.isFinite, timeStep > .zero else { return }
        rigidBodies.step(timeStep: timeStep)
        xpbd.step(timeStep: timeStep)
    }
}
