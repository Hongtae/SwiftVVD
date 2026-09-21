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
    /// Local-space inertia tensor about `centerOfMass`.
    public var inertiaTensor: Matrix3

    /// Compatibility access to the tensor diagonal. Assigning this property
    /// replaces the full tensor with a diagonal tensor.
    public var inertia: Vector3 {
        get {
            Vector3(inertiaTensor.m11,
                    inertiaTensor.m22,
                    inertiaTensor.m33)
        }
        set {
            inertiaTensor = Self.diagonalMatrix(newValue)
        }
    }

    public init(mass: Scalar = 1.0,
                centerOfMass: Vector3 = .zero,
                inertia: Vector3 = .zero) {
        self.mass = mass
        self.centerOfMass = centerOfMass
        self.inertiaTensor = Self.diagonalMatrix(inertia)
    }

    public init(mass: Scalar,
                centerOfMass: Vector3 = .zero,
                inertiaTensor: Matrix3) {
        self.mass = mass
        self.centerOfMass = centerOfMass
        self.inertiaTensor = inertiaTensor
    }

    /// Nonpositive, nonfinite, or noninvertible mass has no linear response.
    public var inverseMass: Scalar {
        Self.finiteInverse(mass)
    }

    public var inverseInertia: Vector3 {
        let inverse = inverseInertiaTensor
        return Vector3(inverse.m11, inverse.m22, inverse.m33)
    }

    /// Diagonal zero/invalid axes are locked. Full tensors must be finite,
    /// symmetric, and positive definite; otherwise angular response is disabled.
    public var inverseInertiaTensor: Matrix3 {
        if inertiaTensor.isDiagonal {
            let diagonal = inertia
            return Self.diagonalMatrix(Vector3(
                Self.finiteInverse(diagonal.x),
                Self.finiteInverse(diagonal.y),
                Self.finiteInverse(diagonal.z)))
        }

        let zero = Self.diagonalMatrix(.zero)
        guard inertiaTensor.hasFiniteInertiaComponents,
              inertiaTensor.m11 > 0, inertiaTensor.m22 > 0, inertiaTensor.m33 > 0
        else { return zero }
        // Test symmetry and positive definiteness in normalized units so the
        // determinant does not overflow or underflow with the body's scale.
        let scale = Swift.max(inertiaTensor.m11, inertiaTensor.m22, inertiaTensor.m33)
        var tensor = Matrix3(row1: inertiaTensor.row1 / scale,
                             row2: inertiaTensor.row2 / scale,
                             row3: inertiaTensor.row3 / scale)
        let tolerance = Scalar.ulpOfOne * 64
        guard abs(tensor.m12 - tensor.m21) <= tolerance,
              abs(tensor.m13 - tensor.m31) <= tolerance,
              abs(tensor.m23 - tensor.m32) <= tolerance else { return zero }
        tensor = (tensor + tensor.transposed()) * Scalar(0.5)
        guard tensor.m11 * tensor.m22 - tensor.m12 * tensor.m12 > 0,
              tensor.determinant > 0,
              let inverse = tensor.inverted() else { return zero }
        let result = Matrix3(row1: inverse.row1 / scale,
                             row2: inverse.row2 / scale,
                             row3: inverse.row3 / scale)
        return result.hasFiniteInertiaComponents ? result : zero
    }

    private static func finiteInverse(_ value: Scalar) -> Scalar {
        guard value.isFinite, value > .zero else { return .zero }
        let inverse = Scalar(1) / value
        return inverse.isFinite ? inverse : .zero
    }

    private static func diagonalMatrix(_ diagonal: Vector3) -> Matrix3 {
        Matrix3(diagonal.x, 0, 0,
                0, diagonal.y, 0,
                0, 0, diagonal.z)
    }
}

private extension Matrix3 {
    var hasFiniteInertiaComponents: Bool {
        m11.isFinite && m12.isFinite && m13.isFinite &&
            m21.isFinite && m22.isFinite && m23.isFinite &&
            m31.isFinite && m32.isFinite && m33.isFinite
    }
}

/// Mutable rigid-body state owned by a `RigidBodySimulator`.
public final class RigidBody: Hashable {
    public let collider: Collider

    public var motionType: RigidBodyMotionType {
        didSet {
            if motionType != oldValue { wakeUp() }
        }
    }
    public var massProperties: RigidBodyMassProperties {
        didSet {
            if massProperties != oldValue { wakeUpIfSleeping() }
        }
    }
    public var material: PhysicsMaterial
    public var linearVelocity: Vector3 {
        didSet {
            if linearVelocity != oldValue { wakeUpIfSleeping() }
        }
    }
    public var angularVelocity: Vector3 {
        didSet {
            if angularVelocity != oldValue { wakeUpIfSleeping() }
        }
    }
    public var linearDamping: Scalar
    public var angularDamping: Scalar
    public var gravityScale: Scalar
    public var allowsSleeping: Bool {
        didSet {
            if allowsSleeping == false { wakeUp() }
        }
    }
    public var isContinuousCollisionDetectionEnabled: Bool {
        didSet {
            if isContinuousCollisionDetectionEnabled { wakeUpIfSleeping() }
        }
    }
    public private(set) var isSleeping: Bool
    public private(set) var sleepDuration: Scalar

