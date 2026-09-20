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
                sleepDelay: Scalar = 0.5) {
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
        let timeStep = context.timeStep
        guard timeStep.isFinite, timeStep > .zero else { return }

        let bodyIdentifiers = Set(context.bodies.map(ObjectIdentifier.init))
        let islands = makeDynamicIslands(context,
                                         bodyIdentifiers: bodyIdentifiers,
                                         timeStep: timeStep)
        var activeBodyIdentifiers = activateIslands(islands)
        integrateForces(context.bodies,
                        gravity: context.gravity,
                        timeStep: timeStep,
                        activeBodyIdentifiers: activeBodyIdentifiers)
        let ccdStep = makeCCDStep(
            context,
            islands: islands,
            activeBodyIdentifiers: &activeBodyIdentifiers,
            timeStep: timeStep)

        var contactConstraints = makeContactConstraints(
            context.contacts,
            bodyIdentifiers: bodyIdentifiers,
            activeBodyIdentifiers: activeBodyIdentifiers,
            timeStep: timeStep)
        contactConstraints.append(contentsOf: makeCCDConstraints(
            ccdStep.impacts,
            timeStep: timeStep))
        var jointRows = makeJointRows(
            context.constraints,
            bodyIdentifiers: bodyIdentifiers,
            activeBodyIdentifiers: activeBodyIdentifiers,
            timeStep: timeStep)

        if isWarmStartingEnabled {
            for constraint in contactConstraints {
                constraint.warmStart()
            }
        }

        for _ in 0..<Swift.max(velocityIterations, 0) {
            for index in jointRows.indices {
                jointRows[index].solve()
            }
            for index in contactConstraints.indices {
                contactConstraints[index].solve()
            }
        }

        updateContactCache(contactConstraints,
                           contacts: context.contacts,
                           bodyIdentifiers: bodyIdentifiers)

        integrateTransforms(context.bodies,
                            timeStep: timeStep,
                            activeBodyIdentifiers: activeBodyIdentifiers,
                            ccdAdvances: ccdStep.advances)
        updateSleeping(islands,
                       activeBodyIdentifiers: activeBodyIdentifiers,
                       timeStep: timeStep)
        for body in context.bodies {
            body.removeAllForces()
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

    private func makeCCDStep(
        _ context: RigidBodySolverContext,
        islands: [_SequentialBodyIsland],
        activeBodyIdentifiers: inout Set<ObjectIdentifier>,
        timeStep: Scalar
    ) -> _SequentialCCDStep {
        guard let collisionSpace = context.collisionSpace else {
            return _SequentialCCDStep()
        }

        var impacts = ccdImpacts(
            bodies: context.bodies,
            discreteContacts: context.contacts,
            collisionSpace: collisionSpace,
            activeBodyIdentifiers: activeBodyIdentifiers,
            timeStep: timeStep)

        while true {
            let sleepingBodies = Set(impacts.flatMap { impact in
                [impact.bodyA, impact.bodyB].compactMap { body -> ObjectIdentifier? in
                    guard let body,
                          body.motionType == .dynamic,
                          body.isSleeping
                    else { return nil }
                    return ObjectIdentifier(body)
                }
            })
            guard sleepingBodies.isEmpty == false else { break }

            var newlyActive: Set<ObjectIdentifier> = []
            for island in islands where island.bodies.contains(where: {
                sleepingBodies.contains(ObjectIdentifier($0))
            }) {
                for body in island.bodies {
                    let identifier = ObjectIdentifier(body)
                    if activeBodyIdentifiers.insert(identifier).inserted {
                        newlyActive.insert(identifier)
                    }
                    if body.isSleeping { body.wakeUp() }
                }
            }
            guard newlyActive.isEmpty == false else { break }

            integrateForces(context.bodies,
                            gravity: context.gravity,
                            timeStep: timeStep,
                            activeBodyIdentifiers: newlyActive)
            impacts = ccdImpacts(
                bodies: context.bodies,
                discreteContacts: context.contacts,
                collisionSpace: collisionSpace,
                activeBodyIdentifiers: activeBodyIdentifiers,
                timeStep: timeStep)
        }

        var advances: [ObjectIdentifier: _SequentialCCDAdvance] = [:]
        for impact in impacts {
            updateCCDAdvance(body: impact.bodyA,
                             fraction: impact.fraction,
                             advances: &advances)
            if let bodyB = impact.bodyB,
               bodyB.motionType == .dynamic {
                updateCCDAdvance(body: bodyB,
                                 fraction: impact.fraction,
                                 advances: &advances)
            }
        }
        return _SequentialCCDStep(impacts: impacts, advances: advances)
    }

    private func ccdImpacts(
        bodies: [RigidBody],
        discreteContacts: [RigidBodyContact],
        collisionSpace: CollisionSpace,
        activeBodyIdentifiers: Set<ObjectIdentifier>,
        timeStep: Scalar
    ) -> [_SequentialCCDImpact] {
        let bodyByCollider = Dictionary(uniqueKeysWithValues: bodies.map {
            ($0.collider, $0)
        })
        let movingBodies = bodies.filter { body in
            body.isEnabled && body.linearVelocity.isFiniteVector &&
                body.linearVelocity != .zero &&
                (body.motionType == .kinematic ||
                 activeBodyIdentifiers.contains(ObjectIdentifier(body)))
        }
        var selected: [_SequentialCCDImpact] = []

        for bodyA in bodies {
            let identifierA = ObjectIdentifier(bodyA)
            guard bodyA.isEnabled,
                  bodyA.motionType == .dynamic,
                  bodyA.isContinuousCollisionDetectionEnabled
            else { continue }

            let isActive = activeBodyIdentifiers.contains(identifierA)
            let velocityA = isActive ? bodyA.linearVelocity : .zero
            guard velocityA.isFiniteVector else { continue }

            var closest: _SequentialCCDImpact?
            let translation = velocityA * timeStep
            if isActive,
               translation.isFiniteVector,
               translation.lengthSquared > Scalar.ulpOfOne {
                for hit in collisionSpace.sweepAll(bodyA.collider,
                                                   translation: translation) {
                    guard bodyByCollider[hit.collider] == nil,
                          Vector3.dot(velocityA, hit.normal) > .zero
                    else { continue }
                    closest = _SequentialCCDImpact(
                        bodyA: bodyA,
                        bodyB: nil,
                        colliderB: hit.collider,
                        fraction: hit.fraction,
                        pointOnA: hit.pointOnMoving,
                        pointOnB: hit.pointOnCollider,
                        normal: hit.normal)
                    break
                }
            }

            // Only a moving partner can hit a stationary or sleeping CCD body.
            let inverseTransform = bodyA.transform.inverted()
            let candidates = velocityA == .zero ? movingBodies : bodies
            for bodyB in candidates where bodyB !== bodyA {
                if discreteContacts.contains(where: {
                    ($0.bodyA === bodyA && $0.bodyB === bodyB) ||
                        ($0.bodyA === bodyB && $0.bodyB === bodyA)
                }) {
                    continue
                }
                guard bodyA.collider.canCollide(with: bodyB.collider) else {
                    continue
                }
                let velocityB = bodyB.motionType == .static || bodyB.isSleeping
                    ? Vector3.zero : bodyB.linearVelocity
                guard velocityB.isFiniteVector else { continue }
                let relativeVelocity = velocityA - velocityB
                let relativeTranslation = (relativeVelocity * timeStep)
                    .applying(inverseTransform.orientation)
                guard relativeTranslation.isFiniteVector,
                      relativeTranslation.lengthSquared > Scalar.ulpOfOne,
                      let impact = collisionSpace.algorithms.timeOfImpact(
                        bodyA.collider.primitive,
                        bodyB.collider.primitive,
                        frame: bodyB.transform * inverseTransform,
                        translation: relativeTranslation),
                      impact.isValid
                else { continue }

                let normal = impact.normal
                    .applying(bodyA.transform.orientation)
                    .normalized()
                guard Vector3.dot(relativeVelocity, normal) > .zero else {
                    continue
                }
                let commonTranslation = velocityB *
                    (timeStep * impact.fraction)
                let candidate = _SequentialCCDImpact(
                    bodyA: bodyA,
                    bodyB: bodyB,
                    colliderB: bodyB.collider,
                    fraction: impact.fraction,
                    pointOnA: impact.pointOnA.applying(bodyA.transform) +
                        commonTranslation,
                    pointOnB: impact.pointOnB.applying(bodyA.transform) +
                        commonTranslation,
                    normal: normal)
                if closest == nil || candidate.fraction < closest!.fraction {
                    closest = candidate
                }
            }

            if let closest,
               selected.contains(where: { $0.matchesPair(of: closest) }) == false {
                selected.append(closest)
            }
        }
        return selected
    }

    private func updateCCDAdvance(
        body: RigidBody,
        fraction: Scalar,
        advances: inout [ObjectIdentifier: _SequentialCCDAdvance]
    ) {
        let identifier = ObjectIdentifier(body)
        guard advances[identifier].map({ fraction < $0.fraction }) ?? true else {
            return
        }
        advances[identifier] = _SequentialCCDAdvance(
            fraction: fraction,
            linearVelocity: body.linearVelocity,
            angularVelocity: body.angularVelocity)
    }

    private func makeCCDConstraints(
        _ impacts: [_SequentialCCDImpact],
        timeStep: Scalar
    ) -> [_SequentialContactConstraint] {
        let restitutionThreshold = sanitizedNonnegative(
            restitutionVelocityThreshold)
        var constraints: [_SequentialContactConstraint] = []
        constraints.reserveCapacity(impacts.count)

        for impact in impacts {
            let centerA = impact.bodyA.massProperties.centerOfMass
                .applying(impact.bodyA.transform) +
                impact.bodyA.linearVelocity *
                (timeStep * impact.fraction)
            let velocityB = impact.bodyB.map {
                $0.motionType == .static ? Vector3.zero : $0.linearVelocity
            } ?? .zero
            let centerB = impact.bodyB.map {
                $0.massProperties.centerOfMass.applying($0.transform) +
                    velocityB * (timeStep * impact.fraction)
            } ?? impact.pointOnB
            let offsetA = impact.pointOnA - centerA
            let offsetB = impact.pointOnB - centerB
            let initialVelocity = _sequentialRelativeVelocity(
                bodyA: impact.bodyA,
                bodyB: impact.bodyB,
                offsetA: offsetA,
                offsetB: offsetB)
            let normalVelocity = Vector3.dot(initialVelocity, impact.normal)
            let material = impact.bodyB.map {
                impact.bodyA.material.combined(with: $0.material)
            } ?? impact.bodyA.material.combined(with: .default)
            let normalBias = normalVelocity < -restitutionThreshold
                ? material.restitution * normalVelocity : Scalar.zero

            if let constraint = _SequentialContactConstraint(
                cacheKey: nil,
                bodyA: impact.bodyA,
                bodyB: impact.bodyB,
                offsetA: offsetA,
                offsetB: offsetB,
                normal: impact.normal,
                normalBias: normalBias,
                friction: material.friction,
                initialRelativeVelocity: initialVelocity,
                cachedImpulse: nil) {
                constraints.append(constraint)
            }
        }
        return constraints
    }

    private func makeContactConstraints(
        _ contacts: [RigidBodyContact],
        bodyIdentifiers: Set<ObjectIdentifier>,
        activeBodyIdentifiers: Set<ObjectIdentifier>,
        timeStep: Scalar
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
                    cachedImpulse: isWarmStartingEnabled
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

    private func integrateTransforms(
        _ bodies: [RigidBody],
        timeStep: Scalar,
        activeBodyIdentifiers: Set<ObjectIdentifier>,
        ccdAdvances: [ObjectIdentifier: _SequentialCCDAdvance]
    ) {
        for body in bodies
        where body.isEnabled && body.motionType != .static {
            if body.motionType == .dynamic &&
                (!activeBodyIdentifiers.contains(ObjectIdentifier(body)) ||
                 body.isSleeping) {
                continue
            }
            guard body.linearVelocity.isFiniteVector,
                  body.angularVelocity.isFiniteVector
            else { continue }

            let localCenter = body.massProperties.centerOfMass
            var worldCenter = localCenter.applying(body.transform)
            if let advance = ccdAdvances[ObjectIdentifier(body)] {
                let remainingFraction = Scalar(1) - advance.fraction
                worldCenter += advance.linearVelocity *
                    (timeStep * advance.fraction)
                worldCenter += body.linearVelocity *
                    (timeStep * remainingFraction)
            } else {
                worldCenter += body.linearVelocity * timeStep
            }

            var orientation = body.transform.orientation
            if let advance = ccdAdvances[ObjectIdentifier(body)] {
                orientation = integratedOrientation(
                    orientation,
                    angularVelocity: advance.angularVelocity,
                    timeStep: timeStep * advance.fraction)
                orientation = integratedOrientation(
                    orientation,
                    angularVelocity: body.angularVelocity,
                    timeStep: timeStep * (Scalar(1) - advance.fraction))
            } else {
                orientation = integratedOrientation(
                    orientation,
                    angularVelocity: body.angularVelocity,
                    timeStep: timeStep)
            }
            body.transform = Transform(
                orientation: orientation,
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

private struct _SequentialCCDStep {
    let impacts: [_SequentialCCDImpact]
    let advances: [ObjectIdentifier: _SequentialCCDAdvance]

    init(impacts: [_SequentialCCDImpact] = [],
         advances: [ObjectIdentifier: _SequentialCCDAdvance] = [:]) {
        self.impacts = impacts
        self.advances = advances
    }
}

private struct _SequentialCCDAdvance {
    let fraction: Scalar
    let linearVelocity: Vector3
    let angularVelocity: Vector3
}

private struct _SequentialCCDImpact {
    let bodyA: RigidBody
    let bodyB: RigidBody?
    let colliderB: Collider
    let fraction: Scalar
    let pointOnA: Vector3
    let pointOnB: Vector3
    let normal: Vector3

    func matchesPair(of other: Self) -> Bool {
        if let bodyB, let otherBodyB = other.bodyB {
            return (bodyA === other.bodyA && bodyB === otherBodyB) ||
                (bodyA === otherBodyB && bodyB === other.bodyA)
        }
        return bodyB == nil && other.bodyB == nil &&
            bodyA === other.bodyA && colliderB === other.colliderB
    }
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
