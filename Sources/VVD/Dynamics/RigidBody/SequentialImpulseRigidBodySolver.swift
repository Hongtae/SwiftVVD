//
//  File: SequentialImpulseRigidBodySolver.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Integrates rigid bodies and resolves contacts and joint rows with sequential
/// impulses.
public final class SequentialImpulseRigidBodySolver: RigidBodySolver {
    /// Number of velocity-constraint passes performed for each step.
    public var velocityIterations: Int
    /// Fraction of contact penetration converted to separating velocity.
    public var positionCorrectionFactor: Scalar
    /// Penetration ignored by velocity-level position correction.
    public var penetrationSlop: Scalar
    /// Closing speed below which restitution is suppressed.
    public var restitutionVelocityThreshold: Scalar
    /// Upper bound for penetration-correction velocity.
    public var maximumBiasVelocity: Scalar
    /// Whether matching contact impulses are carried into the next step.
    public var isWarmStartingEnabled: Bool
    /// Whether low-velocity dynamic islands may stop participating in steps.
    public var isSleepingEnabled: Bool
    /// Maximum linear speed eligible for sleeping.
    public var linearSleepThreshold: Scalar
    /// Maximum angular speed eligible for sleeping.
    public var angularSleepThreshold: Scalar
    /// Continuous low-velocity duration required before an island sleeps.
    public var sleepDelay: Scalar

    /// Scene policy; bodies still opt in individually through their CCD flag.
    public var ccdConfiguration: CCDConfiguration
    public private(set) var ccdStatistics = CCDStatistics()

    /// Number of contact features retained by the most recent valid step.
    public var cachedContactCount: Int { contactCache.count }

    private var contactCache: [_SequentialContactCacheKey:
        _SequentialCachedContactImpulse]

    public init(velocityIterations: Int = 8,
                positionCorrectionFactor: Scalar = 0.2,
                penetrationSlop: Scalar = 0.005,
                restitutionVelocityThreshold: Scalar = 1.0,
                maximumBiasVelocity: Scalar = 10.0,
                isWarmStartingEnabled: Bool = true,
                isSleepingEnabled: Bool = true,
                linearSleepThreshold: Scalar = 0.05,
                angularSleepThreshold: Scalar = 0.05,
                sleepDelay: Scalar = 0.5,
                ccdConfiguration: CCDConfiguration = .default) {
        self.ccdConfiguration = ccdConfiguration
        self.velocityIterations = velocityIterations
        self.positionCorrectionFactor = positionCorrectionFactor
        self.penetrationSlop = penetrationSlop
        self.restitutionVelocityThreshold = restitutionVelocityThreshold
        self.maximumBiasVelocity = maximumBiasVelocity
        self.isWarmStartingEnabled = isWarmStartingEnabled
        self.isSleepingEnabled = isSleepingEnabled
        self.linearSleepThreshold = linearSleepThreshold
        self.angularSleepThreshold = angularSleepThreshold
        self.sleepDelay = sleepDelay
        self.contactCache = [:]
    }

    /// Discards every impulse retained for persistent contacts.
    public func removeAllCachedContacts() {
        contactCache.removeAll(keepingCapacity: true)
    }

    public func solve(_ context: RigidBodySolverContext) {
        guard context.timeStep.isFinite, context.timeStep > 0 else { return }
        ccdStatistics = CCDStatistics()
        let count = Swift.max(ccdConfiguration.substepCount, 1)
        let timeStep = context.timeStep / Scalar(count)
        guard timeStep > 0 else { return }
        for index in 0..<count {
            let contacts = index == 0 ? context.contacts : currentContacts(context)
            let substep = RigidBodySolverContext(timeStep: timeStep,
                gravity: context.gravity, bodies: context.bodies, contacts: contacts,
                constraints: context.constraints, collisionSpace: context.collisionSpace)
            solveSubstep(substep)
        }
        // External forces act for the entire caller-supplied interval.
        for body in context.bodies { body.removeAllForces() }
    }

    private func solveSubstep(_ context: RigidBodySolverContext) {
        let timeStep = context.timeStep
        let identifiers = Set(context.bodies.map(ObjectIdentifier.init))
        let islands = makeDynamicIslands(context, bodyIdentifiers: identifiers,
                                         timeStep: timeStep)
        var active = activateIslands(islands)
        integrateForces(context.bodies, gravity: context.gravity,
                        timeStep: timeStep, activeBodyIdentifiers: active)
        var contacts = makeContactConstraints(context.contacts,
            bodyIdentifiers: identifiers, activeBodyIdentifiers: active, timeStep: timeStep)
        var joints = makeJointRows(context.constraints, bodyIdentifiers: identifiers,
                                   activeBodyIdentifiers: active, timeStep: timeStep)
        if isWarmStartingEnabled {
            for contact in contacts { contact.warmStart() }
        }
        solveRows(contacts: &contacts, joints: &joints)
        updateContactCache(contacts, contacts: context.contacts, bodyIdentifiers: identifiers)

        // All trajectories below use velocities AFTER contacts and joints solve.
        var frozen: Set<ObjectIdentifier> = []
        var participants: Set<ObjectIdentifier> = []
        let hasCCD = context.collisionSpace != nil && context.bodies.contains {
            $0.isEnabled && $0.motionType == .dynamic && $0.isContinuousCollisionDetectionEnabled
        }
        let mode: CCDConfiguration.Mode = hasCCD ? ccdConfiguration.mode : .discrete
        if mode == .speculative || mode == .hybrid {
            let impacts = discoverImpacts(context, islands: islands, active: &active,
                                          frozen: frozen, participants: participants, timeStep: timeStep)
            trackParticipants(impacts, into: &participants)
            let predictive = makeCCDConstraints(impacts, speculative: true, timeStep: timeStep)
            ccdStatistics.predictiveContactCount += predictive.count
            // Rebuild ordinary rows to include newly awakened islands without
            // applying cached impulses a second time.
            if !predictive.isEmpty {
                contacts = makeContactConstraints(currentContacts(context),
                    bodyIdentifiers: identifiers, activeBodyIdentifiers: active,
                    timeStep: timeStep, usesCache: false)
                contacts.append(contentsOf: predictive)
                joints = makeJointRows(context.constraints, bodyIdentifiers: identifiers,
                                      activeBodyIdentifiers: active, timeStep: timeStep)
                solveRows(contacts: &contacts, joints: &joints)
            }
            for impact in impacts where impact.hit == nil {
                freeze(impact, into: &frozen)
            }
        }
        if mode == .discrete || mode == .speculative || context.collisionSpace == nil {
            integrateTransforms(context.bodies, timeStep: timeStep,
                                activeBodyIdentifiers: active, frozen: frozen)
        } else {
            advanceContinuously(context, islands: islands, active: &active,
                                frozen: &frozen, participants: &participants, resolvesImpacts: mode == .timeOfImpact)
        }
        updateSleeping(islands, activeBodyIdentifiers: active, timeStep: timeStep)
    }

