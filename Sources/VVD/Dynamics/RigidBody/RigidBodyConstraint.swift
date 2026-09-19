//
//  File: RigidBodyConstraint.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Shared ownership contract for rigid-body constraints.
public protocol RigidBodyConstraint: AnyObject {
    var bodyA: RigidBody { get }
    var bodyB: RigidBody? { get }
    var isEnabled: Bool { get set }

    /// Produces scalar impulse rows from the current body state.
    func solverRows(timeStep: Scalar) -> [RigidBodyConstraintRow]
}

public final class FixedJointConstraint: RigidBodyConstraint {
    public let bodyA: RigidBody
    public let bodyB: RigidBody?
    public var frameA: Transform
    public var frameB: Transform
    public var isEnabled: Bool
    public var biasFactor: Scalar
    public var maximumForce: Scalar
    public var maximumTorque: Scalar

    public init(bodyA: RigidBody,
                bodyB: RigidBody? = nil,
                frameA: Transform = .identity,
                frameB: Transform = .identity,
                isEnabled: Bool = true,
                biasFactor: Scalar = 0.2,
                maximumForce: Scalar = .infinity,
                maximumTorque: Scalar = .infinity) {
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.frameA = frameA
        self.frameB = frameB
        self.isEnabled = isEnabled
        self.biasFactor = biasFactor
        self.maximumForce = maximumForce
        self.maximumTorque = maximumTorque
    }

    public func solverRows(timeStep: Scalar) -> [RigidBodyConstraintRow] {
        guard isEnabled, timeStep > .zero else { return [] }
        let frames = _jointWorldFrames(bodyA: bodyA,
                                       bodyB: bodyB,
                                       frameA: frameA,
                                       frameB: frameB)
        let axes = _jointAxes(frames.a.orientation)
        let positionError = frames.b.position - frames.a.position
        let orientationError = _jointRotationVector(from: frames.a.orientation,
                                                    to: frames.b.orientation)
        let linearLimit = _jointImpulseLimit(maximumForce, timeStep: timeStep)
        let angularLimit = _jointImpulseLimit(maximumTorque, timeStep: timeStep)
        let factor = _jointBiasFactor(biasFactor) / timeStep
        let centerA = bodyA.massProperties.centerOfMass.applying(bodyA.transform)
        let centerB = bodyB.map {
            $0.massProperties.centerOfMass.applying($0.transform)
        } ?? frames.b.position
        let offsetA = frames.a.position - centerA
        let offsetB = frames.b.position - centerB

        var rows: [RigidBodyConstraintRow] = []
        rows.reserveCapacity(6)
        for axis in axes {
            rows.append(_jointLinearRow(
                bodyA: bodyA,
                bodyB: bodyB,
                axis: axis,
                offsetA: offsetA,
                offsetB: offsetB,
                biasVelocity: Vector3.dot(positionError, axis) * factor,
                lowerImpulse: -linearLimit,
                upperImpulse: linearLimit))
        }
        for axis in axes {
            rows.append(RigidBodyConstraintRow(
                bodyA: bodyA,
                bodyB: bodyB,
                linearJacobianA: .zero,
                angularJacobianA: -axis,
                linearJacobianB: .zero,
                angularJacobianB: axis,
                biasVelocity: Vector3.dot(orientationError, axis) * factor,
                lowerImpulse: -angularLimit,
                upperImpulse: angularLimit))
        }
        return rows
    }
}

public final class ConfigurableJointConstraint: RigidBodyConstraint {
    public let bodyA: RigidBody
    public let bodyB: RigidBody?
    public var frameA: Transform
    public var frameB: Transform
    public var isEnabled: Bool
    public var linearX: RigidBodyJointAxis
    public var linearY: RigidBodyJointAxis
    public var linearZ: RigidBodyJointAxis
    public var angularX: RigidBodyJointAxis
    public var angularY: RigidBodyJointAxis
    public var angularZ: RigidBodyJointAxis
    public var biasFactor: Scalar

    public init(bodyA: RigidBody,
                bodyB: RigidBody? = nil,
                frameA: Transform = .identity,
                frameB: Transform = .identity,
                isEnabled: Bool = true,
                linearX: RigidBodyJointAxis = .free,
                linearY: RigidBodyJointAxis = .free,
                linearZ: RigidBodyJointAxis = .free,
                angularX: RigidBodyJointAxis = .free,
                angularY: RigidBodyJointAxis = .free,
                angularZ: RigidBodyJointAxis = .free,
                biasFactor: Scalar = 0.2) {
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.frameA = frameA
        self.frameB = frameB
        self.isEnabled = isEnabled
        self.linearX = linearX
        self.linearY = linearY
        self.linearZ = linearZ
        self.angularX = angularX
        self.angularY = angularY
        self.angularZ = angularZ
        self.biasFactor = biasFactor
    }