    public private(set) var accumulatedForces: ForceAccumulator

    public var transform: Transform {
        get { collider.transform }
        set {
            let changed = collider.transform != newValue
            collider.transform = newValue
            if changed { wakeUpIfSleeping() }
        }
    }

    public var isEnabled: Bool {
        get { collider.isEnabled }
        set {
            let wasEnabled = collider.isEnabled
            collider.isEnabled = newValue
            if newValue && !wasEnabled { wakeUp() }
        }
    }

    public var inverseMass: Scalar {
        motionType == .dynamic ? massProperties.inverseMass : .zero
    }

    public var inverseInertia: Vector3 {
        motionType == .dynamic ? massProperties.inverseInertia : .zero
    }

    public var inverseInertiaTensor: Matrix3 {
        motionType == .dynamic
            ? massProperties.inverseInertiaTensor
            : Matrix3(0, 0, 0,
                      0, 0, 0,
                      0, 0, 0)
    }

    /// Inverse inertia rotated from body-local coordinates into simulation
    /// coordinates.
    public var worldInverseInertiaTensor: Matrix3 {
        let rotation = transform.orientation.matrix3
        return rotation.transposed() * inverseInertiaTensor * rotation
    }

    public init(collider: Collider,
                motionType: RigidBodyMotionType = .dynamic,
                massProperties: RigidBodyMassProperties = RigidBodyMassProperties(),
                material: PhysicsMaterial = .default,
                linearVelocity: Vector3 = .zero,
                angularVelocity: Vector3 = .zero,
                linearDamping: Scalar = 0.0,
                angularDamping: Scalar = 0.0,
                gravityScale: Scalar = 1.0,
                allowsSleeping: Bool = true,
                isContinuousCollisionDetectionEnabled: Bool = false) {
        self.collider = collider
        self.motionType = motionType
        self.massProperties = massProperties
        self.material = material
        self.linearVelocity = linearVelocity
        self.angularVelocity = angularVelocity
        self.linearDamping = linearDamping
        self.angularDamping = angularDamping
        self.gravityScale = gravityScale
        self.allowsSleeping = allowsSleeping
        self.isContinuousCollisionDetectionEnabled =
            isContinuousCollisionDetectionEnabled
        self.isSleeping = false
        self.sleepDuration = .zero
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

    /// Creates a body after deriving finite-volume mass properties from its
    /// primitive. Unsupported or zero-volume primitives fail construction.
    public convenience init?(
        primitive: any CollisionPrimitive,
        density: Scalar,
        transform: Transform = .identity,
        filter: CollisionFilter = CollisionFilter(),
        motionType: RigidBodyMotionType = .dynamic,
        material: PhysicsMaterial = .default
    ) {
        guard let massProperties = RigidBodyMassProperties(
            primitive: primitive,
            density: density) else { return nil }
        self.init(primitive: primitive,
                  transform: transform,
                  filter: filter,
                  motionType: motionType,
                  massProperties: massProperties,
                  material: material)
    }

    public func addForce(_ force: Vector3) {
        if force != .zero { wakeUp() }
        accumulatedForces.addForce(force)
    }

    public func addTorque(_ torque: Vector3) {
        if torque != .zero { wakeUp() }
        accumulatedForces.addTorque(torque)
    }

    /// Adds force at a world-space point.
    public func addForce(_ force: Vector3, at point: Vector3) {
        if force != .zero { wakeUp() }
        let centerOfMass = massProperties.centerOfMass.applying(transform)
        accumulatedForces.addForce(force, at: point - centerOfMass)
    }

    public func removeAllForces() {
        accumulatedForces.removeAll()
    }

    /// Wakes this body and resets its accumulated stationary duration.
    public func wakeUp() {
        isSleeping = false
        sleepDuration = .zero
    }

    /// Stops an eligible dynamic body until it is explicitly or implicitly
    /// awakened.
    public func putToSleep() {
        guard isEnabled,
              motionType == .dynamic,
              allowsSleeping
        else { return }
        linearVelocity = .zero
        angularVelocity = .zero
        isSleeping = true
    }

    func resetSleepDuration() {
        sleepDuration = .zero
    }

    func advanceSleepDuration(by timeStep: Scalar) {
        guard timeStep.isFinite, timeStep > .zero else { return }
        sleepDuration += timeStep
    }

    private func wakeUpIfSleeping() {
        if isSleeping { wakeUp() }
    }

    /// Replaces the current mass properties with a fresh primitive derivation.
    @discardableResult
    public func recalculateMassProperties(density: Scalar) -> Bool {
        guard let properties = RigidBodyMassProperties(
            primitive: collider.primitive,
            density: density) else { return false }
        massProperties = properties
        return true
    }

    public static func == (lhs: RigidBody, rhs: RigidBody) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