    private func solveRows(contacts: inout [_SequentialContactConstraint],
                           joints: inout [_SequentialJointRow]) {
        for _ in 0..<Swift.max(velocityIterations, 0) {
            for index in joints.indices { joints[index].solve() }
            for index in contacts.indices { contacts[index].solve() }
        }
    }

    private func currentContacts(_ context: RigidBodySolverContext) -> [RigidBodyContact] {
        guard let space = context.collisionSpace else { return context.contacts }
        let owners = Dictionary(uniqueKeysWithValues: context.bodies.map { ($0.collider, $0) })
        return space.collisionPairs().compactMap { pair in
            guard let a = owners[pair.colliderA], let b = owners[pair.colliderB],
                  let manifold = pair.worldContactManifold, !manifold.isEmpty else { return nil }
            return RigidBodyContact(bodyA: a, bodyB: b, manifold: manifold)
        }
    }

    private func integrateForces(_ bodies: [RigidBody],
                                 gravity: Vector3,
                                 timeStep: Scalar,
                                 activeBodyIdentifiers: Set<ObjectIdentifier>) {
        let finiteGravity = gravity.isFiniteVector ? gravity : .zero
        for body in bodies
        where body.isEnabled && body.motionType == .dynamic &&
            activeBodyIdentifiers.contains(ObjectIdentifier(body)) {
            let forces = body.accumulatedForces
            if forces.force.isFiniteVector {
                body.linearVelocity += forces.force * (body.inverseMass * timeStep)
            }
            if forces.torque.isFiniteVector {
                body.angularVelocity += forces.torque
                    .applying(body.worldInverseInertiaTensor) * timeStep
            }
            if body.gravityScale.isFinite {
                body.linearVelocity += finiteGravity * (body.gravityScale * timeStep)
            }

            body.linearVelocity *= dampingFactor(body.linearDamping,
                                                 timeStep: timeStep)
            body.angularVelocity *= dampingFactor(body.angularDamping,
                                                  timeStep: timeStep)
        }
    }

    private func discoverImpacts(
        _ context: RigidBodySolverContext,
        islands: [_SequentialBodyIsland],
        active: inout Set<ObjectIdentifier>,
        frozen: Set<ObjectIdentifier>,
        participants: Set<ObjectIdentifier>,
        timeStep: Scalar
    ) -> [_SequentialCCDImpact] {
        while true {
            let impacts = ccdImpacts(context, active: active, frozen: frozen, participants: participants, timeStep: timeStep)
            let sleeping = Set(impacts.flatMap { [$0.bodyA, $0.bodyB].compactMap { body in
                body?.isSleeping == true ? body.map(ObjectIdentifier.init) : nil
            } })
            var newlyActive: Set<ObjectIdentifier> = []
            for island in islands where island.bodies.contains(where: {
                sleeping.contains(ObjectIdentifier($0))
            }) {
                for body in island.bodies {
                    if active.insert(ObjectIdentifier(body)).inserted {
                        newlyActive.insert(ObjectIdentifier(body))
                    }
                    if body.isSleeping { body.wakeUp() }
                }
            }
            guard !newlyActive.isEmpty else { return impacts }
            // A newly awakened body receives this substep's force exactly once.
            integrateForces(context.bodies, gravity: context.gravity,
                timeStep: context.timeStep, activeBodyIdentifiers: newlyActive)
            let identifiers = Set(context.bodies.map(ObjectIdentifier.init))
            var contacts = makeContactConstraints(currentContacts(context),
                bodyIdentifiers: identifiers, activeBodyIdentifiers: active,
                timeStep: context.timeStep, usesCache: false)
            var joints = makeJointRows(context.constraints, bodyIdentifiers: identifiers,
                activeBodyIdentifiers: active, timeStep: context.timeStep)
            solveRows(contacts: &contacts, joints: &joints)
        }
    }

