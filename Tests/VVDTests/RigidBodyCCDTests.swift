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
            solver: SequentialImpulseRigidBodySolver())
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
            solver: SequentialImpulseRigidBodySolver())
        for body in bodies {
            XCTAssertTrue(simulator.add(body))
        }
        return simulator
    }
}
