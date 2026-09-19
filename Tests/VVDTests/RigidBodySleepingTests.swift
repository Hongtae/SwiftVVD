import XCTest
import VVD

final class RigidBodySleepingTests: XCTestCase {
    func testStationaryBodySleepsAndSkipsIntegrationUntilForceWakesIt() {
        let body = RigidBody(primitive: Sphere(center: .zero, radius: 1))
        let solver = SequentialImpulseRigidBodySolver(
            velocityIterations: 0,
            linearSleepThreshold: 0.1,
            angularSleepThreshold: 0.1,
            sleepDelay: 0.5)

        for _ in 0..<2 {
            solver.solve(context(bodies: [body], timeStep: 0.2))
            XCTAssertFalse(body.isSleeping)
        }
        solver.solve(context(bodies: [body], timeStep: 0.2))

        XCTAssertTrue(body.isSleeping)
        XCTAssertEqual(body.sleepDuration, 0.6, accuracy: 1.0e-9)
        let sleepingTransform = body.transform

        solver.solve(context(bodies: [body],
                             timeStep: 1,
                             gravity: Vector3(0, -10, 0)))

        XCTAssertTrue(body.isSleeping)
        XCTAssertEqual(body.transform, sleepingTransform)
        XCTAssertEqual(body.linearVelocity, .zero)

        body.addForce(Vector3(2, 0, 0))
        XCTAssertFalse(body.isSleeping)
        XCTAssertEqual(body.sleepDuration, 0)

        solver.solve(context(bodies: [body], timeStep: 0.5))

        XCTAssertEqual(body.linearVelocity.x, 1, accuracy: 1.0e-9)
        XCTAssertEqual(body.transform.position.x, 0.5, accuracy: 1.0e-9)
    }

    func testExternalStateChangesWakeSleepingBody() {
        let body = RigidBody(primitive: Sphere(center: .zero, radius: 1))

        body.putToSleep()
        body.transform = Transform(position: Vector3(1, 0, 0))
        XCTAssertFalse(body.isSleeping)

        body.putToSleep()
        body.linearVelocity = Vector3(1, 0, 0)
        XCTAssertFalse(body.isSleeping)

        body.putToSleep()
        body.angularVelocity = Vector3(0, 1, 0)
        XCTAssertFalse(body.isSleeping)

        body.putToSleep()
        body.allowsSleeping = false
        XCTAssertFalse(body.isSleeping)
        body.putToSleep()
        XCTAssertFalse(body.isSleeping)
    }

    func testContactConnectedIslandWakesTogetherAndLeavesOtherIslandSleeping() {
        let bodyA = RigidBody(primitive: Sphere(center: .zero, radius: 1))
        let bodyB = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(2, 0, 0)))
        let isolated = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(10, 0, 0)))
        bodyA.putToSleep()
        bodyB.putToSleep()
        isolated.putToSleep()
        bodyA.linearVelocity = Vector3(1, 0, 0)
        let contact = RigidBodyContact(
            bodyA: bodyA,
            bodyB: bodyB,
            manifold: ContactManifold(Contact(
                pointOnA: Vector3(1, 0, 0),
                pointOnB: Vector3(1, 0, 0),
                normal: Vector3(1, 0, 0),
                penetrationDepth: 0,
                featureID: ContactFeatureID(1))))
        let solver = SequentialImpulseRigidBodySolver(
            velocityIterations: 0,
            linearSleepThreshold: 0.1,
            angularSleepThreshold: 0.1,
            sleepDelay: 0.5)

        solver.solve(context(bodies: [bodyA, bodyB, isolated],
                             contacts: [contact],
                             timeStep: 0.1))

        XCTAssertFalse(bodyA.isSleeping)
        XCTAssertFalse(bodyB.isSleeping)
        XCTAssertTrue(isolated.isSleeping)
        XCTAssertEqual(bodyA.transform.position.x, 0.1, accuracy: 1.0e-9)
        XCTAssertEqual(isolated.transform.position.x, 10, accuracy: 1.0e-9)
    }

    func testMovingKinematicContactWakesDynamicIsland() {
        let dynamicBody = RigidBody(
            primitive: Sphere(center: .zero, radius: 1))
        dynamicBody.putToSleep()
        let kinematicBody = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(2, 0, 0)),
            motionType: .kinematic)
        kinematicBody.linearVelocity = Vector3(-1, 0, 0)
        let contact = RigidBodyContact(
            bodyA: dynamicBody,
            bodyB: kinematicBody,
            manifold: ContactManifold(Contact(
                pointOnA: Vector3(1, 0, 0),
                pointOnB: Vector3(1, 0, 0),
                normal: Vector3(1, 0, 0),
                penetrationDepth: 0)))

        SequentialImpulseRigidBodySolver(velocityIterations: 0).solve(
            context(bodies: [dynamicBody, kinematicBody],
                    contacts: [contact],
                    timeStep: 0.1))

        XCTAssertFalse(dynamicBody.isSleeping)
        XCTAssertEqual(kinematicBody.transform.position.x,
                       1.9,
                       accuracy: 1.0e-9)
    }

    func testDisablingSleepingReactivatesSleepingBodies() {
        let body = RigidBody(primitive: Sphere(center: .zero, radius: 1))
        body.putToSleep()
        let solver = SequentialImpulseRigidBodySolver(
            velocityIterations: 0,
            isSleepingEnabled: false)

        solver.solve(context(bodies: [body], timeStep: 0.1))

        XCTAssertFalse(body.isSleeping)
        XCTAssertEqual(body.sleepDuration, 0)
    }

    private func context(
        bodies: [RigidBody],
        contacts: [RigidBodyContact] = [],
        constraints: [any RigidBodyConstraint] = [],
        timeStep: Scalar,
        gravity: Vector3 = .zero
    ) -> RigidBodySolverContext {
        RigidBodySolverContext(timeStep: timeStep,
                               gravity: gravity,
                               bodies: bodies,
                               contacts: contacts,
                               constraints: constraints)
    }
}
