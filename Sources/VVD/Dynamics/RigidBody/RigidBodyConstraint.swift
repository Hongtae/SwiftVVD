//
//  File: RigidBodyConstraint.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Shared ownership contract for rigid-body constraints.
public protocol RigidBodyConstraint: AnyObject {
    var bodyA: RigidBody { get }
    var bodyB: RigidBody? { get }
    var isEnabled: Bool { get set }
}

public final class FixedJointConstraint: RigidBodyConstraint {
    public let bodyA: RigidBody
    public let bodyB: RigidBody?
    public var frameA: Transform
    public var frameB: Transform
    public var isEnabled: Bool

    public init(bodyA: RigidBody,
                bodyB: RigidBody? = nil,
                frameA: Transform = .identity,
                frameB: Transform = .identity,
                isEnabled: Bool = true) {
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.frameA = frameA
        self.frameB = frameB
        self.isEnabled = isEnabled
    }
}

public final class ConfigurableJointConstraint: RigidBodyConstraint {
    public let bodyA: RigidBody
    public let bodyB: RigidBody?
    public var frameA: Transform
    public var frameB: Transform
    public var isEnabled: Bool

    public init(bodyA: RigidBody,
                bodyB: RigidBody? = nil,
                frameA: Transform = .identity,
                frameB: Transform = .identity,
                isEnabled: Bool = true) {
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.frameA = frameA
        self.frameB = frameB
        self.isEnabled = isEnabled
    }
}

public final class GearJointConstraint: RigidBodyConstraint {
    public let bodyA: RigidBody
    public let bodyB: RigidBody?
    public var axisA: Vector3
    public var axisB: Vector3
    public var ratio: Scalar
    public var isEnabled: Bool

    public init(bodyA: RigidBody,
                bodyB: RigidBody? = nil,
                axisA: Vector3 = Vector3(0, 1, 0),
                axisB: Vector3 = Vector3(0, 1, 0),
                ratio: Scalar = 1.0,
                isEnabled: Bool = true) {
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.axisA = axisA
        self.axisB = axisB
        self.ratio = ratio
        self.isEnabled = isEnabled
    }
}
