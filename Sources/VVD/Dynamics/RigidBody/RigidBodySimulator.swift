//
//  File: RigidBodySimulator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Owns rigid bodies and assembles collision and joint data for a solver.
public final class RigidBodySimulator {
    public let collisionSpace: CollisionSpace
    public var gravity: Vector3
    public var solver: (any RigidBodySolver)?

    private var bodyStorage: [RigidBody]
    private var constraintStorage: [any RigidBodyConstraint]

    public var bodies: [RigidBody] { bodyStorage }
    public var constraints: [any RigidBodyConstraint] { constraintStorage }

    public init(collisionSpace: CollisionSpace = CollisionSpace(),
                gravity: Vector3 = Vector3(0, -9.81, 0),
                solver: (any RigidBodySolver)? =
                    SequentialImpulseRigidBodySolver()) {
        self.collisionSpace = collisionSpace
        self.gravity = gravity
        self.solver = solver
        self.bodyStorage = []
        self.constraintStorage = []
    }

    @discardableResult
    public func add(_ body: RigidBody) -> Bool {
        guard !bodyStorage.contains(body) else { return false }
        bodyStorage.append(body)
        collisionSpace.add(body.collider)
        return true
    }

    @discardableResult
    public func remove(_ body: RigidBody) -> Bool {
        guard let index = bodyStorage.firstIndex(of: body) else { return false }
        let overlappingColliders = Set(collisionSpace.overlaps(with: body.collider))
        bodyStorage.remove(at: index)
        collisionSpace.remove(body.collider)

        // Waking direct neighbors activates their remaining islands next step.
        for neighbor in bodyStorage
        where neighbor.isEnabled && neighbor.motionType == .dynamic &&
            overlappingColliders.contains(neighbor.collider) {
            neighbor.wakeUp()
        }
        constraintStorage.removeAll { constraint in
            guard constraint.bodyA === body || constraint.bodyB === body else {
                return false
            }
            wakeBodies(connectedTo: constraint)
            return true
        }
        return true
    }

    @discardableResult
    public func add(_ constraint: any RigidBodyConstraint) -> Bool {
        let identifier = ObjectIdentifier(constraint)
        guard !constraintStorage.contains(where: { ObjectIdentifier($0) == identifier }) else {
            return false
        }
        constraintStorage.append(constraint)
        return true
    }

    @discardableResult
    public func remove(_ constraint: any RigidBodyConstraint) -> Bool {
        let identifier = ObjectIdentifier(constraint)
        guard let index = constraintStorage.firstIndex(where: {
            ObjectIdentifier($0) == identifier
        }) else { return false }
        constraintStorage.remove(at: index)
        wakeBodies(connectedTo: constraint)
        return true
    }

    private func wakeBodies(connectedTo constraint: any RigidBodyConstraint) {
        guard constraint.isEnabled else { return }
        for body in bodyStorage
        where body.isEnabled && body.motionType == .dynamic &&
            (constraint.bodyA === body || constraint.bodyB === body) {
            body.wakeUp()
        }
    }

    /// Creates the solver input for a step without advancing simulation state.
    public func solverContext(timeStep: Scalar) -> RigidBodySolverContext {
        let bodyByCollider = Dictionary(uniqueKeysWithValues: bodyStorage.map {
            ($0.collider, $0)
        })
        let contacts = collisionSpace.collisionPairs().compactMap { pair -> RigidBodyContact? in
            guard let bodyA = bodyByCollider[pair.colliderA],
                  let bodyB = bodyByCollider[pair.colliderB],
                  let manifold = pair.worldContactManifold,
                  !manifold.isEmpty else {
                return nil
            }
            return RigidBodyContact(bodyA: bodyA,
                                    bodyB: bodyB,
                                    manifold: manifold)
        }
        return RigidBodySolverContext(timeStep: timeStep,
                                      gravity: gravity,
                                      bodies: bodyStorage,
                                      contacts: contacts,
                                      constraints: constraintStorage.filter(\.isEnabled),
                                      collisionSpace: collisionSpace)
    }

    /// Delegates one simulation step to the configured solver.
    public func step(timeStep: Scalar) {
        guard timeStep > .zero else { return }
        solver?.solve(solverContext(timeStep: timeStep))
    }
}
