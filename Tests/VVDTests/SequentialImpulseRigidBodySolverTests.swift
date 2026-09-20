import Foundation
import XCTest
import VVD

final class SequentialImpulseRigidBodySolverTests: XCTestCase {
    func testIntegratesForcesTorqueAndCenterOfMassThenClearsForces() {
        let body = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            massProperties: RigidBodyMassProperties(
                mass: 2,
                centerOfMass: Vector3(1, 0, 0),
                inertia: Vector3(2, 2, 2)))
        body.addForce(Vector3(4, 0, 0))
        body.addTorque(Vector3(0, 0, 4))
        let initialCenter = body.massProperties.centerOfMass
            .applying(body.transform)
        let solver = SequentialImpulseRigidBodySolver(velocityIterations: 0)

        solver.solve(RigidBodySolverContext(
            timeStep: 0.5,
            gravity: Vector3(0, -10, 0),
            bodies: [body],
            contacts: [],
            constraints: []))

        XCTAssertEqual(body.linearVelocity.x, 1, accuracy: 1.0e-9)
        XCTAssertEqual(body.linearVelocity.y, -5, accuracy: 1.0e-9)
        XCTAssertEqual(body.angularVelocity.z, 1, accuracy: 1.0e-9)
        let expectedCenter = initialCenter + body.linearVelocity * 0.5
        let integratedCenter = body.massProperties.centerOfMass
            .applying(body.transform)
        XCTAssertEqual(integratedCenter.x, expectedCenter.x, accuracy: 1.0e-9)
        XCTAssertEqual(integratedCenter.y, expectedCenter.y, accuracy: 1.0e-9)
        XCTAssertEqual(integratedCenter.z, expectedCenter.z, accuracy: 1.0e-9)
        XCTAssertEqual(body.transform.orientation.angle, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(body.accumulatedForces, ForceAccumulator())
    }

    func testStaticAndKinematicBodiesUseTheirMotionContracts() {
        let staticBody = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            motionType: .static)
        staticBody.linearVelocity = Vector3(5, 0, 0)
        staticBody.addForce(Vector3(100, 0, 0))