    private func ccdImpacts(_ context: RigidBodySolverContext,
                            active: Set<ObjectIdentifier>,
                            frozen: Set<ObjectIdentifier>,
                            participants: Set<ObjectIdentifier>,
                            timeStep: Scalar) -> [_SequentialCCDImpact] {
        guard let space = context.collisionSpace else { return [] }
        let colliders = space.colliders
        let configuredTolerance = ccdConfiguration.distanceTolerance
        let allowedTravel = configuredTolerance.isFinite && configuredTolerance > 0
            ? Swift.max(configuredTolerance, Scalar.ulpOfOne * 64) : Scalar(1.0e-6)
        let owners = Dictionary(uniqueKeysWithValues: context.bodies.map { ($0.collider, $0) })
        let motions = colliders.map { collider -> CollisionMotion in
            guard let body = owners[collider], body.isEnabled,
                  body.motionType != .static, !body.isSleeping,
                  !frozen.contains(ObjectIdentifier(body)),
                  body.motionType == .kinematic || active.contains(ObjectIdentifier(body)),
                  body.linearVelocity.isFiniteVector, body.angularVelocity.isFiniteVector
            else { return CollisionMotion(start: collider.transform) }
            var angular = ccdConfiguration.motion == .translationAndRotation
                ? body.angularVelocity * timeStep : .zero
            if let sphere = collider.primitive as? Sphere,
               sphere.center == body.massProperties.centerOfMass { angular = .zero }
            return CollisionMotion(start: body.transform,
                translation: body.linearVelocity * timeStep, angularDisplacement: angular,
                localPivot: body.massProperties.centerOfMass)
        }
        let bounds = colliders.indices.map { motions[$0].sweptBounds(of: colliders[$0].primitive) }
        let bvh = BVH(bounds.enumerated().map { BVH.Element(bounds: $0.element, primitiveIndex: $0.offset) })
        let unbounded = bounds.indices.filter { bounds[$0].isNull }
        var visited: Set<_SequentialCCDPair> = []
        var impacts: [_SequentialCCDImpact] = []
        for indexA in colliders.indices {
            guard let bodyA = owners[colliders[indexA]], bodyA.isEnabled,
                  bodyA.motionType == .dynamic,
                  bodyA.isContinuousCollisionDetectionEnabled || participants.contains(ObjectIdentifier(bodyA))
            else { continue }
            let candidates = bounds[indexA].isNull ? Array(colliders.indices)
                : (bvh.primitiveIndices(overlapping: bounds[indexA]) + unbounded).sorted()
            for indexB in candidates where indexA != indexB {
                let colliderB = colliders[indexB]
                guard colliders[indexA].canCollide(with: colliderB),
                      visited.insert(_SequentialCCDPair(indexA, indexB)).inserted else { continue }
                let moveA = motions[indexA], moveB = motions[indexB]
                if moveA.translation == moveB.translation &&
                    moveA.angularDisplacement == .zero && moveB.angularDisplacement == .zero { continue }
                ccdStatistics.sweepCount += 1
                var result = space.algorithms.sweepMotion(colliders[indexA].primitive,
                    motionA: moveA, colliderB.primitive, motionB: moveB,
                    distanceTolerance: ccdConfiguration.distanceTolerance,
                    maximumIterations: ccdConfiguration.maximumSweepIterations)
                if case .hit(let hit) = result, hit.fraction == 0 {
                    let centerA = moveA.localPivot.applying(moveA.start)
                    let centerB = moveB.localPivot.applying(moveB.start)
                    let velocityA = moveA.translation + Vector3.cross(moveA.angularDisplacement, hit.pointOnA - centerA)
                    let velocityB = moveB.translation + Vector3.cross(moveB.angularDisplacement, hit.pointOnB - centerB)
                    if Vector3.dot(velocityA - velocityB, hit.normal) <= allowedTravel {
                        if moveA.angularDisplacement == .zero && moveB.angularDisplacement == .zero {
                            // Remaining normal travel is within the configured
                            // spatial error, or the pair is separating. Avoid
                            // repeated zero-time impulses for solver roundoff.
                            continue
                        }
                        // A rotating, initially touching pair could meet again. Without
                        // a positive separating interval, conservatively stop its motion.
                        result = .inconclusive(safeFraction: 0)
                    }
                }
                if result == .miss { continue }
                if case .unsupported = result { ccdStatistics.unsupportedPairCount += 1 }
                if case .inconclusive = result { ccdStatistics.inconclusiveSweepCount += 1 }
                let hit: MotionSweepHit?
                if case .hit(let witness) = result { hit = witness } else { hit = nil }
                impacts.append(_SequentialCCDImpact(bodyA: bodyA, bodyB: owners[colliderB],
                    fraction: result.safeFraction, hit: hit, motionA: moveA, motionB: moveB))
            }
        }
        // Stable registration order breaks equal-TOI ties; hash iteration is never used.
        return impacts.enumerated().sorted {
            if $0.element.fraction == $1.element.fraction { return $0.offset < $1.offset }
            return $0.element.fraction < $1.element.fraction
        }.map(\.element)
    }

    private func advanceContinuously(_ context: RigidBodySolverContext,
                                      islands: [_SequentialBodyIsland],
                                      active: inout Set<ObjectIdentifier>,
                                      frozen: inout Set<ObjectIdentifier>,
                                      participants: inout Set<ObjectIdentifier>,
                                      resolvesImpacts: Bool) {
        var remaining = context.timeStep
        var iterations = 0
        let identifiers = Set(context.bodies.map(ObjectIdentifier.init))
        while remaining > 0 {
            let impacts = discoverImpacts(context, islands: islands, active: &active,
                                          frozen: frozen, participants: participants, timeStep: remaining)
            guard let first = impacts.first else {
                integrateTransforms(context.bodies, timeStep: remaining,
                                    activeBodyIdentifiers: active, frozen: frozen)
                break
            }
            let elapsed = remaining * first.fraction
            integrateTransforms(context.bodies, timeStep: elapsed,
                                activeBodyIdentifiers: active, frozen: frozen)
            remaining -= elapsed
            let simultaneous = impacts.filter { $0.fraction == first.fraction }
            trackParticipants(simultaneous, into: &participants)
            let canResolve = resolvesImpacts && iterations < Swift.max(ccdConfiguration.maximumImpactIterations, 0)
            if resolvesImpacts && !canResolve { ccdStatistics.reachedImpactLimit = true }
            let requiresClamping = simultaneous.contains { impact in
                impact.hit == nil || frozen.contains(ObjectIdentifier(impact.bodyA)) ||
                    (impact.bodyB.map { frozen.contains(ObjectIdentifier($0)) } ?? false)
            }
            // A previously stopped pose no longer follows its retained velocity.
            // Propagate clamping instead of solving against that stale motion.
            if !canResolve || requiresClamping {
                for impact in simultaneous { freeze(impact, into: &frozen) }
            } else {
                var contacts = makeContactConstraints(currentContacts(context),
                    bodyIdentifiers: identifiers, activeBodyIdentifiers: active,
                    timeStep: context.timeStep, usesCache: false)
                // The explicit witness is needed even when the distance tolerance
                // leaves a small positive gap and no discrete manifold exists yet.
                contacts.append(contentsOf: makeCCDConstraints(simultaneous,
                    speculative: false, timeStep: context.timeStep))
                var joints = makeJointRows(context.constraints, bodyIdentifiers: identifiers,
                    activeBodyIdentifiers: active, timeStep: context.timeStep)
                solveRows(contacts: &contacts, joints: &joints)
                ccdStatistics.impactCount += simultaneous.count
                iterations += 1
            }
            // Impulses cached at the original poses must not be replayed after impacts.
            contactCache.removeAll(keepingCapacity: true)
        }
    }

    private func trackParticipants(_ impacts: [_SequentialCCDImpact],
                                   into participants: inout Set<ObjectIdentifier>) {
        for impact in impacts {
            participants.insert(ObjectIdentifier(impact.bodyA))
            if let body = impact.bodyB, body.motionType == .dynamic {
                participants.insert(ObjectIdentifier(body))
            }
        }
    }

    private func freeze(_ impact: _SequentialCCDImpact,
                         into frozen: inout Set<ObjectIdentifier>) {
        // Clamping retains velocity for the next substep, including kinematic
        // velocity, but stops the pose of BOTH moving participants this substep.
        for body in [impact.bodyA, impact.bodyB].compactMap({ $0 }) where body.motionType != .static {
            if frozen.insert(ObjectIdentifier(body)).inserted { ccdStatistics.clampedBodyCount += 1 }
        }
    }

