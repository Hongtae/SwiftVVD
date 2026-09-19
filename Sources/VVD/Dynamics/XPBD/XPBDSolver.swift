//
//  File: XPBDSolver.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Immutable input assembled by `XPBDSimulator` for one solver step.
public struct XPBDSolverContext {
    public let timeStep: Scalar
    public let gravity: Vector3
    public let bodies: [any XPBDBody]
    public let constraints: [any XPBDConstraint]

    public init(timeStep: Scalar,
                gravity: Vector3,
                bodies: [any XPBDBody],
                constraints: [any XPBDConstraint]) {
        self.timeStep = timeStep
        self.gravity = gravity
        self.bodies = bodies
        self.constraints = constraints
    }
}

/// Strategy interface for XPBD prediction, projection, and velocity update.
public protocol XPBDSolver: AnyObject {
    func solve(_ context: XPBDSolverContext)
}