        let kinematicBody = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            motionType: .kinematic)
        kinematicBody.linearVelocity = Vector3(2, 0, 0)
        kinematicBody.angularVelocity = Vector3(0, 0, 1)
        kinematicBody.addForce(Vector3(100, 0, 0))

        let dampedBody = RigidBody(
            primitive: Sphere(center: .zero, radius: 1))
        dampedBody.linearVelocity = Vector3(4, 0, 0)
        dampedBody.linearDamping = log(2)
        let solver = SequentialImpulseRigidBodySolver(velocityIterations: 0)
        solver.solve(RigidBodySolverContext(
            timeStep: 1,
            gravity: Vector3(0, -10, 0),
            bodies: [staticBody, kinematicBody, dampedBody],
            contacts: [],
            constraints: []))

        XCTAssertEqual(staticBody.transform, .identity)
        XCTAssertEqual(kinematicBody.transform.position, Vector3(2, 0, 0))
        XCTAssertEqual(kinematicBody.transform.orientation.angle,
                       1,
                       accuracy: 1.0e-9)
        XCTAssertEqual(kinematicBody.linearVelocity, Vector3(2, 0, 0))
        XCTAssertEqual(dampedBody.linearVelocity.x, 2, accuracy: 1.0e-9)
        XCTAssertEqual(staticBody.accumulatedForces, ForceAccumulator())
        XCTAssertEqual(kinematicBody.accumulatedForces, ForceAccumulator())
    }

    func testContactRestitutionReversesClosingVelocity() {
        let material = PhysicsMaterial(friction: 0, restitution: 0.5)
        let bodyA = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            material: material)
        bodyA.linearVelocity = Vector3(2, 0, 0)
        let bodyB = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(2, 0, 0)),
            motionType: .static,
            material: material)
        let contact = makeContact(bodyA: bodyA,
                                  bodyB: bodyB,
                                  penetrationDepth: 0)
        let solver = SequentialImpulseRigidBodySolver(
            restitutionVelocityThreshold: 0)

        solver.solve(RigidBodySolverContext(
            timeStep: 0.1,
            gravity: .zero,
            bodies: [bodyA, bodyB],
            contacts: [contact],
            constraints: []))

        XCTAssertEqual(bodyA.linearVelocity.x, -1, accuracy: 1.0e-9)
        XCTAssertEqual(bodyB.linearVelocity, .zero)
    }

    func testContactFrictionUsesCoulombImpulseLimit() {
        let material = PhysicsMaterial(friction: 0.25, restitution: 0)
        let bodyA = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            material: material)
        bodyA.linearVelocity = Vector3(2, 1, 0)
        let bodyB = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(2, 0, 0)),
            motionType: .static,
            material: material)
        let contact = makeContact(bodyA: bodyA,
                                  bodyB: bodyB,
                                  penetrationDepth: 0)

        SequentialImpulseRigidBodySolver().solve(RigidBodySolverContext(
            timeStep: 0.1,
            gravity: .zero,
            bodies: [bodyA, bodyB],
            contacts: [contact],
            constraints: []))

        XCTAssertEqual(bodyA.linearVelocity.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(bodyA.linearVelocity.y, 0.5, accuracy: 1.0e-9)
    }

    func testContactBiasSeparatesPenetratingBodies() {
        let bodyA = RigidBody(primitive: Sphere(center: .zero, radius: 1))
        let bodyB = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(1.8, 0, 0)),
            motionType: .static)
        let contact = makeContact(bodyA: bodyA,
                                  bodyB: bodyB,
                                  penetrationDepth: 0.205)
        let solver = SequentialImpulseRigidBodySolver(
            positionCorrectionFactor: 0.2,
            penetrationSlop: 0.005,
            restitutionVelocityThreshold: 1,
            maximumBiasVelocity: 10)

        solver.solve(RigidBodySolverContext(
            timeStep: 0.1,
            gravity: .zero,
            bodies: [bodyA, bodyB],
            contacts: [contact],
            constraints: []))

        XCTAssertEqual(bodyA.linearVelocity.x, -0.4, accuracy: 1.0e-9)
        XCTAssertEqual(bodyA.transform.position.x, -0.04, accuracy: 1.0e-9)
    }

    func testFixedJointRowsAreSolvedWithBodyImpulses() {
        let bodyA = RigidBody(primitive: Sphere(center: .zero, radius: 1))
        let bodyB = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(1, 0, 0)))
        let joint = FixedJointConstraint(bodyA: bodyA,
                                         bodyB: bodyB,
                                         biasFactor: 0.2)

        SequentialImpulseRigidBodySolver().solve(RigidBodySolverContext(
            timeStep: 0.1,
            gravity: .zero,
            bodies: [bodyA, bodyB],
            contacts: [],
            constraints: [joint]))

        XCTAssertEqual(bodyA.linearVelocity.x, 1, accuracy: 1.0e-9)
        XCTAssertEqual(bodyB.linearVelocity.x, -1, accuracy: 1.0e-9)
        XCTAssertEqual(bodyA.transform.position.x, 0.1, accuracy: 1.0e-9)
        XCTAssertEqual(bodyB.transform.position.x, 0.9, accuracy: 1.0e-9)
    }

    func testPersistentContactWarmStartsNextStep() {
        let bodyA = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            material: PhysicsMaterial(friction: 0, restitution: 0))
        let bodyB = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(2, 0, 0)),
            motionType: .static,
            material: PhysicsMaterial(friction: 0, restitution: 0))
        let contact = makeContact(bodyA: bodyA,
                                  bodyB: bodyB,
                                  penetrationDepth: 0,
                                  featureID: ContactFeatureID(7))
        let solver = SequentialImpulseRigidBodySolver(velocityIterations: 1)

        solver.solve(RigidBodySolverContext(
            timeStep: 1,
            gravity: Vector3(1, 0, 0),
            bodies: [bodyA, bodyB],
            contacts: [contact],
            constraints: []))

        XCTAssertEqual(bodyA.linearVelocity.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(solver.cachedContactCount, 1)

        solver.velocityIterations = 0
        solver.solve(RigidBodySolverContext(
            timeStep: 1,
            gravity: Vector3(1, 0, 0),
            bodies: [bodyA, bodyB],
            contacts: [contact],
            constraints: []))

        XCTAssertEqual(bodyA.linearVelocity.x, 0, accuracy: 1.0e-9)
    }

    func testWarmStartReprojectsWorldFrictionIntoNewTangentBasis() {
        let material = PhysicsMaterial(friction: 1, restitution: 0)
        let bodyA = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            material: material)
        bodyA.linearVelocity = Vector3(1, 1, 0)
        let bodyB = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(2, 0, 0)),
            motionType: .static,
            material: material)
        let contact = makeContact(bodyA: bodyA,
                                  bodyB: bodyB,
                                  penetrationDepth: 0,
                                  featureID: ContactFeatureID(9))
        let solver = SequentialImpulseRigidBodySolver(velocityIterations: 1)

        solver.solve(RigidBodySolverContext(
            timeStep: 0.1,
            gravity: .zero,
            bodies: [bodyA, bodyB],
            contacts: [contact],
            constraints: []))
        XCTAssertEqual(bodyA.linearVelocity, .zero)

        bodyA.linearVelocity = Vector3(1, 0, 1)
        solver.velocityIterations = 0
        solver.solve(RigidBodySolverContext(
            timeStep: 0.1,
            gravity: .zero,
            bodies: [bodyA, bodyB],
            contacts: [contact],
            constraints: []))

        XCTAssertEqual(bodyA.linearVelocity.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(bodyA.linearVelocity.y, -1, accuracy: 1.0e-9)
        XCTAssertEqual(bodyA.linearVelocity.z, 1, accuracy: 1.0e-9)
    }

    func testSeparatingContactReleasesWarmStartedFriction() {
        let material = PhysicsMaterial(friction: 1, restitution: 0)
        let bodyA = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            material: material)
        let bodyB = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(2, 0, 0)),
            motionType: .static,
            material: material)
        let solver = SequentialImpulseRigidBodySolver()
        let simulator = RigidBodySimulator(gravity: .zero, solver: solver)
        XCTAssertTrue(simulator.add(bodyA))
        XCTAssertTrue(simulator.add(bodyB))

        bodyA.linearVelocity = Vector3(1, 0.5, 0.5)
        simulator.step(timeStep: 0.1)

        XCTAssertEqual(bodyA.linearVelocity.length, 0, accuracy: 1.0e-9)
        XCTAssertEqual(solver.cachedContactCount, 1)

        bodyA.linearVelocity = Vector3(-1, 0, 0)
        simulator.step(timeStep: 0.1)

        XCTAssertEqual(bodyA.linearVelocity.x, -1, accuracy: 1.0e-9)
        XCTAssertEqual(bodyA.linearVelocity.y, 0, accuracy: 1.0e-9)
        XCTAssertEqual(bodyA.linearVelocity.z, 0, accuracy: 1.0e-9)
    }

    func testDisablingWarmStartClearsContactCache() {
        let bodyA = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            material: PhysicsMaterial(friction: 0))
        let bodyB = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(2, 0, 0)),
            motionType: .static,
            material: PhysicsMaterial(friction: 0))
        let solver = SequentialImpulseRigidBodySolver(velocityIterations: 1)
        let featureOne = makeContact(bodyA: bodyA,
                                     bodyB: bodyB,
                                     penetrationDepth: 0,
                                     featureID: ContactFeatureID(1))

        bodyA.linearVelocity = Vector3(1, 0, 0)
        solver.solve(RigidBodySolverContext(
            timeStep: 0.1,
            gravity: .zero,
            bodies: [bodyA, bodyB],
            contacts: [featureOne],
            constraints: []))
        XCTAssertEqual(solver.cachedContactCount, 1)

        solver.isWarmStartingEnabled = false
        solver.velocityIterations = 0
        bodyA.linearVelocity = Vector3(1, 0, 0)
        solver.solve(RigidBodySolverContext(
            timeStep: 0.1,
            gravity: .zero,
            bodies: [bodyA, bodyB],
            contacts: [featureOne],
            constraints: []))

        XCTAssertEqual(bodyA.linearVelocity.x, 1, accuracy: 1.0e-9)
        XCTAssertEqual(solver.cachedContactCount, 0)

        solver.isWarmStartingEnabled = true
        solver.solve(RigidBodySolverContext(
            timeStep: 0.1,
            gravity: .zero,
            bodies: [bodyA, bodyB],
            contacts: [],
            constraints: []))
        XCTAssertEqual(solver.cachedContactCount, 0)
    }

    func testSleepingContactRetainsCacheUntilFeatureDisappears() {
        let bodyA = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            material: PhysicsMaterial(friction: 0))
        bodyA.linearVelocity = Vector3(1, 0, 0)
        let bodyB = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(2, 0, 0)),
            motionType: .static,
            material: PhysicsMaterial(friction: 0))
        let contact = makeContact(bodyA: bodyA,
                                  bodyB: bodyB,
                                  penetrationDepth: 0,
                                  featureID: ContactFeatureID(11))
        let solver = SequentialImpulseRigidBodySolver(velocityIterations: 1)

        solver.solve(RigidBodySolverContext(
            timeStep: 0.1,
            gravity: .zero,
            bodies: [bodyA, bodyB],
            contacts: [contact],
            constraints: []))
        bodyA.putToSleep()

        solver.solve(RigidBodySolverContext(
            timeStep: 0.1,
            gravity: .zero,
            bodies: [bodyA, bodyB],
            contacts: [contact],
            constraints: []))
        XCTAssertTrue(bodyA.isSleeping)
        XCTAssertEqual(solver.cachedContactCount, 1)

        solver.solve(RigidBodySolverContext(
            timeStep: 0.1,
            gravity: .zero,
            bodies: [bodyA, bodyB],
            contacts: [],
            constraints: []))
        XCTAssertEqual(solver.cachedContactCount, 0)
    }

    private func makeContact(bodyA: RigidBody,
                             bodyB: RigidBody,
                             penetrationDepth: Scalar,
                             featureID: ContactFeatureID = ContactFeatureID())
        -> RigidBodyContact {
        RigidBodyContact(
            bodyA: bodyA,
            bodyB: bodyB,
            manifold: ContactManifold(Contact(
                pointOnA: Vector3(1, 0, 0),
                pointOnB: Vector3(1, 0, 0),
                normal: Vector3(1, 0, 0),
                penetrationDepth: penetrationDepth,
                featureID: featureID)))
    }
}
