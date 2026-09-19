import XCTest
import VVD

final class DefaultDynamicsSolverTests: XCTestCase {
    func testRigidBodySimulatorUsesSequentialImpulseSolverByDefault() {
        let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0))
        let body = RigidBody(primitive: Sphere(center: .zero, radius: 0.5))
        XCTAssertTrue(simulator.add(body))

        simulator.step(timeStep: 0.1)

        XCTAssertTrue(simulator.solver is SequentialImpulseRigidBodySolver)
        XCTAssertEqual(body.linearVelocity.y, -1, accuracy: 1.0e-9)
        XCTAssertEqual(body.transform.position.y, -0.1, accuracy: 1.0e-9)
    }

    func testXPBDSimulatorUsesProjectionSolverByDefault() {
        let simulator = XPBDSimulator(gravity: Vector3(0, -10, 0))
        let rope = RopeBody(particles: [XPBDParticle(position: .zero)])
        XCTAssertTrue(simulator.add(rope))

        simulator.step(timeStep: 0.1)

        XCTAssertTrue(simulator.solver is XPBDProjectionSolver)
        XCTAssertEqual(rope.particles[0].velocity.y, -1, accuracy: 1.0e-9)
        XCTAssertEqual(rope.particles[0].position.y, -0.1, accuracy: 1.0e-9)
    }

    func testExplicitNilSolverKeepsNoOpStrategyBoundary() {
        let rigid = RigidBodySimulator(gravity: Vector3(0, -10, 0),
                                       solver: nil)
        let rigidBody = RigidBody(
            primitive: Sphere(center: .zero, radius: 0.5))
        XCTAssertTrue(rigid.add(rigidBody))

        let xpbd = XPBDSimulator(gravity: Vector3(0, -10, 0), solver: nil)
        let rope = RopeBody(particles: [XPBDParticle(position: .zero)])
        XCTAssertTrue(xpbd.add(rope))

        rigid.step(timeStep: 0.1)
        xpbd.step(timeStep: 0.1)

        XCTAssertEqual(rigidBody.transform, .identity)
        XCTAssertEqual(rigidBody.linearVelocity, .zero)
        XCTAssertEqual(rope.particles[0].position, .zero)
        XCTAssertEqual(rope.particles[0].velocity, .zero)
    }

    func testDynamicsSimulatorDefaultsBothConcretePipelines() {
        let simulator = DynamicsSimulator()

        XCTAssertTrue(simulator.rigidBodies.solver is
                      SequentialImpulseRigidBodySolver)
        XCTAssertTrue(simulator.xpbd.solver is XPBDProjectionSolver)
    }
}
