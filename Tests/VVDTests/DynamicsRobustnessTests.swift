import XCTest
import VVD

final class DynamicsRobustnessTests: XCTestCase {
    func testInvalidTimeStepsDoNotReachInjectedSolvers() {
        let rigid = RobustnessRigidSolver()
        let xpbd = RobustnessXPBDSolver()
        let simulator = DynamicsSimulator(rigidBodies: RigidBodySimulator(solver: rigid),
                                          xpbd: XPBDSimulator(solver: xpbd))
        for timeStep in [Scalar.nan, .infinity, -.infinity, 0, -1] {
            simulator.step(timeStep: timeStep)
            simulator.rigidBodies.step(timeStep: timeStep)
            simulator.xpbd.step(timeStep: timeStep)
        }
        XCTAssertTrue(rigid.timeSteps.isEmpty)
        XCTAssertTrue(xpbd.timeSteps.isEmpty)
        simulator.step(timeStep: 0.1)
        XCTAssertEqual(rigid.timeSteps, [0.1])
        XCTAssertEqual(xpbd.timeSteps, [0.1])
    }

    func testDuplicateColliderContextsAreRejectedBeforeMutatingBodies() {
        let first = sphere(.zero)
        let second = RigidBody(collider: first.collider)
        first.isContinuousCollisionDetectionEnabled = true
        first.addForce(Vector3(1, 0, 0))
        let solver = SequentialImpulseRigidBodySolver(ccdConfiguration: .init(substepCount: 2))
        let space = CollisionSpace(colliders: [first.collider])
        for bodies in [[first, second], [first, first]] {
            solver.solve(.init(timeStep: 1, gravity: Vector3(0, -10, 0), bodies: bodies,
                               contacts: [], constraints: [], collisionSpace: space))
            XCTAssertEqual(first.transform, .identity)
            XCTAssertEqual(first.linearVelocity, .zero)
            XCTAssertEqual(first.accumulatedForces.force, Vector3(1, 0, 0))
        }
        solver.solve(.init(timeStep: 1, gravity: .zero, bodies: [first],
                           contacts: [], constraints: [], collisionSpace: space))
        XCTAssertEqual(first.linearVelocity.x, 1, accuracy: 1.0e-9)
    }

    func testInvalidMassDoesNotProduceGravityOrForceAcceleration() {
        for mass in [Scalar.zero, -1, .nan, .infinity, .leastNonzeroMagnitude] {
            let body = sphere(.zero)
            body.massProperties.mass = mass
            body.addForce(Vector3(1, 0, 0))
            let simulator = RigidBodySimulator()
            simulator.add(body)
            simulator.step(timeStep: 0.1)
            XCTAssertEqual(body.inverseMass, 0)
            XCTAssertEqual(body.linearVelocity, .zero)
            XCTAssertEqual(body.transform.position, .zero)
        }
    }

    func testInertiaValidationPreservesLockedAxesAndRejectsInvalidFullTensors() {
        let zero = Matrix3(0, 0, 0, 0, 0, 0, 0, 0, 0)
        XCTAssertEqual(RigidBodyMassProperties(inertia: Vector3(-1, 2, 0)).inverseInertia,
                       Vector3(0, 0.5, 0))
        XCTAssertEqual(RigidBodyMassProperties(inertia: Vector3(Scalar.nan, .infinity, 0))
            .inverseInertiaTensor, zero)
        let invalid = [
            Matrix3(1, 2, 2, 2, 1, 2, 2, 2, 1), // Positive determinant, two negative eigenvalues.
            Matrix3(2, 1, 0, 0, 2, 0, 0, 0, 2), // Nonsymmetric.
            Matrix3(1, 1, 1, 1, 1, 1, 1, 1, 1), // Singular.
            Matrix3(1, Scalar.nan, 0, .nan, 1, 0, 0, 0, 1),
        ]
        for tensor in invalid {
            XCTAssertEqual(RigidBodyMassProperties(mass: 1, inertiaTensor: tensor).inverseInertiaTensor, zero)
        }
        for scale: Scalar in [1.0e-200, 1, 1.0e200] {
            let tensor = Matrix3(2, 1, 0, 1, 2, 0, 0, 0, 3) * scale
            let inverse = RigidBodyMassProperties(mass: 1, inertiaTensor: tensor).inverseInertiaTensor
            let product = tensor * inverse
            for row in 0..<3 {
                for column in 0..<3 {
                    XCTAssertEqual(product[row, column], row == column ? 1 : 0, accuracy: 1.0e-12)
                }
            }
        }
    }

