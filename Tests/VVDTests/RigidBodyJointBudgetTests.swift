import XCTest
import VVD

final class RigidBodyJointBudgetTests: XCTestCase {
    func testCCDExtraSolvesPreserveUnrelatedForceTorqueAndCustomJointBudgets() {
        for mode in CCDConfiguration.Mode.allCases {
            for substeps in [1, 4] {
                for sleepingTarget in [false, true] {
                    let linear = body(Vector3(0, -10, 0), velocity: Vector3(10, 0, 0))
                    let angular = body(Vector3(0, -20, 0))
                    angular.angularVelocity = Vector3(0, 0, 10)
                    let custom = body(Vector3(0, -30, 0), velocity: Vector3(10, 0, 0))
                    let bullet = body(.zero, velocity: Vector3(10, 0, 0))
                    bullet.isContinuousCollisionDetectionEnabled = true
                    let target = body(Vector3(3, 0, 0), motion: sleepingTarget ? .dynamic : .static)
                    let solver = SequentialImpulseRigidBodySolver(sleepDelay: 10,
                        ccdConfiguration: .init(mode: mode, substepCount: substeps))
                    let simulator = RigidBodySimulator(gravity: .zero, solver: solver)
                    for body in [linear, angular, custom, bullet, target] { simulator.add(body) }
                    simulator.add(FixedJointConstraint(bodyA: linear, biasFactor: 0, maximumForce: 1))
                    simulator.add(GearJointConstraint(bodyA: angular,
                        axisA: Vector3(0, 0, 1), maximumTorque: 1))
                    simulator.add(BudgetTestJoint(bodyA: custom))
                    if sleepingTarget { target.putToSleep() }

                    simulator.step(timeStep: 0.5)

                    let scenario = "\(mode), substeps=\(substeps), sleeping=\(sleepingTarget)"
                    XCTAssertEqual(linear.linearVelocity.x, 9.5, accuracy: 1.0e-9, scenario)
                    XCTAssertEqual(angular.angularVelocity.z, 9.5, accuracy: 1.0e-9, scenario)
                    XCTAssertEqual(custom.linearVelocity.x, 9.5, accuracy: 1.0e-9, scenario)
                    if sleepingTarget && mode != .discrete {
                        XCTAssertFalse(target.isSleeping, scenario)
                    }
                }
            }
        }
    }

    func testTOIJointBudgetSurvivesMultipleImpactsAndResetsNextStep() {
        let constrained = body(Vector3(0, -10, 0), velocity: Vector3(10, 0, 0))
        let bullet = body(.zero, velocity: Vector3(20, 0, 0), restitution: 1)
        bullet.isContinuousCollisionDetectionEnabled = true
        let solver = SequentialImpulseRigidBodySolver(ccdConfiguration: .init(mode: .timeOfImpact))
        let simulator = RigidBodySimulator(gravity: .zero, solver: solver)
        for body in [constrained, bullet,
                     body(Vector3(3, 0, 0), motion: .static, restitution: 1),
                     body(Vector3(-3, 0, 0), motion: .static, restitution: 1)] {
            simulator.add(body)
        }
        simulator.add(FixedJointConstraint(bodyA: constrained, biasFactor: 0, maximumForce: 1))

        simulator.step(timeStep: 0.45)

        XCTAssertEqual(solver.ccdStatistics.impactCount, 2)
        XCTAssertEqual(constrained.linearVelocity.x, 9.55, accuracy: 1.0e-9)
        simulator.step(timeStep: 0.45)
        XCTAssertEqual(constrained.linearVelocity.x, 9.1, accuracy: 1.0e-9)
    }

