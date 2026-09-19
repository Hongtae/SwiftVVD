//
//  File: RigidBodyConstraintRowTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class RigidBodyConstraintRowTests: XCTestCase {
    func testFixedJointBuildsThreeLinearAndThreeAngularRows() {
        let bodyA = body(position: .zero)
        let bodyB = body(
            position: Vector3(1, 2, 3),
            orientation: Quaternion(angle: Scalar.pi * 0.5,
                                    axis: Vector3(0, 0, 1)))
        let joint = FixedJointConstraint(bodyA: bodyA,
                                         bodyB: bodyB,
                                         biasFactor: 0.2,
                                         maximumForce: 10,
                                         maximumTorque: 20)

        let rows = joint.solverRows(timeStep: 0.5)

        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows[0].linearJacobianA, Vector3(-1, 0, 0))
        XCTAssertEqual(rows[0].linearJacobianB, Vector3(1, 0, 0))
        XCTAssertEqual(rows[0].biasVelocity, 0.4, accuracy: 1.0e-9)
        XCTAssertEqual(rows[1].biasVelocity, 0.8, accuracy: 1.0e-9)
        XCTAssertEqual(rows[2].biasVelocity, 1.2, accuracy: 1.0e-9)
        XCTAssertEqual(rows[0].lowerImpulse, -5)
        XCTAssertEqual(rows[0].upperImpulse, 5)

        XCTAssertEqual(rows[5].angularJacobianA, Vector3(0, 0, -1))
        XCTAssertEqual(rows[5].angularJacobianB, Vector3(0, 0, 1))
        XCTAssertEqual(rows[5].biasVelocity,
                       Scalar.pi * 0.2,
                       accuracy: 1.0e-9)
        XCTAssertEqual(rows[5].lowerImpulse, -10)
        XCTAssertEqual(rows[5].upperImpulse, 10)
    }

    func testFixedJointSupportsWorldFrameAndAnchorAngularJacobians() {
        let bodyA = body(position: .zero)
        let joint = FixedJointConstraint(
            bodyA: bodyA,
            frameA: Transform(position: Vector3(0, 1, 0)),
            frameB: Transform(position: Vector3(2, 1, 0)))

        let rows = joint.solverRows(timeStep: 1)

        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows[0].biasVelocity, 0.4, accuracy: 1.0e-9)
        XCTAssertEqual(rows[0].angularJacobianA, Vector3(0, 0, 1))
        XCTAssertEqual(rows[0].angularJacobianB, .zero)
    }

    func testConfigurableJointBuildsOnlyActiveAxisRows() {
        let bodyA = body(position: .zero)
        let bodyB = body(
            position: Vector3(2, 0, 0),
            orientation: Quaternion(angle: 0.5,
                                    axis: Vector3(0, 0, 1)))
        let joint = ConfigurableJointConstraint(
            bodyA: bodyA,
            bodyB: bodyB,
            linearX: .limited(-1, 1, maximumForce: 10),
            angularZ: .locked,
            biasFactor: 0.2)

        let rows = joint.solverRows(timeStep: 0.5)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].biasVelocity, 0.4, accuracy: 1.0e-9)
        XCTAssertEqual(rows[0].lowerImpulse, -5)
        XCTAssertEqual(rows[0].upperImpulse, 0)
        XCTAssertEqual(rows[1].angularJacobianA, Vector3(0, 0, -1))
        XCTAssertEqual(rows[1].angularJacobianB, Vector3(0, 0, 1))
        XCTAssertEqual(rows[1].biasVelocity, 0.2, accuracy: 1.0e-9)
    }

    func testConfigurableDriveAndLowerLimitUseCorrectImpulseDirections() {
        let bodyA = body(position: .zero)
        let bodyB = body(position: Vector3(-2, 0, 0))
        let driven = RigidBodyJointAxis(motion: .free,
                                        targetVelocity: 3,
                                        maximumForce: 4)
        let joint = ConfigurableJointConstraint(
            bodyA: bodyA,
            bodyB: bodyB,
            linearX: .limited(-1, 1, targetVelocity: 0,
                              maximumForce: 6),
            linearY: driven)

        let rows = joint.solverRows(timeStep: 0.5)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].lowerImpulse, 0)
        XCTAssertEqual(rows[0].upperImpulse, 3)
        XCTAssertLessThan(rows[0].biasVelocity, 0)
        XCTAssertEqual(rows[1].biasVelocity, -3)
        XCTAssertEqual(rows[1].lowerImpulse, -2)
        XCTAssertEqual(rows[1].upperImpulse, 2)
    }

    func testDefaultConfigurableJointHasNoRows() {
        let bodyA = body(position: .zero)
        let bodyB = body(position: Vector3(3, 4, 5))
        let joint = ConfigurableJointConstraint(bodyA: bodyA, bodyB: bodyB)

        XCTAssertTrue(joint.solverRows(timeStep: 1.0 / 60.0).isEmpty)
    }

    func testGearJointBuildsRatioVelocityRowInWorldAxes() throws {
        let bodyA = body(
            position: .zero,
            orientation: Quaternion(angle: Scalar.pi * 0.5,
                                    axis: Vector3(0, 0, 1)))
        let bodyB = body(position: .zero)
        let joint = GearJointConstraint(bodyA: bodyA,
                                        bodyB: bodyB,
                                        axisA: Vector3(1, 0, 0),
                                        axisB: Vector3(0, 0, 1),
                                        ratio: -2,
                                        targetVelocity: 3,
                                        maximumTorque: 8)

        let row = try XCTUnwrap(joint.solverRows(timeStep: 0.25).first)

        XCTAssertEqual(row.angularJacobianA.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(row.angularJacobianA.y, 1, accuracy: 1.0e-9)
        XCTAssertEqual(row.angularJacobianA.z, 0, accuracy: 1.0e-9)
        XCTAssertEqual(row.angularJacobianB, Vector3(0, 0, -2))
        XCTAssertEqual(row.biasVelocity, -3)
        XCTAssertEqual(row.lowerImpulse, -2)
        XCTAssertEqual(row.upperImpulse, 2)
    }

    func testDisabledAndInvalidJointInputsProduceNoRows() {
        let body = body(position: .zero)
        let fixed = FixedJointConstraint(bodyA: body, isEnabled: false)
        let gear = GearJointConstraint(bodyA: body, axisA: .zero)

        XCTAssertTrue(fixed.solverRows(timeStep: 1).isEmpty)
        XCTAssertTrue(fixed.solverRows(timeStep: 0).isEmpty)
        XCTAssertTrue(gear.solverRows(timeStep: 1).isEmpty)
    }

    private func body(position: Vector3,
                      orientation: Quaternion = .identity) -> RigidBody {
        RigidBody(
            primitive: Sphere(center: .zero, radius: 0.5),
            transform: Transform(orientation: orientation,
                                 position: position),
            massProperties: RigidBodyMassProperties(
                mass: 1,
                inertia: Vector3(1, 1, 1)))
    }
}