    private func makeCCDConstraints(_ impacts: [_SequentialCCDImpact],
                                    speculative: Bool,
                                    timeStep: Scalar) -> [_SequentialContactConstraint] {
        impacts.compactMap { impact in
            guard let hit = impact.hit else { return nil }
            var pointA = hit.pointOnA, pointB = hit.pointOnB
            if speculative {
                pointA = pointA.applying(impact.motionA.transform(at: hit.fraction).inverted())
                    .applying(impact.motionA.start)
                pointB = pointB.applying(impact.motionB.transform(at: hit.fraction).inverted())
                    .applying(impact.motionB.start)
            }
            let offsetA = pointA - impact.bodyA.massProperties.centerOfMass.applying(impact.bodyA.transform)
            let offsetB = impact.bodyB.map { pointB - $0.massProperties.centerOfMass.applying($0.transform) } ?? .zero
            let velocity = _sequentialRelativeVelocity(bodyA: impact.bodyA, bodyB: impact.bodyB,
                                                      offsetA: offsetA, offsetB: offsetB)
            let material = impact.bodyA.material.combined(with: impact.bodyB?.material ?? .default)
            let normalVelocity = Vector3.dot(velocity, hit.normal)
            let bias: Scalar
            if speculative {
                bias = Swift.max(Vector3.dot(pointB - pointA, hit.normal), 0) / timeStep
            } else {
                bias = normalVelocity < -sanitizedNonnegative(restitutionVelocityThreshold)
                    ? material.restitution * normalVelocity : 0
            }
            return _SequentialContactConstraint(cacheKey: nil,
                bodyA: impact.bodyA, bodyB: impact.bodyB, offsetA: offsetA, offsetB: offsetB,
                normal: hit.normal, normalBias: bias, friction: speculative ? 0 : material.friction,
                initialRelativeVelocity: velocity, cachedImpulse: nil)
        }
    }

    private func makeContactConstraints(
        _ contacts: [RigidBodyContact],
        bodyIdentifiers: Set<ObjectIdentifier>,
        activeBodyIdentifiers: Set<ObjectIdentifier>,
        timeStep: Scalar,
        usesCache: Bool = true
    ) -> [_SequentialContactConstraint] {
        let correctionFactor = sanitizedNonnegative(positionCorrectionFactor)
            .clamp(min: .zero, max: Scalar(1))
        let slop = sanitizedNonnegative(penetrationSlop)
        let restitutionThreshold = sanitizedNonnegative(
            restitutionVelocityThreshold)
        let maximumBias = sanitizedNonnegative(maximumBiasVelocity)

        var constraints: [_SequentialContactConstraint] = []
        for pair in contacts {
            guard bodyIdentifiers.contains(ObjectIdentifier(pair.bodyA)),
                  bodyIdentifiers.contains(ObjectIdentifier(pair.bodyB)),
                  pair.bodyA.isEnabled,
                  pair.bodyB.isEnabled,
                  _sequentialHasActiveDynamicBody(
                    pair.bodyA,
                    pair.bodyB,
                    activeBodyIdentifiers: activeBodyIdentifiers)
            else { continue }

            let material = pair.material
            let centerA = pair.bodyA.massProperties.centerOfMass
                .applying(pair.bodyA.transform)
            let centerB = pair.bodyB.massProperties.centerOfMass
                .applying(pair.bodyB.transform)

            for contact in pair.manifold.contacts {
                guard contact.pointOnA.isFiniteVector,
                      contact.pointOnB.isFiniteVector,
                      contact.normal.isFiniteVector,
                      contact.penetrationDepth.isFinite,
                      contact.normal.lengthSquared > Scalar.ulpOfOne
                else { continue }

                let normal = contact.normal.normalized()
                let offsetA = contact.pointOnA - centerA
                let offsetB = contact.pointOnB - centerB
                let initialVelocity = _sequentialRelativeVelocity(
                    bodyA: pair.bodyA,
                    bodyB: pair.bodyB,
                    offsetA: offsetA,
                    offsetB: offsetB)
                let initialNormalVelocity = Vector3.dot(initialVelocity, normal)
                let penetration = Swift.max(contact.penetrationDepth - slop,
                                            .zero)
                var correctionVelocity = correctionFactor * penetration / timeStep
                if maximumBias.isFinite {
                    correctionVelocity = Swift.min(correctionVelocity,
                                                   maximumBias)
                }
                let restitutionBias: Scalar
                if initialNormalVelocity < -restitutionThreshold {
                    restitutionBias = material.restitution * initialNormalVelocity
                } else {
                    restitutionBias = .zero
                }

                let cacheKey = _SequentialContactCacheKey(
                    bodyA: pair.bodyA,
                    bodyB: pair.bodyB,
                    featureID: contact.featureID)
                if let constraint = _SequentialContactConstraint(
                    cacheKey: cacheKey,
                    bodyA: pair.bodyA,
                    bodyB: pair.bodyB,
                    offsetA: offsetA,
                    offsetB: offsetB,
                    normal: normal,
                    normalBias: restitutionBias - correctionVelocity,
                    friction: material.friction,
                    initialRelativeVelocity: initialVelocity,
                    cachedImpulse: usesCache && isWarmStartingEnabled
                        ? contactCache[cacheKey] : nil) {
                    constraints.append(constraint)
                }
            }
        }
        return constraints
    }

    private func updateContactCache(
        _ constraints: [_SequentialContactConstraint],
        contacts: [RigidBodyContact],
        bodyIdentifiers: Set<ObjectIdentifier>
    ) {
        guard isWarmStartingEnabled else {
            contactCache.removeAll(keepingCapacity: true)
            return
        }

        var nextCache: [_SequentialContactCacheKey:
            _SequentialCachedContactImpulse] = [:]
        nextCache.reserveCapacity(constraints.count)
        for constraint in constraints {
            if let cacheKey = constraint.cacheKey {
                nextCache[cacheKey] = constraint.cachedImpulse
            }
        }
        for pair in contacts {
            guard pair.bodyA.isEnabled,
                  pair.bodyB.isEnabled,
                  bodyIdentifiers.contains(ObjectIdentifier(pair.bodyA)),
                  bodyIdentifiers.contains(ObjectIdentifier(pair.bodyB))
            else { continue }
            for contact in pair.manifold.contacts
            where contact.pointOnA.isFiniteVector &&
                contact.pointOnB.isFiniteVector &&
                contact.normal.isFiniteVector &&
                contact.penetrationDepth.isFinite &&
                contact.normal.lengthSquared > Scalar.ulpOfOne {
                let key = _SequentialContactCacheKey(
                    bodyA: pair.bodyA,
                    bodyB: pair.bodyB,
                    featureID: contact.featureID)
                if nextCache[key] == nil, let cached = contactCache[key] {
                    nextCache[key] = cached
                }
            }
        }
        contactCache = nextCache
    }

