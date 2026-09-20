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
    private var enabledBodyIdentifiers: Set<ObjectIdentifier> = []
    private var activeConstraintIdentifiers: Set<ObjectIdentifier> = []
    private var contactNeighbors: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
    private var colliderSnapshots: [ObjectIdentifier: _RigidBodyColliderSnapshot] = [:]

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

    /// Registers a body unless it or another owner of its collider is present.
    @discardableResult
    public func add(_ body: RigidBody) -> Bool {
        guard !bodyStorage.contains(where: { $0.collider === body.collider }) else {
            return false
        }
        bodyStorage.append(body)
        collisionSpace.add(body.collider)
        if body.isEnabled {
            enabledBodyIdentifiers.insert(ObjectIdentifier(body))
            colliderSnapshots[ObjectIdentifier(body)] = _RigidBodyColliderSnapshot(body.collider)
        }
        return true
    }

    @discardableResult
    public func remove(_ body: RigidBody) -> Bool {
        guard let index = bodyStorage.firstIndex(of: body) else { return false }
        wakeContactNeighbors(of: body)
        bodyStorage.remove(at: index)
        collisionSpace.remove(body.collider)
        let identifier = ObjectIdentifier(body)
        enabledBodyIdentifiers.remove(identifier)
        colliderSnapshots.removeValue(forKey: identifier)
        for neighbor in contactNeighbors.removeValue(forKey: identifier) ?? [] {
            contactNeighbors[neighbor]?.remove(identifier)
        }
        constraintStorage.removeAll { constraint in
            guard constraint.bodyA === body || constraint.bodyB === body else {
                return false
            }
            if constraint.isEnabled || activeConstraintIdentifiers.contains(ObjectIdentifier(constraint)) {
                wakeBodies(connectedTo: constraint)
            }
            activeConstraintIdentifiers.remove(ObjectIdentifier(constraint))
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
        if constraint.isEnabled && constraint.bodyA.isEnabled && bodyStorage.contains(constraint.bodyA) &&
            (constraint.bodyB.map { $0.isEnabled && bodyStorage.contains($0) } ?? true) {
            activeConstraintIdentifiers.insert(identifier)
        }
        return true
    }

    @discardableResult
    public func remove(_ constraint: any RigidBodyConstraint) -> Bool {
        let identifier = ObjectIdentifier(constraint)
        guard let index = constraintStorage.firstIndex(where: {
            ObjectIdentifier($0) == identifier
        }) else { return false }
        constraintStorage.remove(at: index)
        if constraint.isEnabled || activeConstraintIdentifiers.contains(identifier) {
            wakeBodies(connectedTo: constraint)
        }
        activeConstraintIdentifiers.remove(identifier)
        return true
    }

    private func wakeBodies(connectedTo constraint: any RigidBodyConstraint) {
        for body in bodyStorage
        where body.isEnabled && body.motionType == .dynamic &&
            (constraint.bodyA === body || constraint.bodyB === body) {
            body.wakeUp()
        }
    }

    private func wakeContactNeighbors(of body: RigidBody) {
        guard body.isEnabled || enabledBodyIdentifiers.contains(ObjectIdentifier(body)) else { return }
        // Query an enabled copy so direct collider flag changes do not hide
        // supports disabled before their first step. Never toggle live state.
        let current = _RigidBodyColliderSnapshot(body.collider)
        var overlapping = Set(collisionSpace.overlaps(with: current.makeCollider()))
        if let previous = colliderSnapshots[ObjectIdentifier(body)], previous != current {
            // Contacts formed during CCD/substeps may not be in the initial
            // contact graph. Check the support's last solved geometry as well.
            overlapping.formUnion(collisionSpace.overlaps(with: previous.makeCollider()))
        }
        let previous = contactNeighbors[ObjectIdentifier(body)] ?? []
        for neighbor in bodyStorage
        where neighbor !== body && neighbor.isEnabled && neighbor.motionType == .dynamic &&
            (previous.contains(ObjectIdentifier(neighbor)) || overlapping.contains(neighbor.collider)) {
            neighbor.wakeUp()
        }
    }

    private func updateActivationState() {
        let enabled = Set(bodyStorage.filter(\.isEnabled).map(ObjectIdentifier.init))
        for body in bodyStorage {
            let identifier = ObjectIdentifier(body)
            if enabledBodyIdentifiers.contains(identifier) && !body.isEnabled {
                wakeContactNeighbors(of: body)
                colliderSnapshots.removeValue(forKey: identifier)
            } else if body.isEnabled,
                      let previous = colliderSnapshots[identifier],
                      previous != _RigidBodyColliderSnapshot(body.collider) {
                // A still-enabled support can disappear through a transform,
                // primitive, or filter edit. Solver motion is already captured
                // after each step, so only external edits reach this branch.
                wakeContactNeighbors(of: body)
                if body.motionType == .dynamic { body.wakeUp() }
            }
        }
        var activeConstraints: Set<ObjectIdentifier> = []
        for constraint in constraintStorage {
            let identifier = ObjectIdentifier(constraint)
            let active = constraint.isEnabled && enabled.contains(ObjectIdentifier(constraint.bodyA)) &&
                (constraint.bodyB.map { enabled.contains(ObjectIdentifier($0)) } ?? true)
            if active {
                activeConstraints.insert(identifier)
            } else if activeConstraintIdentifiers.contains(identifier) {
                wakeBodies(connectedTo: constraint)
            }
        }
        enabledBodyIdentifiers = enabled
        activeConstraintIdentifiers = activeConstraints
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
        guard timeStep.isFinite, timeStep > .zero, let solver else { return }
        updateActivationState()
        let context = solverContext(timeStep: timeStep)
        contactNeighbors.removeAll(keepingCapacity: true)
        for contact in context.contacts {
            let a = ObjectIdentifier(contact.bodyA), b = ObjectIdentifier(contact.bodyB)
            contactNeighbors[a, default: []].insert(b)
            contactNeighbors[b, default: []].insert(a)
        }
        solver.solve(context)
        for body in bodyStorage where body.isEnabled {
            colliderSnapshots[ObjectIdentifier(body)] = _RigidBodyColliderSnapshot(body.collider)
        }
    }
}

private struct _RigidBodyColliderSnapshot: Equatable {
    let primitive: any CollisionPrimitive
    let transform: Transform
    let filter: CollisionFilter

    init(_ collider: Collider) {
        primitive = collider.primitive
        transform = collider.transform
        filter = collider.filter
    }

    func makeCollider() -> Collider {
        Collider(primitive: primitive, transform: transform, filter: filter)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.transform == rhs.transform && lhs.filter == rhs.filter &&
            AnyHashable(lhs.primitive) == AnyHashable(rhs.primitive)
    }
}