    func testAxisDefaultsMatchHelpersAndZeroSpeedDriveRemainsActive() {
        XCTAssertEqual(RigidBodyJointAxis(), .free)
        XCTAssertEqual(RigidBodyJointAxis(motion: .locked), .locked)
        XCTAssertEqual(RigidBodyJointAxis(motion: .limited(lower: -1, upper: 1)), .limited(-1, 1))
        let body = sphere(.zero)
        body.linearVelocity = Vector3(2, 2, 0)
        let simulator = RigidBodySimulator(gravity: .zero)
        simulator.add(body)
        simulator.add(ConfigurableJointConstraint(bodyA: body,
            linearX: RigidBodyJointAxis(motion: .locked),
            linearY: RigidBodyJointAxis(maximumForce: 1), biasFactor: 0))
        simulator.step(timeStep: 0.5)
        XCTAssertEqual(body.linearVelocity.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(body.linearVelocity.y, 1.5, accuracy: 1.0e-9)
    }

    func testZeroForceJointBiasDoesNotKeepAnIslandAwake() {
        let body = sphere(Vector3(10, 0, 0))
        let configurable = ConfigurableJointConstraint(bodyA: body,
            linearX: .init(motion: .locked, maximumForce: 0),
            linearY: .limited(-1, 1, maximumForce: 0))
        XCTAssertTrue(configurable.solverRows(timeStep: 0.1).isEmpty)
        let simulator = RigidBodySimulator(gravity: .zero)
        simulator.add(body)
        simulator.add(configurable)
        simulator.add(FixedJointConstraint(bodyA: body, maximumForce: 0, maximumTorque: 0))
        body.putToSleep()
        simulator.step(timeStep: 0.1)
        XCTAssertTrue(body.isSleeping)
        XCTAssertEqual(body.transform.position, Vector3(10, 0, 0))
    }

    func testWakeAfterRicochetIntegratesGravityAndDampingForRemainingTime() {
        for damping: Scalar in [0, 0.4] {
            let bullet = sphere(.zero, radius: 0.1, restitution: 1)
            bullet.linearVelocity = Vector3(10, 0, 0)
            bullet.gravityScale = 0
            bullet.isContinuousCollisionDetectionEnabled = true
            let hitX = 3 - Scalar(0.1) * Scalar(2).squareRoot()
            let target = sphere(Vector3(hitX, 3, 0), radius: 0.1)
            target.linearDamping = damping
            let wall = RigidBody(primitive: StaticPlane(Plane(
                normal: Vector3(-1, 1, 0).normalized(), point: Vector3(3, 0, 0))),
                motionType: .static, material: .init(friction: 0, restitution: 1))
            let solver = SequentialImpulseRigidBodySolver(ccdConfiguration: .init(mode: .timeOfImpact))
            let simulator = RigidBodySimulator(gravity: Vector3(0, 0, -10), solver: solver)
            for body in [bullet, wall, target] { simulator.add(body) }
            target.putToSleep()
            simulator.step(timeStep: 1)
            let remaining = 1 - hitX / 10
            let expectedVelocity = -10 * remaining * exp(-damping * remaining)
            XCTAssertEqual(solver.ccdStatistics.impactCount, 1)
            XCTAssertFalse(target.isSleeping)
            XCTAssertEqual(target.linearVelocity.z, expectedVelocity, accuracy: 1.0e-9)
            XCTAssertEqual(target.transform.position.z, expectedVelocity * remaining, accuracy: 1.0e-9)
        }
    }

    func testRemoteCCDImpactPreservesUnrelatedContactWarmStarts() {
        for mode in [CCDConfiguration.Mode.motionClamping, .hybrid, .timeOfImpact] {
            for sleeping in [false, true] {
                let supported = sphere(Vector3(0, -10, 0))
                let floor = RigidBody(primitive: Box(halfExtents: Vector3(5, 0.1, 5)),
                    transform: Transform(position: Vector3(0, -10.6, 0)), motionType: .static,
                    material: .init(friction: 0))
                let bullet = sphere(.zero)
                bullet.gravityScale = 0
                let target = sphere(Vector3(3, 0, 0), motion: .static)
                let solver = SequentialImpulseRigidBodySolver(ccdConfiguration: .init(mode: mode))
                let simulator = RigidBodySimulator(solver: solver)
                for body in [supported, floor, bullet, target] { simulator.add(body) }
                simulator.step(timeStep: 0.01)
                XCTAssertEqual(solver.cachedContactCount, 1)
                if sleeping { supported.putToSleep() }
                bullet.isContinuousCollisionDetectionEnabled = true
                bullet.linearVelocity = Vector3(20, 0, 0)
                simulator.step(timeStep: 0.2)
                XCTAssertGreaterThan(solver.ccdStatistics.sweepCount, 0)
                XCTAssertEqual(solver.cachedContactCount, 1, "\(mode), sleeping=\(sleeping)")
                XCTAssertEqual(supported.transform.position.y, -10, accuracy: 1.0e-9)
            }
        }
    }

    private func sphere(_ position: Vector3, radius: Scalar = 0.5,
                        motion: RigidBodyMotionType = .dynamic, restitution: Scalar = 0) -> RigidBody {
        RigidBody(primitive: Sphere(center: .zero, radius: radius),
                  transform: Transform(position: position), motionType: motion,
                  material: .init(friction: 0, restitution: restitution))
    }
}

private final class RobustnessRigidSolver: RigidBodySolver {
    var timeSteps: [Scalar] = []
    func solve(_ context: RigidBodySolverContext) { timeSteps.append(context.timeStep) }
}

private final class RobustnessXPBDSolver: XPBDSolver {
    var timeSteps: [Scalar] = []
    func solve(_ context: XPBDSolverContext) { timeSteps.append(context.timeStep) }
}
