//
//  File: RigidBodySolver.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Solver-ready contact data expressed in the simulator's coordinate space.
public struct RigidBodyContact {
    public let bodyA: RigidBody
    public let bodyB: RigidBody
    public let manifold: ContactManifold

    /// The symmetric material pair resolved for this contact.
    public var material: PhysicsMaterial {
        bodyA.material.combined(with: bodyB.material)
    }

    public init(bodyA: RigidBody,
                bodyB: RigidBody,
                manifold: ContactManifold) {
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.manifold = manifold
    }
}

/// Immutable input assembled by `RigidBodySimulator` for one solver step.
public struct RigidBodySolverContext {
    public let timeStep: Scalar
    public let gravity: Vector3
    public let bodies: [RigidBody]
    public let contacts: [RigidBodyContact]
    public let constraints: [any RigidBodyConstraint]

    public init(timeStep: Scalar,
                gravity: Vector3,
                bodies: [RigidBody],
                contacts: [RigidBodyContact],
                constraints: [any RigidBodyConstraint]) {
        self.timeStep = timeStep
        self.gravity = gravity
        self.bodies = bodies
        self.contacts = contacts
        self.constraints = constraints
    }
}

/// Strategy interface for integration and rigid-body constraint solving.
public protocol RigidBodySolver: AnyObject {
    func solve(_ context: RigidBodySolverContext)
}