    func testConfigurableJointKeepsYAxisBudgetWhenXLimitActivatesAtTOI() {
        let constrained = body(.zero, velocity: Vector3(10, 10, 0))
        let joint = ConfigurableJointConstraint(bodyA: constrained,
            linearX: .limited(-1, 1, maximumForce: 1),
            linearY: RigidBodyJointAxis(maximumForce: 1), biasFactor: 0)
        XCTAssertEqual(joint.solverRows(timeStep: 0.5).count, 1)
        let bullet = body(Vector3(0, 20, 0), velocity: Vector3(10, 0, 0))
        bullet.isContinuousCollisionDetectionEnabled = true
        let solver = SequentialImpulseRigidBodySolver(ccdConfiguration: .init(mode: .timeOfImpact))
        let simulator = RigidBodySimulator(gravity: .zero, solver: solver)
        for body in [constrained, bullet, body(Vector3(3, 20, 0), motion: .static)] {
            simulator.add(body)
        }
        simulator.add(joint)

        simulator.step(timeStep: 0.5)

        XCTAssertEqual(solver.ccdStatistics.impactCount, 1)
        XCTAssertEqual(joint.solverRows(timeStep: 0.5).count, 2)
        XCTAssertEqual(constrained.linearVelocity.x, 9.5, accuracy: 1.0e-9)
        XCTAssertEqual(constrained.linearVelocity.y, 9.5, accuracy: 1.0e-9)
    }

    func testCustomRowIdentifiersPreserveBudgetsWhenRowsReorderAtTOI() {
        let constrained = body(.zero, velocity: Vector3(10, 20, 0))
        let bullet = body(Vector3(0, 30, 0), velocity: Vector3(10, 0, 0))
        bullet.isContinuousCollisionDetectionEnabled = true
        let simulator = RigidBodySimulator(gravity: .zero,
            solver: SequentialImpulseRigidBodySolver(ccdConfiguration: .init(mode: .timeOfImpact)))
        for body in [constrained, bullet, body(Vector3(3, 30, 0), motion: .static)] {
            simulator.add(body)
        }
        simulator.add(ReorderedBudgetTestJoint(bodyA: constrained))

        simulator.step(timeStep: 0.5)

        XCTAssertEqual(constrained.linearVelocity.x, 9.5, accuracy: 1.0e-9)
        XCTAssertEqual(constrained.linearVelocity.y, 19, accuracy: 1.0e-9)
    }

    private func body(_ position: Vector3, velocity: Vector3 = .zero,
                      motion: RigidBodyMotionType = .dynamic,
                      restitution: Scalar = 0) -> RigidBody {
        RigidBody(collider: Collider(primitive: Sphere(center: .zero, radius: 0.5),
            transform: Transform(position: position)), motionType: motion,
            massProperties: RigidBodyMassProperties(mass: 1, inertia: Vector3(1, 1, 1)),
            material: PhysicsMaterial(friction: 0, restitution: restitution),
            linearVelocity: velocity)
    }
}

// Existing custom constraints with a fixed row layout need no new arguments.
private final class BudgetTestJoint: RigidBodyConstraint {
    let bodyA: RigidBody
    var bodyB: RigidBody? { nil }
    var isEnabled = true
    init(bodyA: RigidBody) { self.bodyA = bodyA }
    func solverRows(timeStep: Scalar) -> [RigidBodyConstraintRow] {
        [RigidBodyConstraintRow(bodyA: bodyA, bodyB: nil,
            linearJacobianA: Vector3(-1, 0, 0), angularJacobianA: .zero,
            linearJacobianB: .zero, angularJacobianB: .zero,
            lowerImpulse: -timeStep, upperImpulse: timeStep)]
    }
}

private final class ReorderedBudgetTestJoint: RigidBodyConstraint {
    let bodyA: RigidBody
    var bodyB: RigidBody? { nil }
    var isEnabled = true
    init(bodyA: RigidBody) { self.bodyA = bodyA }
    func solverRows(timeStep: Scalar) -> [RigidBodyConstraintRow] {
        let x = RigidBodyConstraintRow(bodyA: bodyA, bodyB: nil,
            linearJacobianA: Vector3(-1, 0, 0), angularJacobianA: .zero,
            linearJacobianB: .zero, angularJacobianB: .zero,
            lowerImpulse: -timeStep, upperImpulse: timeStep, identifier: 7)
        let y = RigidBodyConstraintRow(bodyA: bodyA, bodyB: nil,
            linearJacobianA: Vector3(0, -1, 0), angularJacobianA: .zero,
            linearJacobianB: .zero, angularJacobianB: .zero,
            lowerImpulse: -2 * timeStep, upperImpulse: 2 * timeStep, identifier: 8)
        return bodyA.transform.position.x > 1 ? [y, x] : [x, y]
    }
}