    public func solverRows(timeStep: Scalar) -> [RigidBodyConstraintRow] {
        guard isEnabled, timeStep > .zero else { return [] }
        let frames = _jointWorldFrames(bodyA: bodyA,
                                       bodyB: bodyB,
                                       frameA: frameA,
                                       frameB: frameB)
        let axes = _jointAxes(frames.a.orientation)
        let positionError = frames.b.position - frames.a.position
        let orientationError = _jointRotationVector(from: frames.a.orientation,
                                                    to: frames.b.orientation)
        let centerA = bodyA.massProperties.centerOfMass.applying(bodyA.transform)
        let centerB = bodyB.map {
            $0.massProperties.centerOfMass.applying($0.transform)
        } ?? frames.b.position
        let offsetA = frames.a.position - centerA
        let offsetB = frames.b.position - centerB
        let linearSettings = [linearX, linearY, linearZ]
        let angularSettings = [angularX, angularY, angularZ]
        let factor = _jointBiasFactor(biasFactor) / timeStep
        var rows: [RigidBodyConstraintRow] = []

        for index in axes.indices {
            let axis = axes[index]
            let coordinate = Vector3.dot(positionError, axis)
            guard let parameters = _jointAxisParameters(
                linearSettings[index],
                coordinate: coordinate,
                biasScale: factor,
                timeStep: timeStep) else { continue }
            rows.append(_jointLinearRow(
                bodyA: bodyA,
                bodyB: bodyB,
                axis: axis,
                offsetA: offsetA,
                offsetB: offsetB,
                biasVelocity: parameters.biasVelocity,
                lowerImpulse: parameters.lowerImpulse,
                upperImpulse: parameters.upperImpulse))
        }

        for index in axes.indices {
            let axis = axes[index]
            let coordinate = Vector3.dot(orientationError, axis)
            guard let parameters = _jointAxisParameters(
                angularSettings[index],
                coordinate: coordinate,
                biasScale: factor,
                timeStep: timeStep) else { continue }
            rows.append(RigidBodyConstraintRow(
                bodyA: bodyA,
                bodyB: bodyB,
                linearJacobianA: .zero,
                angularJacobianA: -axis,
                linearJacobianB: .zero,
                angularJacobianB: axis,
                biasVelocity: parameters.biasVelocity,
                lowerImpulse: parameters.lowerImpulse,
                upperImpulse: parameters.upperImpulse))
        }
        return rows
    }
}

public final class GearJointConstraint: RigidBodyConstraint {
    public let bodyA: RigidBody
    public let bodyB: RigidBody?
    public var axisA: Vector3
    public var axisB: Vector3
    public var ratio: Scalar
    public var isEnabled: Bool
    public var targetVelocity: Scalar
    public var maximumTorque: Scalar

    public init(bodyA: RigidBody,
                bodyB: RigidBody? = nil,
                axisA: Vector3 = Vector3(0, 1, 0),
                axisB: Vector3 = Vector3(0, 1, 0),
                ratio: Scalar = 1.0,
                isEnabled: Bool = true,
                targetVelocity: Scalar = .zero,
                maximumTorque: Scalar = .infinity) {
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.axisA = axisA
        self.axisB = axisB
        self.ratio = ratio
        self.isEnabled = isEnabled
        self.targetVelocity = targetVelocity
        self.maximumTorque = maximumTorque
    }

    public func solverRows(timeStep: Scalar) -> [RigidBodyConstraintRow] {
        guard isEnabled,
              timeStep > .zero,
              ratio.isFinite,
              targetVelocity.isFinite,
              axisA.lengthSquared > .ulpOfOne,
              bodyB == nil || axisB.lengthSquared > .ulpOfOne
        else { return [] }

        let worldAxisA = axisA.normalized()
            .applying(bodyA.transform.orientation)
        let worldAxisB = bodyB.map {
            axisB.normalized().applying($0.transform.orientation) * ratio
        } ?? .zero
        let limit = _jointImpulseLimit(maximumTorque, timeStep: timeStep)
        return [RigidBodyConstraintRow(
            bodyA: bodyA,
            bodyB: bodyB,
            linearJacobianA: .zero,
            angularJacobianA: worldAxisA,
            linearJacobianB: .zero,
            angularJacobianB: worldAxisB,
            biasVelocity: -targetVelocity,
            lowerImpulse: -limit,
            upperImpulse: limit)]
    }
}