    private func makeJointRows(
        _ constraints: [any RigidBodyConstraint],
        bodyIdentifiers: Set<ObjectIdentifier>,
        activeBodyIdentifiers: Set<ObjectIdentifier>,
        timeStep: Scalar
    ) -> [_SequentialJointRow] {
        var rows: [_SequentialJointRow] = []
        for constraint in constraints where constraint.isEnabled {
            guard bodyIdentifiers.contains(ObjectIdentifier(constraint.bodyA)),
                  constraint.bodyB.map({
                      bodyIdentifiers.contains(ObjectIdentifier($0))
                  }) ?? true,
                  _sequentialHasActiveDynamicBody(
                    constraint.bodyA,
                    constraint.bodyB,
                    activeBodyIdentifiers: activeBodyIdentifiers)
            else { continue }
            for row in constraint.solverRows(timeStep: timeStep) {
                guard bodyIdentifiers.contains(ObjectIdentifier(row.bodyA)),
                      row.bodyB.map({
                          bodyIdentifiers.contains(ObjectIdentifier($0))
                      }) ?? true,
                      let solverRow = _SequentialJointRow(row)
                else { continue }
                rows.append(solverRow)
            }
        }
        return rows
    }

    private func makeDynamicIslands(
        _ context: RigidBodySolverContext,
        bodyIdentifiers: Set<ObjectIdentifier>,
        timeStep: Scalar
    ) -> [_SequentialBodyIsland] {
        var bodyByIdentifier: [ObjectIdentifier: RigidBody] = [:]
        var orderedBodies: [RigidBody] = []
        for body in context.bodies
        where body.isEnabled && body.motionType == .dynamic {
            let identifier = ObjectIdentifier(body)
            if bodyByIdentifier[identifier] == nil {
                bodyByIdentifier[identifier] = body
                orderedBodies.append(body)
            }
        }

        var adjacency: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
        var activationSeeds: Set<ObjectIdentifier> = []
        for body in orderedBodies {
            let identifier = ObjectIdentifier(body)
            adjacency[identifier] = []
            if !isSleepingEnabled || !body.allowsSleeping || !body.isSleeping {
                activationSeeds.insert(identifier)
            }
        }

        let wakePenetration = sanitizedNonnegative(penetrationSlop)
        for pair in context.contacts {
            guard pair.bodyA.isEnabled,
                  pair.bodyB.isEnabled,
                  bodyIdentifiers.contains(ObjectIdentifier(pair.bodyA)),
                  bodyIdentifiers.contains(ObjectIdentifier(pair.bodyB))
            else { continue }

            let identifierA = ObjectIdentifier(pair.bodyA)
            let identifierB = ObjectIdentifier(pair.bodyB)
            let dynamicA = bodyByIdentifier[identifierA] != nil
            let dynamicB = bodyByIdentifier[identifierB] != nil
            if dynamicA && dynamicB {
                adjacency[identifierA, default: []].insert(identifierB)
                adjacency[identifierB, default: []].insert(identifierA)
            }

            let deeplyPenetrating = pair.manifold.contacts.contains {
                $0.penetrationDepth.isFinite &&
                    $0.penetrationDepth > wakePenetration
            }
            if deeplyPenetrating {
                if dynamicA { activationSeeds.insert(identifierA) }
                if dynamicB { activationSeeds.insert(identifierB) }
            }
            if dynamicA && _sequentialIsMovingKinematic(pair.bodyB) {
                activationSeeds.insert(identifierA)
            }
            if dynamicB && _sequentialIsMovingKinematic(pair.bodyA) {
                activationSeeds.insert(identifierB)
            }
        }

        let linearThreshold = sanitizedNonnegative(linearSleepThreshold)
        let angularThreshold = sanitizedNonnegative(angularSleepThreshold)
        let biasThreshold = Swift.min(linearThreshold, angularThreshold)
        for constraint in context.constraints where constraint.isEnabled {
            let identifierA = ObjectIdentifier(constraint.bodyA)
            guard bodyIdentifiers.contains(identifierA),
                  constraint.bodyB.map({
                      bodyIdentifiers.contains(ObjectIdentifier($0))
                  }) ?? true
            else { continue }

            let identifierB = constraint.bodyB.map(ObjectIdentifier.init)
            let dynamicA = bodyByIdentifier[identifierA] != nil
            let dynamicB = identifierB.map { bodyByIdentifier[$0] != nil }
                ?? false
            if dynamicA, dynamicB, let identifierB {
                adjacency[identifierA, default: []].insert(identifierB)
                adjacency[identifierB, default: []].insert(identifierA)
            }
            if dynamicA,
               constraint.bodyB.map(_sequentialIsMovingKinematic) ?? false {
                activationSeeds.insert(identifierA)
            }
            if dynamicB && _sequentialIsMovingKinematic(constraint.bodyA),
               let identifierB {
                activationSeeds.insert(identifierB)
            }

            let hasActiveBias = constraint.solverRows(timeStep: timeStep)
                .contains {
                    $0.biasVelocity.isFinite &&
                        abs($0.biasVelocity) > biasThreshold
                }
            if hasActiveBias {
                if dynamicA { activationSeeds.insert(identifierA) }
                if dynamicB, let identifierB {
                    activationSeeds.insert(identifierB)
                }
            }
        }

        var visited: Set<ObjectIdentifier> = []
        var islands: [_SequentialBodyIsland] = []
        for root in orderedBodies {
            let rootIdentifier = ObjectIdentifier(root)
            guard visited.insert(rootIdentifier).inserted else { continue }

            var stack = [rootIdentifier]
            var bodies: [RigidBody] = []
            var isActive = false
            while let identifier = stack.popLast() {
                guard let body = bodyByIdentifier[identifier] else { continue }
                bodies.append(body)
                isActive = isActive || activationSeeds.contains(identifier)
                for neighbor in adjacency[identifier] ?? []
                where visited.insert(neighbor).inserted {
                    stack.append(neighbor)
                }
            }
            islands.append(_SequentialBodyIsland(bodies: bodies,
                                                 isActive: isActive))
        }
        return islands
    }

