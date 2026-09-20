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

    func testRemovingGroundWakesSupportedIslandWithoutWakingOtherBodies() {
        let ground = RigidBody(
            primitive: StaticPlane(Plane(normal: Vector3(0, 1, 0),
                                         point: .zero)),
            motionType: .static)
        let lower = sphereBody(position: Vector3(0, 0.5, 0))
        let upper = sphereBody(position: Vector3(0, 1.5, 0))
        let isolated = sphereBody(position: Vector3(10, 10, 0))
        isolated.gravityScale = 0
        let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0))
        for body in [ground, lower, upper, isolated] {
            XCTAssertTrue(simulator.add(body))
        }
        for _ in 0..<120 { simulator.step(timeStep: 1.0 / 120.0) }

        XCTAssertTrue(lower.isSleeping)
        XCTAssertTrue(upper.isSleeping)
        XCTAssertTrue(isolated.isSleeping)
        let lowerPosition = lower.transform.position
        let upperPosition = upper.transform.position

        XCTAssertTrue(simulator.remove(ground))
        simulator.step(timeStep: 0.1)

        XCTAssertFalse(lower.isSleeping)
        XCTAssertFalse(upper.isSleeping)
        XCTAssertLessThan(lower.transform.position.y, lowerPosition.y)
        XCTAssertLessThan(upper.transform.position.y, upperPosition.y)
        XCTAssertLessThan(lower.linearVelocity.y, 0)
        XCTAssertLessThan(upper.linearVelocity.y, 0)
        XCTAssertTrue(isolated.isSleeping)
        XCTAssertEqual(isolated.transform.position, Vector3(10, 10, 0))
    }

    func testRemovingWorldJointWakesAttachedBody() {
        let body = sphereBody(position: .zero)
        let joint = FixedJointConstraint(bodyA: body)
        let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0))
        XCTAssertTrue(simulator.add(body))
        XCTAssertTrue(simulator.add(joint))
        body.putToSleep()

        XCTAssertTrue(simulator.remove(joint))
        simulator.step(timeStep: 0.1)

        XCTAssertFalse(body.isSleeping)
        XCTAssertEqual(body.linearVelocity.y, -1, accuracy: 1.0e-9)
        XCTAssertEqual(body.transform.position.y, -0.1, accuracy: 1.0e-9)
    }

    func testRemovingJointAnchorWakesAttachedBodyWithoutContact() {
        let anchor = sphereBody(position: Vector3(3, 0, 0),
                                motionType: .static)
        let body = sphereBody(position: .zero)
        let joint = FixedJointConstraint(
            bodyA: anchor,
            bodyB: body,
            frameA: Transform(position: Vector3(-3, 0, 0)))
        let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0))
        XCTAssertTrue(simulator.add(anchor))
        XCTAssertTrue(simulator.add(body))
        XCTAssertTrue(simulator.add(joint))
        body.putToSleep()

        XCTAssertTrue(simulator.remove(anchor))
        simulator.step(timeStep: 0.1)

        XCTAssertTrue(simulator.constraints.isEmpty)
        XCTAssertFalse(body.isSleeping)
        XCTAssertEqual(body.linearVelocity.y, -1, accuracy: 1.0e-9)
        XCTAssertEqual(body.transform.position.y, -0.1, accuracy: 1.0e-9)
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

    func testDisablingGroundWakesSupportedIslandThroughEitherEnabledProperty() {
        for changeColliderDirectly in [false, true] {
            let ground = RigidBody(primitive: Box(halfExtents: Vector3(5, 0.5, 5)),
                transform: Transform(position: Vector3(0, -0.5, 0)), motionType: .static)
            let lower = sphereBody(position: Vector3(0, 0.5, 0))
            let upper = sphereBody(position: Vector3(0, 1.5, 0))
            let isolated = sphereBody(position: Vector3(10, 10, 0))
            isolated.gravityScale = 0
            let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0))
            for body in [ground, lower, upper, isolated] { simulator.add(body) }
            for _ in 0..<120 { simulator.step(timeStep: 1.0 / 120.0) }
            XCTAssertTrue(lower.isSleeping)
            XCTAssertTrue(upper.isSleeping)
            XCTAssertTrue(isolated.isSleeping)

            if changeColliderDirectly { ground.collider.isEnabled = false }
            else { ground.isEnabled = false }
            // Preserve the old support connection even if the disabled collider
            // is moved before the next step observes the change.
            ground.transform = Transform(position: Vector3(100, 100, 0))
            _ = simulator.solverContext(timeStep: 0.1)
            XCTAssertTrue(lower.isSleeping, "Context queries must not wake bodies")
            simulator.step(timeStep: 0.1)

            XCTAssertFalse(lower.isSleeping)
            XCTAssertFalse(upper.isSleeping)
            XCTAssertLessThan(lower.linearVelocity.y, 0)
            XCTAssertLessThan(upper.linearVelocity.y, 0)
            XCTAssertTrue(isolated.isSleeping)
        }
    }

    func testDisablingJointWakesItsBodyIncludingCustomConstraintsAndRemoval() {
        for custom in [false, true] {
            for removeBeforeStep in [false, true] {
                let body = sphereBody(position: .zero)
                let joint: any RigidBodyConstraint = custom
                    ? SleepingTestJoint(bodyA: body) : FixedJointConstraint(bodyA: body)
                let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0))
                simulator.add(body)
                simulator.add(joint)
                simulator.step(timeStep: 0.1)
                body.putToSleep()

                joint.isEnabled = false
                if removeBeforeStep { XCTAssertTrue(simulator.remove(joint)) }
                simulator.step(timeStep: 0.1)

                XCTAssertFalse(body.isSleeping)
                XCTAssertEqual(body.linearVelocity.y, -1, accuracy: 1.0e-9)
                XCTAssertEqual(body.transform.position.y, -0.1, accuracy: 1.0e-9)
                body.putToSleep()
                simulator.step(timeStep: 0.1)
                XCTAssertTrue(body.isSleeping, "A disabled joint must not wake every step")
            }
        }
    }

    func testDisablingJointAnchorWakesBodyWithoutContact() {
        let anchor = sphereBody(position: Vector3(3, 0, 0), motionType: .static)
        let body = sphereBody(position: .zero)
        let joint = FixedJointConstraint(bodyA: anchor, bodyB: body,
            frameA: Transform(position: Vector3(-3, 0, 0)))
        let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0))
        simulator.add(anchor)
        simulator.add(body)
        simulator.add(joint)
        simulator.step(timeStep: 0.1)
        body.putToSleep()

        anchor.collider.isEnabled = false
        simulator.step(timeStep: 0.1)

        XCTAssertFalse(body.isSleeping)
        XCTAssertEqual(body.linearVelocity.y, -1, accuracy: 1.0e-9)
        XCTAssertEqual(body.transform.position.y, -0.1, accuracy: 1.0e-9)
        body.putToSleep()
        simulator.step(timeStep: 0.1)
        XCTAssertTrue(body.isSleeping)
    }

    func testDisablingSupportBeforeFirstStepWakesManuallySleepingBody() {
        let ground = RigidBody(primitive: StaticPlane(
            Plane(normal: Vector3(0, 1, 0), point: .zero)), motionType: .static)
        let body = sphereBody(position: Vector3(0, 0.5, 0))
        let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0))
        simulator.add(ground)
        simulator.add(body)
        body.putToSleep()

        ground.isEnabled = false
        simulator.step(timeStep: 0.1)

        XCTAssertFalse(body.isSleeping)
        XCTAssertEqual(body.linearVelocity.y, -1, accuracy: 1.0e-9)
    }

    func testDisablingMovedSupportWakesBodyThatSleptAfterNewCCDContact() {
        let wall = sphereBody(position: Vector3(3, 0, 0), motionType: .static)
        let body = sphereBody(position: .zero)
        body.linearVelocity = Vector3(10, 0, 0)
        body.isContinuousCollisionDetectionEnabled = true
        let simulator = RigidBodySimulator(gravity: Vector3(10, 0, 0),
            solver: SequentialImpulseRigidBodySolver(ccdConfiguration: .init(mode: .timeOfImpact)))
        simulator.add(wall)
        simulator.add(body)
        simulator.step(timeStep: 0.5)
        XCTAssertTrue(body.isSleeping)
        XCTAssertEqual(body.transform.position.x, 2, accuracy: 1.0e-9)

        wall.isEnabled = false
        wall.transform = Transform(position: Vector3(100, 0, 0))
        simulator.step(timeStep: 0.1)

        XCTAssertFalse(body.isSleeping)
        XCTAssertEqual(body.linearVelocity.x, 1, accuracy: 1.0e-9)
    }

    func testChangingEnabledSupportGeometryOrFilterWakesOnlyAffectedIsland() {
        for change in 0..<3 {
            let ground = RigidBody(primitive: Box(halfExtents: Vector3(5, 0.5, 5)),
                transform: Transform(position: Vector3(0, -0.5, 0)), motionType: .static)
            let lower = sphereBody(position: Vector3(0, 0.5, 0))
            let upper = sphereBody(position: Vector3(0, 1.5, 0))
            let isolated = sphereBody(position: Vector3(20, 10, 0))
            isolated.gravityScale = 0
            let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0))
            for body in [ground, lower, upper, isolated] { simulator.add(body) }
            for _ in 0..<120 { simulator.step(timeStep: 1.0 / 120.0) }
            XCTAssertTrue(lower.isSleeping)
            XCTAssertTrue(upper.isSleeping)
            XCTAssertTrue(isolated.isSleeping)

            switch change {
            case 0: ground.transform = Transform(position: Vector3(100, 0, 0))
            case 1: ground.collider.filter = CollisionFilter(mask: .none)
            default: ground.collider.primitive = Box(halfExtents: Vector3(5, 0.1, 5))
            }
            _ = simulator.solverContext(timeStep: 0.1)
            simulator.step(timeStep: .infinity)
            XCTAssertTrue(lower.isSleeping, "Queries and invalid steps must not consume changes")
            let solver = simulator.solver
            simulator.solver = nil
            simulator.step(timeStep: 0.1)
            XCTAssertTrue(lower.isSleeping)
            simulator.solver = solver
            simulator.step(timeStep: 0.1)

            XCTAssertFalse(lower.isSleeping, "change=\(change)")
            XCTAssertFalse(upper.isSleeping, "change=\(change)")
            XCTAssertLessThan(lower.linearVelocity.y, 0)
            XCTAssertLessThan(upper.linearVelocity.y, 0)
            XCTAssertTrue(isolated.isSleeping)
            lower.putToSleep()
            upper.putToSleep()
            simulator.step(timeStep: 0.01)
            XCTAssertTrue(lower.isSleeping, "An observed change must not wake every step")
        }
    }

    func testMovingSupportBeforeFirstStepWakesSleepingBody() {
        let ground = RigidBody(primitive: StaticPlane(
            Plane(normal: Vector3(0, 1, 0), point: .zero)), motionType: .static)
        let body = sphereBody(position: Vector3(0, 0.5, 0))
        let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0))
        simulator.add(ground)
        simulator.add(body)
        body.putToSleep()
        ground.collider.transform = Transform(position: Vector3(0, -10, 0))

        simulator.step(timeStep: 0.1)

        XCTAssertFalse(body.isSleeping)
        XCTAssertEqual(body.linearVelocity.y, -1, accuracy: 1.0e-9)
    }

    private func sphereBody(
        position: Vector3,
        motionType: RigidBodyMotionType = .dynamic
    ) -> RigidBody {
        RigidBody(primitive: Sphere(center: .zero, radius: 0.5),
                  transform: Transform(position: position),
                  motionType: motionType)
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

private final class SleepingTestJoint: RigidBodyConstraint {
    let bodyA: RigidBody
    var bodyB: RigidBody? { nil }
    var isEnabled = true
    init(bodyA: RigidBody) { self.bodyA = bodyA }
    func solverRows(timeStep: Scalar) -> [RigidBodyConstraintRow] {
        isEnabled ? FixedJointConstraint(bodyA: bodyA).solverRows(timeStep: timeStep) : []
    }
}
