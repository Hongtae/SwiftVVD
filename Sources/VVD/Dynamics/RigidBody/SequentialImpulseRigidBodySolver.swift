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

    public init(velocityIterations: Int = 8,
                positionCorrectionFactor: Scalar = 0.2,
                penetrationSlop: Scalar = 0.005,
                restitutionVelocityThreshold: Scalar = 1.0,
                maximumBiasVelocity: Scalar = 10.0) {
        self.velocityIterations = velocityIterations
        self.positionCorrectionFactor = positionCorrectionFactor
        self.penetrationSlop = penetrationSlop
        self.restitutionVelocityThreshold = restitutionVelocityThreshold
        self.maximumBiasVelocity = maximumBiasVelocity
    }

    public func solve(_ context: RigidBodySolverContext) {
        let timeStep = context.timeStep
        guard timeStep.isFinite, timeStep > .zero else { return }

        let bodyIdentifiers = Set(context.bodies.map(ObjectIdentifier.init))
        integrateForces(context.bodies,
                        gravity: context.gravity,
                        timeStep: timeStep)

        var contactConstraints = makeContactConstraints(
            context.contacts,
            bodyIdentifiers: bodyIdentifiers,
            timeStep: timeStep)
        var jointRows = makeJointRows(
            context.constraints,
            bodyIdentifiers: bodyIdentifiers,
            timeStep: timeStep)

        for _ in 0..<Swift.max(velocityIterations, 0) {
            for index in jointRows.indices {
                jointRows[index].solve()
            }
            for index in contactConstraints.indices {
                contactConstraints[index].solve()
            }
        }

        integrateTransforms(context.bodies, timeStep: timeStep)
        for body in context.bodies {
            body.removeAllForces()
        }
    }

    private func integrateForces(_ bodies: [RigidBody],
                                 gravity: Vector3,
                                 timeStep: Scalar) {
        let finiteGravity = gravity.isFiniteVector ? gravity : .zero
        for body in bodies where body.isEnabled && body.motionType == .dynamic {
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

    private func makeContactConstraints(
        _ contacts: [RigidBodyContact],
        bodyIdentifiers: Set<ObjectIdentifier>,
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
                  pair.bodyB.isEnabled
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

                if let constraint = _SequentialContactConstraint(
                    bodyA: pair.bodyA,
                    bodyB: pair.bodyB,
                    offsetA: offsetA,
                    offsetB: offsetB,
                    normal: normal,
                    normalBias: restitutionBias - correctionVelocity,
                    friction: material.friction,
                    initialRelativeVelocity: initialVelocity) {
                    constraints.append(constraint)
                }
            }
        }
        return constraints
    }

    private func makeJointRows(
        _ constraints: [any RigidBodyConstraint],
        bodyIdentifiers: Set<ObjectIdentifier>,
        timeStep: Scalar
    ) -> [_SequentialJointRow] {
        var rows: [_SequentialJointRow] = []
        for constraint in constraints where constraint.isEnabled {
            guard bodyIdentifiers.contains(ObjectIdentifier(constraint.bodyA)),
                  constraint.bodyB.map({
                      bodyIdentifiers.contains(ObjectIdentifier($0))
                  }) ?? true
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

    private func integrateTransforms(_ bodies: [RigidBody], timeStep: Scalar) {
        for body in bodies
        where body.isEnabled && body.motionType != .static {
            guard body.linearVelocity.isFiniteVector,
                  body.angularVelocity.isFiniteVector
            else { continue }

            let localCenter = body.massProperties.centerOfMass
            var worldCenter = localCenter.applying(body.transform)
            worldCenter += body.linearVelocity * timeStep

            var orientation = body.transform.orientation
            let angularSpeed = body.angularVelocity.length
            if angularSpeed.isFinite && angularSpeed > Scalar.ulpOfOne {
                let rotation = Quaternion(angle: angularSpeed * timeStep,
                                          axis: body.angularVelocity)
                orientation = orientation.concatenating(rotation).normalized()
            }
            body.transform = Transform(
                orientation: orientation,
                position: worldCenter - localCenter.applying(orientation))
        }
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

private struct _SequentialContactConstraint {
    let bodyA: RigidBody
    let bodyB: RigidBody
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
    var normalImpulse: Scalar = .zero
    var tangentImpulse1: Scalar = .zero
    var tangentImpulse2: Scalar = .zero

    init?(bodyA: RigidBody,
          bodyB: RigidBody,
          offsetA: Vector3,
          offsetB: Vector3,
          normal: Vector3,
          normalBias: Scalar,
          friction: Scalar,
          initialRelativeVelocity: Vector3) {
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
        guard maximumFriction > .zero,
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
        _sequentialApplyImpulse(
            to: bodyB,
            linearJacobian: impulse,
            angularJacobian: Vector3.cross(offsetB, impulse),
            impulse: Scalar(1))
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
    guard body.isEnabled, body.motionType != .static else { return .zero }
    return Vector3.dot(linearJacobian, body.linearVelocity) +
        Vector3.dot(angularJacobian, body.angularVelocity)
}

private func _sequentialRelativeVelocity(
    bodyA: RigidBody,
    bodyB: RigidBody,
    offsetA: Vector3,
    offsetB: Vector3
) -> Vector3 {
    _sequentialPointVelocity(bodyB, offset: offsetB) -
        _sequentialPointVelocity(bodyA, offset: offsetA)
}

private func _sequentialPointVelocity(_ body: RigidBody,
                                      offset: Vector3) -> Vector3 {
    guard body.isEnabled, body.motionType != .static else { return .zero }
    return body.linearVelocity + Vector3.cross(body.angularVelocity, offset)
}

private func _sequentialApplyImpulse(
    to body: RigidBody,
    linearJacobian: Vector3,
    angularJacobian: Vector3,
    impulse: Scalar
) {
    guard body.isEnabled,
          body.motionType == .dynamic,
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