    private func activateIslands(
        _ islands: [_SequentialBodyIsland]
    ) -> Set<ObjectIdentifier> {
        var identifiers: Set<ObjectIdentifier> = []
        for island in islands where island.isActive {
            for body in island.bodies {
                identifiers.insert(ObjectIdentifier(body))
                if body.isSleeping { body.wakeUp() }
            }
        }
        return identifiers
    }

    private func updateSleeping(
        _ islands: [_SequentialBodyIsland],
        activeBodyIdentifiers: Set<ObjectIdentifier>,
                                timeStep: Scalar) {
        let linearThreshold = sanitizedNonnegative(linearSleepThreshold)
        let angularThreshold = sanitizedNonnegative(angularSleepThreshold)
        let delay = sanitizedNonnegative(sleepDelay)

        for island in islands where island.bodies.contains(where: {
            activeBodyIdentifiers.contains(ObjectIdentifier($0))
        }) {
            guard isSleepingEnabled,
                  island.bodies.allSatisfy(\.allowsSleeping)
            else {
                for body in island.bodies {
                    body.resetSleepDuration()
                    if body.isSleeping { body.wakeUp() }
                }
                continue
            }

            let canSleep = island.bodies.allSatisfy { body in
                body.linearVelocity.isFiniteVector &&
                    body.angularVelocity.isFiniteVector &&
                    body.linearVelocity.length <= linearThreshold &&
                    body.angularVelocity.length <= angularThreshold
            }
            guard canSleep else {
                for body in island.bodies { body.resetSleepDuration() }
                continue
            }

            for body in island.bodies {
                body.advanceSleepDuration(by: timeStep)
            }
            if island.bodies.allSatisfy({ $0.sleepDuration >= delay }) {
                for body in island.bodies { body.putToSleep() }
            }
        }
    }

    private func integrateTransforms(_ bodies: [RigidBody],
                                     timeStep: Scalar,
                                     activeBodyIdentifiers: Set<ObjectIdentifier>,
                                     frozen: Set<ObjectIdentifier>) {
        guard timeStep > 0 else { return }
        for body in bodies where body.isEnabled && body.motionType != .static {
            let identifier = ObjectIdentifier(body)
            if frozen.contains(identifier) || (body.motionType == .dynamic &&
                (!activeBodyIdentifiers.contains(identifier) || body.isSleeping)) { continue }
            guard body.linearVelocity.isFiniteVector, body.angularVelocity.isFiniteVector else { continue }
            let localCenter = body.massProperties.centerOfMass
            let worldCenter = localCenter.applying(body.transform) + body.linearVelocity * timeStep
            let orientation = integratedOrientation(body.transform.orientation,
                angularVelocity: body.angularVelocity, timeStep: timeStep)
            body.transform = Transform(orientation: orientation,
                                       position: worldCenter - localCenter.applying(orientation))
        }
    }

    private func integratedOrientation(
        _ orientation: Quaternion,
        angularVelocity: Vector3,
        timeStep: Scalar
    ) -> Quaternion {
        let angularSpeed = angularVelocity.length
        guard angularSpeed.isFinite,
              angularSpeed > Scalar.ulpOfOne,
              timeStep.isFinite,
              timeStep > .zero
        else { return orientation }
        let rotation = Quaternion(angle: angularSpeed * timeStep,
                                  axis: angularVelocity)
        return orientation.concatenating(rotation).normalized()
    }

    private func dampingFactor(_ damping: Scalar,
                               timeStep: Scalar) -> Scalar {
        guard damping.isFinite else { return damping > .zero ? .zero : Scalar(1) }
        return exp(-Swift.max(damping, .zero) * timeStep)
    }

    private func sanitizedNonnegative(_ value: Scalar) -> Scalar {
        if value == .infinity { return .infinity }
        guard value.isFinite else { return .zero }
        return Swift.max(value, .zero)
    }
}

private struct _SequentialBodyIsland {
    let bodies: [RigidBody]
    let isActive: Bool
}

private struct _SequentialCCDPair: Hashable {
    let a: Int
    let b: Int
    init(_ a: Int, _ b: Int) { self.a = Swift.min(a, b); self.b = Swift.max(a, b) }
}

private struct _SequentialCCDImpact {
    let bodyA: RigidBody
    let bodyB: RigidBody?
    let fraction: Scalar
    let hit: MotionSweepHit?
    let motionA: CollisionMotion
    let motionB: CollisionMotion
}

private struct _SequentialJointRow {
    let row: RigidBodyConstraintRow
    let inverseEffectiveMass: Scalar
    var accumulatedImpulse: Scalar = .zero

    init?(_ row: RigidBodyConstraintRow) {
        guard row.bodyA.isEnabled,
              row.bodyB?.isEnabled ?? true,
              row.linearJacobianA.isFiniteVector,
              row.angularJacobianA.isFiniteVector,
              row.linearJacobianB.isFiniteVector,
              row.angularJacobianB.isFiniteVector,
              row.biasVelocity.isFinite,
              !row.lowerImpulse.isNaN,
              !row.upperImpulse.isNaN,
              row.lowerImpulse <= row.upperImpulse
        else { return nil }

        let inverseEffectiveMass = _sequentialInverseEffectiveMass(
            bodyA: row.bodyA,
            bodyB: row.bodyB,
            linearJacobianA: row.linearJacobianA,
            angularJacobianA: row.angularJacobianA,
            linearJacobianB: row.linearJacobianB,
            angularJacobianB: row.angularJacobianB)
        guard inverseEffectiveMass > .zero else { return nil }
        self.row = row
        self.inverseEffectiveMass = inverseEffectiveMass
    }

    mutating func solve() {
        let velocityA = _sequentialConstraintVelocity(
            body: row.bodyA,
            linearJacobian: row.linearJacobianA,
            angularJacobian: row.angularJacobianA)
        let velocityB = row.bodyB.map {
            _sequentialConstraintVelocity(
                body: $0,
                linearJacobian: row.linearJacobianB,
                angularJacobian: row.angularJacobianB)
        } ?? .zero
        let velocity = velocityA + velocityB
        guard velocity.isFinite else { return }
        let impulse = -(velocity + row.biasVelocity) * inverseEffectiveMass
        let previous = accumulatedImpulse
        accumulatedImpulse = (previous + impulse).clamp(
            min: row.lowerImpulse,
            max: row.upperImpulse)
        let appliedImpulse = accumulatedImpulse - previous
        _sequentialApplyImpulse(
            to: row.bodyA,
            linearJacobian: row.linearJacobianA,
            angularJacobian: row.angularJacobianA,
            impulse: appliedImpulse)
        if let bodyB = row.bodyB {
            _sequentialApplyImpulse(
                to: bodyB,
                linearJacobian: row.linearJacobianB,
                angularJacobian: row.angularJacobianB,
                impulse: appliedImpulse)
        }
    }
}

