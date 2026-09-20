import XCTest
import VVD

final class RigidBodyCCDTests: XCTestCase {
    func testCCDStopsFastBodyAtStaticTimeOfImpact() {
        let moving = sphereBody(position: .zero)
        moving.linearVelocity = Vector3(10, 0, 0)
        moving.isContinuousCollisionDetectionEnabled = true
        let target = sphereBody(position: Vector3(3, 0, 0),
                                motionType: .static)
        let simulator = makeSimulator(moving, target)

        simulator.step(timeStep: 0.5)

        XCTAssertEqual(moving.transform.position.x, 2, accuracy: 1.0e-8)
        XCTAssertEqual(moving.linearVelocity.x, 0, accuracy: 1.0e-8)
    }

    func testDisabledCCDKeepsDiscreteTunnelingBehavior() {
        let moving = sphereBody(position: .zero)
        moving.linearVelocity = Vector3(10, 0, 0)
        let target = sphereBody(position: Vector3(3, 0, 0),
                                motionType: .static)
        let simulator = makeSimulator(moving, target)

        simulator.step(timeStep: 0.5)

        XCTAssertEqual(moving.transform.position.x, 5, accuracy: 1.0e-9)
        XCTAssertEqual(moving.linearVelocity.x, 10, accuracy: 1.0e-9)
    }

    func testCCDUsesVelocityAfterForceIntegration() {
        let moving = sphereBody(position: .zero)
        moving.isContinuousCollisionDetectionEnabled = true
        moving.addForce(Vector3(10, 0, 0))
        let target = sphereBody(position: Vector3(2, 0, 0),
                                motionType: .static)
        let simulator = makeSimulator(moving, target)

        simulator.step(timeStep: 0.5)

        XCTAssertEqual(moving.transform.position.x, 1, accuracy: 1.0e-8)
        XCTAssertEqual(moving.linearVelocity.x, 0, accuracy: 1.0e-8)
        XCTAssertEqual(moving.accumulatedForces, ForceAccumulator())
    }

    func testDynamicImpactWakesTargetAndIntegratesRemainingTime() {
        let moving = sphereBody(position: .zero)
        moving.linearVelocity = Vector3(10, 0, 0)
        moving.isContinuousCollisionDetectionEnabled = true
        let target = sphereBody(position: Vector3(3, 0, 0))
        target.putToSleep()
        let simulator = makeSimulator(moving, target)

        simulator.step(timeStep: 0.5)

        XCTAssertFalse(target.isSleeping)
        XCTAssertEqual(moving.linearVelocity.x, 5, accuracy: 1.0e-8)
        XCTAssertEqual(target.linearVelocity.x, 5, accuracy: 1.0e-8)
        XCTAssertEqual(moving.transform.position.x, 3.5, accuracy: 1.0e-8)
        XCTAssertEqual(target.transform.position.x, 4.5, accuracy: 1.0e-8)
    }

    func testStationaryCCDRespondsToMovingKinematicBody() {
        let stationary = sphereBody(position: .zero)
        stationary.isContinuousCollisionDetectionEnabled = true
        let kinematic = sphereBody(position: Vector3(-3, 0, 0),
                                   motionType: .kinematic)
        kinematic.linearVelocity = Vector3(12, 0, 0)
        let simulator = makeSimulator(stationary, kinematic)

        simulator.step(timeStep: 0.5)

        XCTAssertEqual(stationary.transform.position.x, 4, accuracy: 1.0e-8)
        XCTAssertEqual(stationary.linearVelocity.x, 12, accuracy: 1.0e-8)
        XCTAssertEqual(kinematic.transform.position.x, 3, accuracy: 1.0e-8)
        XCTAssertEqual(kinematic.linearVelocity.x, 12, accuracy: 1.0e-8)
    }

