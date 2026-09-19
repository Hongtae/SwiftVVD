//
//  File: RigidBody.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public enum RigidBodyMotionType: Hashable, Sendable {
    case `static`
    case kinematic
    case dynamic
}

/// Mass and local-space inertia data for a rigid body.
public struct RigidBodyMassProperties: Hashable, Sendable {
    public var mass: Scalar
    public var centerOfMass: Vector3
    public var inertia: Vector3

    public init(mass: Scalar = 1.0,
                centerOfMass: Vector3 = .zero,
                inertia: Vector3 = .zero) {
        self.mass = mass
        self.centerOfMass = centerOfMass
        self.inertia = inertia
    }

    public var inverseMass: Scalar {
        mass > .zero ? Scalar(1) / mass : .zero
    }

    public var inverseInertia: Vector3 {
        Vector3(inertia.x > .zero ? Scalar(1) / inertia.x : .zero,
                inertia.y > .zero ? Scalar(1) / inertia.y : .zero,
                inertia.z > .zero ? Scalar(1) / inertia.z : .zero)
    }
}

/// Mutable rigid-body state owned by a `RigidBodySimulator`.
public final class RigidBody: Hashable {
    public let collider: Collider

    public var motionType: RigidBodyMotionType
    public var massProperties: RigidBodyMassProperties
    public var material: PhysicsMaterial
    public var linearVelocity: Vector3
    public var angularVelocity: Vector3
    public var linearDamping: Scalar
    public var angularDamping: Scalar
    public var gravityScale: Scalar

    public private(set) var accumulatedForces: ForceAccumulator

    public var transform: Transform {
        get { collider.transform }
        set { collider.transform = newValue }
    }

    public var isEnabled: Bool {
        get { collider.isEnabled }
        set { collider.isEnabled = newValue }
    }

    public var inverseMass: Scalar {
        motionType == .dynamic ? massProperties.inverseMass : .zero
    }

    public var inverseInertia: Vector3 {
        motionType == .dynamic ? massProperties.inverseInertia : .zero
    }

    public init(collider: Collider,
                motionType: RigidBodyMotionType = .dynamic,
                massProperties: RigidBodyMassProperties = RigidBodyMassProperties(),
                material: PhysicsMaterial = .default,
                linearVelocity: Vector3 = .zero,
                angularVelocity: Vector3 = .zero,
                linearDamping: Scalar = 0.0,
                angularDamping: Scalar = 0.0,
                gravityScale: Scalar = 1.0) {
        self.collider = collider
        self.motionType = motionType
        self.massProperties = massProperties
        self.material = material
        self.linearVelocity = linearVelocity
        self.angularVelocity = angularVelocity
        self.linearDamping = linearDamping
        self.angularDamping = angularDamping
        self.gravityScale = gravityScale
        self.accumulatedForces = ForceAccumulator()
    }

    public convenience init(primitive: any CollisionPrimitive,
                            transform: Transform = .identity,
                            filter: CollisionFilter = CollisionFilter(),
                            motionType: RigidBodyMotionType = .dynamic,
                            massProperties: RigidBodyMassProperties = RigidBodyMassProperties(),
                            material: PhysicsMaterial = .default) {
        self.init(collider: Collider(primitive: primitive,
                                     transform: transform,
                                     filter: filter),
                  motionType: motionType,
                  massProperties: massProperties,
                  material: material)
    }

    public func addForce(_ force: Vector3) {
        accumulatedForces.addForce(force)
    }

    public func addTorque(_ torque: Vector3) {
        accumulatedForces.addTorque(torque)
    }

    /// Adds force at a world-space point.
    public func addForce(_ force: Vector3, at point: Vector3) {
        let centerOfMass = massProperties.centerOfMass.applying(transform)
        accumulatedForces.addForce(force, at: point - centerOfMass)
    }

    public func removeAllForces() {
        accumulatedForces.removeAll()
    }

    public static func == (lhs: RigidBody, rhs: RigidBody) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