private struct _SequentialContactCacheKey: Hashable {
    let bodyA: ObjectIdentifier
    let bodyB: ObjectIdentifier
    let featureID: ContactFeatureID

    init(bodyA: RigidBody,
         bodyB: RigidBody,
         featureID: ContactFeatureID) {
        self.bodyA = ObjectIdentifier(bodyA)
        self.bodyB = ObjectIdentifier(bodyB)
        self.featureID = featureID
    }
}

private struct _SequentialCachedContactImpulse {
    let normal: Scalar
    let friction: Vector3
}

private struct _SequentialContactConstraint {
    let cacheKey: _SequentialContactCacheKey?
    let bodyA: RigidBody
    let bodyB: RigidBody?
    let offsetA: Vector3
    let offsetB: Vector3
    let normal: Vector3
    let tangent1: Vector3
    let tangent2: Vector3
    let inverseNormalMass: Scalar
    let inverseTangentMass1: Scalar
    let inverseTangentMass2: Scalar
    let normalBias: Scalar
    let friction: Scalar
    var normalImpulse: Scalar
    var tangentImpulse1: Scalar
    var tangentImpulse2: Scalar

    var cachedImpulse: _SequentialCachedContactImpulse {
        _SequentialCachedContactImpulse(
            normal: normalImpulse,
            friction: tangent1 * tangentImpulse1 +
                tangent2 * tangentImpulse2)
    }

    init?(cacheKey: _SequentialContactCacheKey?,
          bodyA: RigidBody,
          bodyB: RigidBody?,
          offsetA: Vector3,
          offsetB: Vector3,
          normal: Vector3,
          normalBias: Scalar,
          friction: Scalar,
          initialRelativeVelocity: Vector3,
          cachedImpulse: _SequentialCachedContactImpulse?) {
        guard normalBias.isFinite,
              friction.isFinite,
              initialRelativeVelocity.isFiniteVector
        else { return nil }
        let normalJacobians = Self.jacobians(direction: normal,
                                             offsetA: offsetA,
                                             offsetB: offsetB)
        let inverseNormalMass = _sequentialInverseEffectiveMass(
            bodyA: bodyA,
            bodyB: bodyB,
            linearJacobianA: normalJacobians.linearA,
            angularJacobianA: normalJacobians.angularA,
            linearJacobianB: normalJacobians.linearB,
            angularJacobianB: normalJacobians.angularB)
        guard inverseNormalMass > .zero else { return nil }

        let tangentVelocity = initialRelativeVelocity -
            normal * Vector3.dot(initialRelativeVelocity, normal)
        let tangent1: Vector3
        if tangentVelocity.lengthSquared > Scalar.ulpOfOne {
            tangent1 = tangentVelocity.normalized()
        } else {
            tangent1 = Self.perpendicular(to: normal)
        }
        let tangent2 = Vector3.cross(normal, tangent1).normalized()
        let tangentJacobians1 = Self.jacobians(direction: tangent1,
                                              offsetA: offsetA,
                                              offsetB: offsetB)
        let tangentJacobians2 = Self.jacobians(direction: tangent2,
                                              offsetA: offsetA,
                                              offsetB: offsetB)

        self.cacheKey = cacheKey
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.offsetA = offsetA
        self.offsetB = offsetB
        self.normal = normal
        self.tangent1 = tangent1
        self.tangent2 = tangent2
        self.inverseNormalMass = inverseNormalMass
        self.inverseTangentMass1 = _sequentialInverseEffectiveMass(
            bodyA: bodyA,
            bodyB: bodyB,
            linearJacobianA: tangentJacobians1.linearA,
            angularJacobianA: tangentJacobians1.angularA,
            linearJacobianB: tangentJacobians1.linearB,
            angularJacobianB: tangentJacobians1.angularB)
        self.inverseTangentMass2 = _sequentialInverseEffectiveMass(
            bodyA: bodyA,
            bodyB: bodyB,
            linearJacobianA: tangentJacobians2.linearA,
            angularJacobianA: tangentJacobians2.angularA,
            linearJacobianB: tangentJacobians2.linearB,
            angularJacobianB: tangentJacobians2.angularB)
        self.normalBias = normalBias
        self.friction = Swift.max(friction, .zero)

        let cachedNormal: Scalar
        if let normalImpulse = cachedImpulse?.normal,
           normalImpulse.isFinite {
            cachedNormal = Swift.max(normalImpulse, .zero)
        } else {
            cachedNormal = .zero
        }
        var cachedTangent1: Scalar = .zero
        var cachedTangent2: Scalar = .zero
        if let frictionImpulse = cachedImpulse?.friction,
           frictionImpulse.isFiniteVector {
            cachedTangent1 = Vector3.dot(frictionImpulse, tangent1)
            cachedTangent2 = Vector3.dot(frictionImpulse, tangent2)
            let maximumFriction = self.friction * cachedNormal
            let magnitudeSquared = cachedTangent1 * cachedTangent1 +
                cachedTangent2 * cachedTangent2
            if maximumFriction.isFinite,
               magnitudeSquared > maximumFriction * maximumFriction {
                let scale = maximumFriction / sqrt(magnitudeSquared)
                cachedTangent1 *= scale
                cachedTangent2 *= scale
            }
        }
        self.normalImpulse = cachedNormal
        self.tangentImpulse1 = cachedTangent1
        self.tangentImpulse2 = cachedTangent2
    }

    func warmStart() {
        let impulse = normal * normalImpulse +
            tangent1 * tangentImpulse1 +
            tangent2 * tangentImpulse2
        guard impulse.isFiniteVector else { return }
        applyContactImpulse(impulse)
    }

    mutating func solve() {
        solveNormal()
        solveFriction()
    }

    private mutating func solveNormal() {
        let relativeVelocity = _sequentialRelativeVelocity(
            bodyA: bodyA,
            bodyB: bodyB,
            offsetA: offsetA,
            offsetB: offsetB)
        let normalVelocity = Vector3.dot(relativeVelocity, normal)
        let impulse = -(normalVelocity + normalBias) * inverseNormalMass
        guard impulse.isFinite else { return }
        let previous = normalImpulse
        normalImpulse = Swift.max(previous + impulse, .zero)
        applyContactImpulse(normal * (normalImpulse - previous))
    }

