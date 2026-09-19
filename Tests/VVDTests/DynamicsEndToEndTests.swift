import XCTest
import VVD

final class DynamicsEndToEndTests: XCTestCase {
    func testRigidBodyStackSettlesOnStaticGround() {
        let simulator = RigidBodySimulator()
        let ground = RigidBody(
            primitive: StaticPlane(Plane(normal: Vector3(0, 1, 0),
                                         point: .zero)),
            motionType: .static)
        let lower = sphereBody(position: Vector3(0, 0.5, 0))
        let upper = sphereBody(position: Vector3(0, 1.5, 0))
        XCTAssertTrue(simulator.add(ground))
        XCTAssertTrue(simulator.add(lower))
        XCTAssertTrue(simulator.add(upper))

        step(simulator, count: 360, timeStep: 1.0 / 120.0)

        XCTAssertEqual(lower.transform.position.y, 0.5, accuracy: 0.03)
        XCTAssertEqual(upper.transform.position.y, 1.5, accuracy: 0.05)
        XCTAssertLessThan(abs(lower.linearVelocity.y), 0.15)
        XCTAssertLessThan(abs(upper.linearVelocity.y), 0.15)
    }

    func testFixedJointHoldsBodyAtWorldFrame() {
        let simulator = RigidBodySimulator()
        let body = sphereBody(position: .zero)
        let joint = FixedJointConstraint(bodyA: body,
                                         frameA: .identity,
                                         frameB: .identity)
        XCTAssertTrue(simulator.add(body))
        XCTAssertTrue(simulator.add(joint))

        step(simulator, count: 120, timeStep: 1.0 / 120.0)

        XCTAssertEqual(body.transform.position.x, 0, accuracy: 1.0e-6)
        XCTAssertEqual(body.transform.position.y, 0, accuracy: 0.01)
        XCTAssertEqual(body.transform.position.z, 0, accuracy: 1.0e-6)
        XCTAssertLessThan(body.linearVelocity.length, 0.1)
    }

    func testRopeMaintainsLengthFromPinnedEndpoint() {
        let simulator = XPBDSimulator()
        let rope = RopeBody(particles: [
            XPBDParticle(position: .zero, inverseMass: 0),
            XPBDParticle(position: Vector3(0, -1, 0), inverseMass: 1)
        ])
        XCTAssertTrue(simulator.add(rope))
        for constraint in rope.makeDistanceConstraints() {
            XCTAssertTrue(simulator.add(constraint))
        }

        step(simulator, count: 240, timeStep: 1.0 / 120.0)

        XCTAssertEqual(rope.particles[0].position, .zero)
        XCTAssertEqual((rope.particles[1].position -
                        rope.particles[0].position).length,
                       1,
                       accuracy: 1.0e-6)
        XCTAssertEqual(rope.particles[1].position.y, -1, accuracy: 1.0e-5)
    }

    func testClothMaintainsTriangulatedShapeWithPinnedTopEdge() {
        let simulator = XPBDSimulator()
        let cloth = ClothBody(
            particles: [
                XPBDParticle(position: Vector3(-0.5, 0, 0), inverseMass: 0),
                XPBDParticle(position: Vector3(0.5, 0, 0), inverseMass: 0),
                XPBDParticle(position: Vector3(-0.5, -1, 0)),
                XPBDParticle(position: Vector3(0.5, -1, 0))
            ],
            triangles: [XPBDParticleTriangle(0, 2, 1),
                        XPBDParticleTriangle(1, 2, 3)])
        XCTAssertTrue(simulator.add(cloth))
        for constraint in cloth.makeDistanceConstraints() {
            XCTAssertTrue(simulator.add(constraint))
        }
        for constraint in cloth.makeBendingConstraints() {
            XCTAssertTrue(simulator.add(constraint))
        }

        step(simulator, count: 240, timeStep: 1.0 / 120.0)

        XCTAssertEqual(cloth.particles[0].position, Vector3(-0.5, 0, 0))
        XCTAssertEqual(cloth.particles[1].position, Vector3(0.5, 0, 0))
        XCTAssertEqual((cloth.particles[2].position -
                        cloth.particles[0].position).length,
                       1,
                       accuracy: 2.0e-4)
        XCTAssertEqual((cloth.particles[3].position -
                        cloth.particles[1].position).length,
                       1,
                       accuracy: 2.0e-4)
        XCTAssertEqual((cloth.particles[3].position -
                        cloth.particles[0].position).length,
                       Scalar(2).squareRoot(),
                       accuracy: 3.0e-4)
    }

    func testSoftBodyPreservesTetrahedralVolumeUnderLoad() {
        let simulator = XPBDSimulator(gravity: Vector3(0, 0, -10))
        let softBody = SoftBody(
            particles: [
                XPBDParticle(position: .zero, inverseMass: 0),
                XPBDParticle(position: Vector3(1, 0, 0), inverseMass: 0),
                XPBDParticle(position: Vector3(0, 1, 0), inverseMass: 0),
                XPBDParticle(position: Vector3(0, 0, 1))
            ],
            tetrahedra: [XPBDParticleTetrahedron(0, 1, 2, 3)])
        XCTAssertTrue(simulator.add(softBody))
        for constraint in softBody.makeVolumeConstraints() {
            XCTAssertTrue(simulator.add(constraint))
        }

        step(simulator, count: 240, timeStep: 1.0 / 120.0)

        let volume = XPBDVolumeConstraint.signedVolume(
            softBody.particles[0].position,
            softBody.particles[1].position,
            softBody.particles[2].position,
            softBody.particles[3].position)
        XCTAssertEqual(volume, 1.0 / 6.0, accuracy: 1.0e-7)
        XCTAssertEqual(softBody.particles[3].position.z,
                       1,
                       accuracy: 1.0e-6)
    }

    func testParticleCollisionSettlesAbovePlane() {
        let simulator = XPBDSimulator()
        let body = RopeBody(particles: [
            XPBDParticle(position: Vector3(0, 1, 0))
        ])
        let plane = Collider(primitive: StaticPlane(
            Plane(normal: Vector3(0, 1, 0), point: .zero)))
        let collision = XPBDParticleCollisionConstraint(
            particle: XPBDParticleReference(body: body, particleIndex: 0),
            collider: plane,
            particleRadius: 0.1)
        XCTAssertTrue(simulator.add(body))
        XCTAssertTrue(simulator.add(collision))

        step(simulator, count: 240, timeStep: 1.0 / 120.0)

        XCTAssertEqual(body.particles[0].position.y, 0.1, accuracy: 1.0e-6)
        XCTAssertLessThan(abs(body.particles[0].velocity.y), 1.0e-6)
    }

    private func sphereBody(position: Vector3) -> RigidBody {
        RigidBody(
            primitive: Sphere(center: .zero, radius: 0.5),
            transform: Transform(position: position),
            material: PhysicsMaterial(friction: 0.5, restitution: 0))
    }

    private func step(_ simulator: RigidBodySimulator,
                      count: Int,
                      timeStep: Scalar) {
        for _ in 0..<count { simulator.step(timeStep: timeStep) }
    }

    private func step(_ simulator: XPBDSimulator,
                      count: Int,
                      timeStep: Scalar) {
        for _ in 0..<count { simulator.step(timeStep: timeStep) }
    }
}