private struct _JointAxisParameters {
    let biasVelocity: Scalar
    let lowerImpulse: Scalar
    let upperImpulse: Scalar
}

private func _jointWorldFrames(bodyA: RigidBody,
                               bodyB: RigidBody?,
                               frameA: Transform,
                               frameB: Transform) -> (a: Transform, b: Transform) {
    (frameA * bodyA.transform,
     bodyB.map { frameB * $0.transform } ?? frameB)
}

private func _jointAxes(_ orientation: Quaternion) -> [Vector3] {
    [Vector3(1, 0, 0).applying(orientation),
     Vector3(0, 1, 0).applying(orientation),
     Vector3(0, 0, 1).applying(orientation)]
}

private func _jointRotationVector(from a: Quaternion,
                                  to b: Quaternion) -> Vector3 {
    var difference = a.inverted().concatenating(b).normalized()
    if difference.w < .zero { difference = -difference }
    let vector = Vector3(difference.x, difference.y, difference.z)
    let length = vector.length
    guard length > .ulpOfOne else { return .zero }
    let angle = Scalar(2) * atan2(length, difference.w)
    return vector * (angle / length)
}

private func _jointLinearRow(bodyA: RigidBody,
                             bodyB: RigidBody?,
                             axis: Vector3,
                             offsetA: Vector3,
                             offsetB: Vector3,
                             biasVelocity: Scalar,
                             lowerImpulse: Scalar,
                             upperImpulse: Scalar) -> RigidBodyConstraintRow {
    RigidBodyConstraintRow(
        bodyA: bodyA,
        bodyB: bodyB,
        linearJacobianA: -axis,
        angularJacobianA: -Vector3.cross(offsetA, axis),
        linearJacobianB: axis,
        angularJacobianB: Vector3.cross(offsetB, axis),
        biasVelocity: biasVelocity,
        lowerImpulse: lowerImpulse,
        upperImpulse: upperImpulse)
}

private func _jointAxisParameters(
    _ settings: RigidBodyJointAxis,
    coordinate: Scalar,
    biasScale: Scalar,
    timeStep: Scalar
) -> _JointAxisParameters? {
    guard coordinate.isFinite,
          settings.targetVelocity.isFinite
    else { return nil }
    let limit = _jointImpulseLimit(settings.maximumForce,
                                   timeStep: timeStep)

    switch settings.motion {
    case .free:
        guard limit > .zero else { return nil }
        return _JointAxisParameters(
            biasVelocity: -settings.targetVelocity,
            lowerImpulse: -limit,
            upperImpulse: limit)
    case .locked:
        return _JointAxisParameters(
            biasVelocity: coordinate * biasScale - settings.targetVelocity,
            lowerImpulse: -limit,
            upperImpulse: limit)
    case .limited(let rawLower, let rawUpper):
        let lower = Swift.min(rawLower, rawUpper)
        let upper = Swift.max(rawLower, rawUpper)
        if coordinate < lower {
            return _JointAxisParameters(
                biasVelocity: (coordinate - lower) * biasScale -
                    settings.targetVelocity,
                lowerImpulse: .zero,
                upperImpulse: limit)
        }
        if coordinate > upper {
            return _JointAxisParameters(
                biasVelocity: (coordinate - upper) * biasScale -
                    settings.targetVelocity,
                lowerImpulse: -limit,
                upperImpulse: .zero)
        }
        guard limit > .zero && settings.targetVelocity != .zero else {
            return nil
        }
        return _JointAxisParameters(
            biasVelocity: -settings.targetVelocity,
            lowerImpulse: -limit,
            upperImpulse: limit)
    }
}

private func _jointBiasFactor(_ value: Scalar) -> Scalar {
    guard value.isFinite else { return .zero }
    return value.clamp(min: .zero, max: Scalar(1))
}

private func _jointImpulseLimit(_ maximumForce: Scalar,
                                timeStep: Scalar) -> Scalar {
    if maximumForce == .infinity { return .infinity }
    guard maximumForce.isFinite else { return .zero }
    return Swift.max(maximumForce, .zero) * timeStep
}