    private mutating func solveFriction() {
        let maximumFriction = friction * normalImpulse
        // A zero limit must still undo friction applied during warm starting.
        guard maximumFriction > .zero ||
                tangentImpulse1 != .zero || tangentImpulse2 != .zero,
              inverseTangentMass1 > .zero || inverseTangentMass2 > .zero
        else { return }

        let relativeVelocity = _sequentialRelativeVelocity(
            bodyA: bodyA,
            bodyB: bodyB,
            offsetA: offsetA,
            offsetB: offsetB)
        guard relativeVelocity.isFiniteVector else { return }
        var proposed1 = tangentImpulse1 -
            Vector3.dot(relativeVelocity, tangent1) * inverseTangentMass1
        var proposed2 = tangentImpulse2 -
            Vector3.dot(relativeVelocity, tangent2) * inverseTangentMass2
        let magnitudeSquared = proposed1 * proposed1 + proposed2 * proposed2
        guard magnitudeSquared.isFinite else { return }
        if magnitudeSquared > maximumFriction * maximumFriction {
            let scale = maximumFriction / sqrt(magnitudeSquared)
            proposed1 *= scale
            proposed2 *= scale
        }

        let impulse = tangent1 * (proposed1 - tangentImpulse1) +
            tangent2 * (proposed2 - tangentImpulse2)
        tangentImpulse1 = proposed1
        tangentImpulse2 = proposed2
        applyContactImpulse(impulse)
    }

    private func applyContactImpulse(_ impulse: Vector3) {
        _sequentialApplyImpulse(
            to: bodyA,
            linearJacobian: -impulse,
            angularJacobian: -Vector3.cross(offsetA, impulse),
            impulse: Scalar(1))
        if let bodyB {
            _sequentialApplyImpulse(
                to: bodyB,
                linearJacobian: impulse,
                angularJacobian: Vector3.cross(offsetB, impulse),
                impulse: Scalar(1))
        }
    }

    private static func jacobians(
        direction: Vector3,
        offsetA: Vector3,
        offsetB: Vector3
    ) -> (linearA: Vector3, angularA: Vector3,
          linearB: Vector3, angularB: Vector3) {
        (-direction,
         -Vector3.cross(offsetA, direction),
         direction,
         Vector3.cross(offsetB, direction))
    }

    private static func perpendicular(to normal: Vector3) -> Vector3 {
        let axis = abs(normal.x) < abs(normal.y)
            ? (abs(normal.x) < abs(normal.z)
                ? Vector3(1, 0, 0) : Vector3(0, 0, 1))
            : (abs(normal.y) < abs(normal.z)
                ? Vector3(0, 1, 0) : Vector3(0, 0, 1))
        return Vector3.cross(normal, axis).normalized()
    }
}

private func _sequentialInverseEffectiveMass(
    bodyA: RigidBody,
    bodyB: RigidBody?,
    linearJacobianA: Vector3,
    angularJacobianA: Vector3,
    linearJacobianB: Vector3,
    angularJacobianB: Vector3
) -> Scalar {
    var denominator = bodyA.inverseMass *
        Vector3.dot(linearJacobianA, linearJacobianA)
    denominator += Vector3.dot(
        angularJacobianA.applying(bodyA.worldInverseInertiaTensor),
        angularJacobianA)
    if let bodyB {
        denominator += bodyB.inverseMass *
            Vector3.dot(linearJacobianB, linearJacobianB)
        denominator += Vector3.dot(
            angularJacobianB.applying(bodyB.worldInverseInertiaTensor),
            angularJacobianB)
    }
    guard denominator.isFinite, denominator > Scalar.ulpOfOne else {
        return .zero
    }
    return Scalar(1) / denominator
}

private func _sequentialConstraintVelocity(
    body: RigidBody,
    linearJacobian: Vector3,
    angularJacobian: Vector3
) -> Scalar {
    guard body.isEnabled,
          body.motionType != .static,
          !body.isSleeping
    else { return .zero }
    return Vector3.dot(linearJacobian, body.linearVelocity) +
        Vector3.dot(angularJacobian, body.angularVelocity)
}

private func _sequentialRelativeVelocity(
    bodyA: RigidBody,
    bodyB: RigidBody?,
    offsetA: Vector3,
    offsetB: Vector3
) -> Vector3 {
    (bodyB.map { _sequentialPointVelocity($0, offset: offsetB) } ?? .zero) -
        _sequentialPointVelocity(bodyA, offset: offsetA)
}

private func _sequentialPointVelocity(_ body: RigidBody,
                                      offset: Vector3) -> Vector3 {
    guard body.isEnabled,
          body.motionType != .static,
          !body.isSleeping
    else { return .zero }
    return body.linearVelocity + Vector3.cross(body.angularVelocity, offset)
}

private func _sequentialHasActiveDynamicBody(
    _ bodyA: RigidBody,
    _ bodyB: RigidBody?,
    activeBodyIdentifiers: Set<ObjectIdentifier>
) -> Bool {
    if bodyA.motionType == .dynamic &&
        activeBodyIdentifiers.contains(ObjectIdentifier(bodyA)) {
        return true
    }
    if let bodyB,
       bodyB.motionType == .dynamic,
       activeBodyIdentifiers.contains(ObjectIdentifier(bodyB)) {
        return true
    }
    return false
}

private func _sequentialIsMovingKinematic(_ body: RigidBody) -> Bool {
    body.isEnabled && body.motionType == .kinematic &&
        ((body.linearVelocity.isFiniteVector &&
          body.linearVelocity.lengthSquared > Scalar.ulpOfOne) ||
         (body.angularVelocity.isFiniteVector &&
          body.angularVelocity.lengthSquared > Scalar.ulpOfOne))
}

private func _sequentialApplyImpulse(
    to body: RigidBody,
    linearJacobian: Vector3,
    angularJacobian: Vector3,
    impulse: Scalar
) {
    guard body.isEnabled,
          body.motionType == .dynamic,
          !body.isSleeping,
          impulse.isFinite
    else { return }
    body.linearVelocity += linearJacobian * (impulse * body.inverseMass)
    body.angularVelocity += (angularJacobian * impulse)
        .applying(body.worldInverseInertiaTensor)
}

private extension Vector3 {
    var isFiniteVector: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}
