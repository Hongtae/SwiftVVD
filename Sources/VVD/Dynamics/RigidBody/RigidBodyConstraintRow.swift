//
//  File: RigidBodyConstraintRow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// One scalar Jacobian row consumed by an impulse-based rigid-body solver.
///
/// The solver drives `J * velocity + biasVelocity` toward zero while clamping
/// the accumulated impulse to `lowerImpulse...upperImpulse`.
public struct RigidBodyConstraintRow {
    /// Stable slot within the owning constraint, unique among its current rows.
    /// Use the same identifier when an axis is rebuilt, omitted, or reordered
    /// within a substep. Nil uses array position and requires a fixed row layout.
    public let identifier: Int?
    public let bodyA: RigidBody
    public let bodyB: RigidBody?
    public let linearJacobianA: Vector3
    public let angularJacobianA: Vector3
    public let linearJacobianB: Vector3
    public let angularJacobianB: Vector3
    public let biasVelocity: Scalar
    public let lowerImpulse: Scalar
    public let upperImpulse: Scalar

    public init(bodyA: RigidBody,
                bodyB: RigidBody?,
                linearJacobianA: Vector3,
                angularJacobianA: Vector3,
                linearJacobianB: Vector3,
                angularJacobianB: Vector3,
                biasVelocity: Scalar = .zero,
                lowerImpulse: Scalar = -.infinity,
                upperImpulse: Scalar = .infinity,
                identifier: Int? = nil) {
        self.identifier = identifier
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.linearJacobianA = linearJacobianA
        self.angularJacobianA = angularJacobianA
        self.linearJacobianB = linearJacobianB
        self.angularJacobianB = angularJacobianB
        self.biasVelocity = biasVelocity
        self.lowerImpulse = lowerImpulse
        self.upperImpulse = upperImpulse
    }
}

public enum RigidBodyJointMotion: Hashable, Sendable {
    case free
    case locked
    case limited(lower: Scalar, upper: Scalar)
}

/// Motion and optional velocity-drive settings for one configurable-joint axis.
public struct RigidBodyJointAxis: Hashable, Sendable {
    public var motion: RigidBodyJointMotion
    public var targetVelocity: Scalar
    public var maximumForce: Scalar

    public static let free = RigidBodyJointAxis()
    public static let locked = RigidBodyJointAxis(motion: .locked,
                                                  maximumForce: .infinity)

    public static func limited(_ lower: Scalar,
                               _ upper: Scalar,
                               targetVelocity: Scalar = .zero,
                               maximumForce: Scalar = .infinity) -> Self {
        Self(motion: .limited(lower: lower, upper: upper),
             targetVelocity: targetVelocity,
             maximumForce: maximumForce)
    }

    /// Free axes default to no drive; locks and limits default to no force cap.
    public init(motion: RigidBodyJointMotion = .free,
                targetVelocity: Scalar = .zero) {
        self.init(motion: motion, targetVelocity: targetVelocity,
                  maximumForce: motion == .free ? .zero : .infinity)
    }

    public init(motion: RigidBodyJointMotion = .free,
                targetVelocity: Scalar = .zero,
                maximumForce: Scalar) {
        self.motion = motion
        self.targetVelocity = targetVelocity
        self.maximumForce = maximumForce
    }
}
