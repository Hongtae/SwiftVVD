import XCTest
import VVD

final class DynamicsInterfaceTests: XCTestCase {
    func testCollisionSpaceOwnsColliderIdentityAndProducesWorldContacts() throws {
        let colliderA = Collider(primitive: Sphere(center: .zero, radius: 1),
                                 transform: Transform(position: Vector3(3, 0, 0)))
        let colliderB = Collider(primitive: Sphere(center: .zero, radius: 1),
                                 transform: Transform(position: Vector3(4.5, 0, 0)))
        let space = CollisionSpace()

        XCTAssertTrue(space.add(colliderA))
        XCTAssertFalse(space.add(colliderA))
        XCTAssertTrue(space.add(colliderB))

        let pair = try XCTUnwrap(space.collisionPairs().first)
        XCTAssertTrue(pair.colliderA === colliderA)
        XCTAssertTrue(pair.colliderB === colliderB)

        let contact = try XCTUnwrap(pair.worldContactManifold?.contacts.first)
        XCTAssertEqual(contact.pointOnA.x, 4, accuracy: 1.0e-9)
        XCTAssertEqual(contact.pointOnB.x, 3.5, accuracy: 1.0e-9)
        XCTAssertEqual(contact.normal.x, 1, accuracy: 1.0e-9)
    }

    func testRigidBodySimulatorBuildsContextAndDelegatesToSolver() throws {
        let solver = RecordingRigidBodySolver()
        let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0),
                                           solver: solver)
        let bodyA = RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            material: PhysicsMaterial(friction: 0.25,
                                      restitution: 0.2,
                                      frictionCombineMode: .multiply,
                                      restitutionCombineMode: .maximum))
        let bodyB = RigidBody(primitive: Sphere(center: .zero, radius: 1),
                              transform: Transform(position: Vector3(1.5, 0, 0)),
                              motionType: .static,
                              material: PhysicsMaterial(friction: 0.8,
                                                        restitution: 0.6))
        let constraint = FixedJointConstraint(bodyA: bodyA, bodyB: bodyB)

        XCTAssertTrue(simulator.add(bodyA))
        XCTAssertTrue(simulator.add(bodyB))
        XCTAssertTrue(simulator.add(constraint))
        XCTAssertTrue(simulator.collisionSpace.contains(bodyA.collider))

        simulator.step(timeStep: 1.0 / 60.0)

        let context = try XCTUnwrap(solver.context)
        XCTAssertEqual(context.bodies.count, 2)
        XCTAssertEqual(context.contacts.count, 1)
        XCTAssertEqual(context.constraints.count, 1)
        XCTAssertEqual(context.gravity.y, -10, accuracy: 1.0e-9)
        XCTAssertTrue(context.contacts[0].bodyA === bodyA)
        XCTAssertTrue(context.contacts[0].bodyB === bodyB)
        XCTAssertEqual(context.contacts[0].material.friction,
                       0.2,
                       accuracy: 1.0e-9)
        XCTAssertEqual(context.contacts[0].material.restitution,
                       0.6,
                       accuracy: 1.0e-9)
    }

    func testForceAccumulatorAndMassPropertiesExposeSolverInputs() {
        let body = RigidBody(primitive: Box(halfExtents: Vector3(1, 1, 1)),
                             massProperties: RigidBodyMassProperties(
                                mass: 2,
                                centerOfMass: .zero,
                                inertia: Vector3(4, 5, 10)))

        body.addForce(Vector3(2, 0, 0))
        body.addForce(Vector3(0, 3, 0), at: Vector3(0, 0, 2))

        XCTAssertEqual(body.inverseMass, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(body.inverseInertia.x, 0.25, accuracy: 1.0e-9)
        XCTAssertEqual(body.accumulatedForces.force, Vector3(2, 3, 0))
        XCTAssertEqual(body.accumulatedForces.torque, Vector3(-6, 0, 0))

        body.removeAllForces()
        XCTAssertEqual(body.accumulatedForces, ForceAccumulator())
    }

    func testXPBDSimulatorOwnsBodiesAndDelegatesToSolver() throws {
        let solver = RecordingXPBDSolver()
        let simulator = XPBDSimulator(solver: solver)
        let rope = RopeBody(particles: [
            XPBDParticle(position: .zero, mass: 0),
            XPBDParticle(position: Vector3(0, -1, 0), mass: 1)
        ])
        let constraint = XPBDFixedJointConstraint(
            particleA: XPBDParticleReference(body: rope, particleIndex: 1),
            worldAnchor: Vector3(0, -1, 0))

        XCTAssertTrue(simulator.add(rope))
        XCTAssertFalse(simulator.add(rope))
        XCTAssertTrue(simulator.add(constraint))

        simulator.step(timeStep: 1.0 / 120.0)

        let context = try XCTUnwrap(solver.context)
        XCTAssertEqual(context.bodies.count, 1)
        XCTAssertEqual(context.constraints.count, 1)
        XCTAssertTrue(rope.particles[0].isPinned)
        XCTAssertFalse(rope.particles[1].isPinned)
    }
}

private final class RecordingRigidBodySolver: RigidBodySolver {
    var context: RigidBodySolverContext?

    func solve(_ context: RigidBodySolverContext) {
        self.context = context
    }
}

private final class RecordingXPBDSolver: XPBDSolver {
    var context: XPBDSolverContext?

    func solve(_ context: XPBDSolverContext) {
        self.context = context
    }
}