    func testKinematicImpactWakesSleepingCCDIsland() {
        let stationary = sphereBody(position: .zero)
        stationary.isContinuousCollisionDetectionEnabled = true
        let connected = sphereBody(position: Vector3(0, 1, 0))
        let isolated = sphereBody(position: Vector3(10, 10, 0))
        isolated.isContinuousCollisionDetectionEnabled = true
        let kinematic = sphereBody(position: Vector3(-3, 0, 0),
                                   motionType: .kinematic)
        kinematic.linearVelocity = Vector3(12, 0, 0)
        for body in [stationary, connected, isolated] { body.putToSleep() }
        let simulator = makeSimulator(stationary, connected, isolated, kinematic)

        simulator.step(timeStep: 0.5)

        XCTAssertFalse(stationary.isSleeping)
        XCTAssertFalse(connected.isSleeping)
        XCTAssertTrue(isolated.isSleeping)
        XCTAssertEqual(stationary.transform.position.x, 4, accuracy: 1.0e-8)
        XCTAssertEqual(stationary.linearVelocity.x, 12, accuracy: 1.0e-8)
        XCTAssertEqual(isolated.transform.position, Vector3(10, 10, 0))
    }

    func testDynamicImpactWakesSleepingCCDAndIntegratesGravityOnce() {
        let stationary = sphereBody(position: .zero)
        stationary.isContinuousCollisionDetectionEnabled = true
        stationary.putToSleep()
        let moving = sphereBody(position: Vector3(-3, 0, 0))
        moving.linearVelocity = Vector3(12, 0, 0)
        moving.gravityScale = 0
        let simulator = makeSimulator(stationary, moving)
        simulator.gravity = Vector3(2, 0, 0)

        simulator.step(timeStep: 0.5)

        XCTAssertFalse(stationary.isSleeping)
        XCTAssertEqual(stationary.linearVelocity.x, 6.5, accuracy: 1.0e-8)
        XCTAssertEqual(moving.linearVelocity.x, 6.5, accuracy: 1.0e-8)
        XCTAssertEqual(stationary.transform.position.x, 2.25, accuracy: 1.0e-8)
        XCTAssertEqual(moving.transform.position.x, 1.25, accuracy: 1.0e-8)
    }

    func testFilteredKinematicBodyDoesNotWakeSleepingCCD() {
        let stationary = sphereBody(position: .zero)
        stationary.isContinuousCollisionDetectionEnabled = true
        stationary.putToSleep()
        let kinematic = sphereBody(position: Vector3(-3, 0, 0),
                                   motionType: .kinematic)
        kinematic.linearVelocity = Vector3(12, 0, 0)
        kinematic.collider.filter = CollisionFilter(mask: .none)
        let simulator = makeSimulator(stationary, kinematic)

        simulator.step(timeStep: 0.5)

        XCTAssertTrue(stationary.isSleeping)
        XCTAssertEqual(stationary.transform.position, .zero)
        XCTAssertEqual(stationary.linearVelocity, .zero)
        XCTAssertEqual(kinematic.transform.position.x, 3, accuracy: 1.0e-8)
    }

    func testCCDHandlesColliderWithoutRigidBodyOwner() {
        let environment = Collider(
            primitive: Sphere(center: .zero, radius: 0.5),
            transform: Transform(position: Vector3(3, 0, 0)))
        let collisionSpace = CollisionSpace(colliders: [environment])
        let moving = sphereBody(position: .zero)
        moving.linearVelocity = Vector3(10, 0, 0)
        moving.isContinuousCollisionDetectionEnabled = true
        let simulator = RigidBodySimulator(
            collisionSpace: collisionSpace,
            gravity: .zero,
            solver: SequentialImpulseRigidBodySolver(ccdConfiguration: .init(mode: .timeOfImpact)))
        XCTAssertTrue(simulator.add(moving))

        simulator.step(timeStep: 0.5)

        XCTAssertEqual(moving.transform.position.x, 2, accuracy: 1.0e-8)
        XCTAssertEqual(moving.linearVelocity.x, 0, accuracy: 1.0e-8)
    }

    private func sphereBody(
        position: Vector3,
        motionType: RigidBodyMotionType = .dynamic
    ) -> RigidBody {
        RigidBody(
            primitive: Sphere(center: .zero, radius: 0.5),
            transform: Transform(position: position),
            motionType: motionType,
            material: PhysicsMaterial(friction: 0, restitution: 0))
    }

    private func makeSimulator(_ bodies: RigidBody...) -> RigidBodySimulator {
        let simulator = RigidBodySimulator(
            gravity: .zero,
            solver: SequentialImpulseRigidBodySolver(ccdConfiguration: .init(mode: .timeOfImpact)))
        for body in bodies {
            XCTAssertTrue(simulator.add(body))
        }
        return simulator
    }
}
