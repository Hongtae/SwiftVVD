import XCTest
import VVD

final class XPBDDistanceConstraintTests: XCTestCase {
    func testParticleTopologyCanonicalizesEdgesAndValidatesTriangles() {
        XCTAssertEqual(XPBDParticleEdge(3, 1), XPBDParticleEdge(1, 3))
        XCTAssertTrue(XPBDParticleEdge(0, 2).isValid(particleCount: 3))
        XCTAssertFalse(XPBDParticleEdge(1, 1).isValid(particleCount: 3))
        XCTAssertFalse(XPBDParticleEdge(-1, 1).isValid(particleCount: 3))

        let triangle = XPBDParticleTriangle(0, 1, 2)
        XCTAssertTrue(triangle.isValid(particleCount: 3))
        XCTAssertEqual(Set(triangle.edges), [
            XPBDParticleEdge(0, 1),
            XPBDParticleEdge(1, 2),
            XPBDParticleEdge(0, 2)
        ])
        XCTAssertFalse(XPBDParticleTriangle(0, 0, 2)
            .isValid(particleCount: 3))
    }

    func testDistanceConstraintCapturesRestLengthAndBuildsGradients() throws {
        let body = RopeBody(particles: [
            XPBDParticle(position: .zero),
            XPBDParticle(position: Vector3(2, 0, 0))
        ])
        let constraint = XPBDDistanceConstraint(
            particleA: XPBDParticleReference(body: body, particleIndex: 0),
            particleB: XPBDParticleReference(body: body, particleIndex: 1),
            compliance: 0.25)

        XCTAssertEqual(constraint.restLength, 2)
        body.particles[1].position.x = 3
        let projection = try XCTUnwrap(constraint.projections().first)

        XCTAssertEqual(projection.value, 1)
        XCTAssertEqual(projection.compliance, 0.25)
        XCTAssertEqual(projection.gradients.map(\.gradient), [
            Vector3(-1, 0, 0), Vector3(1, 0, 0)
        ])
    }

    func testDistanceConstraintSeparatesCoincidentParticles() {
        let body = RopeBody(particles: [XPBDParticle(), XPBDParticle()])
        let constraint = XPBDDistanceConstraint(
            particleA: XPBDParticleReference(body: body, particleIndex: 0),
            particleB: XPBDParticleReference(body: body, particleIndex: 1),
            restLength: 2)

        XPBDProjectionSolver(projectionIterations: 1).solve(
            XPBDSolverContext(timeStep: 0.1,
                              gravity: .zero,
                              bodies: [body],
                              constraints: [constraint]))

        XCTAssertEqual(body.particles[0].position.x, -1, accuracy: 1.0e-9)
        XCTAssertEqual(body.particles[1].position.x, 1, accuracy: 1.0e-9)
    }

    func testRopeBuildsDistanceConstraintsFromSegments() {
        let rope = RopeBody(particles: [
            XPBDParticle(position: .zero),
            XPBDParticle(position: Vector3(1, 0, 0)),
            XPBDParticle(position: Vector3(3, 0, 0))
        ])

        let constraints = rope.makeDistanceConstraints(compliance: 0.1)

        XCTAssertEqual(rope.segments, [
            XPBDParticleEdge(0, 1), XPBDParticleEdge(1, 2)
        ])
        XCTAssertEqual(constraints.map(\.restLength), [1, 2])
        XCTAssertTrue(constraints.allSatisfy { $0.compliance == 0.1 })
    }

    func testClothBuildsOneDistanceConstraintPerUniqueTriangleEdge() {
        let cloth = ClothBody(
            particles: [
                XPBDParticle(position: Vector3(0, 0, 0)),
                XPBDParticle(position: Vector3(1, 0, 0)),
                XPBDParticle(position: Vector3(1, 1, 0)),
                XPBDParticle(position: Vector3(0, 1, 0))
            ],
            triangles: [
                XPBDParticleTriangle(0, 1, 2),
                XPBDParticleTriangle(0, 2, 3),
                XPBDParticleTriangle(0, 9, 3)
            ])

        let constraints = cloth.makeDistanceConstraints()
        let edges = constraints.map {
            XPBDParticleEdge($0.particleA.particleIndex,
                             $0.particleB.particleIndex)
        }

        XCTAssertEqual(edges, [
            XPBDParticleEdge(0, 1),
            XPBDParticleEdge(0, 2),
            XPBDParticleEdge(0, 3),
            XPBDParticleEdge(1, 2),
            XPBDParticleEdge(2, 3)
        ])
    }

    func testPinnedRopeEndpointConstrainsDynamicParticle() {
        let rope = RopeBody(particles: [
            XPBDParticle(position: .zero, inverseMass: 0),
            XPBDParticle(position: Vector3(2, 0, 0), inverseMass: 1)
        ])
        let constraint = XPBDDistanceConstraint(
            particleA: XPBDParticleReference(body: rope, particleIndex: 0),
            particleB: XPBDParticleReference(body: rope, particleIndex: 1),
            restLength: 1)

        XPBDProjectionSolver(projectionIterations: 1).solve(
            XPBDSolverContext(timeStep: 0.1,
                              gravity: .zero,
                              bodies: [rope],
                              constraints: [constraint]))

        XCTAssertEqual(rope.particles[0].position, .zero)
        XCTAssertEqual(rope.particles[1].position.x, 1, accuracy: 1.0e-9)
    }
}
