import XCTest
import VVD

final class XPBDBendingConstraintTests: XCTestCase {
    func testBendingConstraintUsesDistanceProjectionContract() throws {
        let body = RopeBody(particles: [
            XPBDParticle(position: .zero),
            XPBDParticle(position: Vector3(2, 0, 0))
        ])
        let constraint = XPBDBendingConstraint(
            particleA: XPBDParticleReference(body: body, particleIndex: 0),
            particleB: XPBDParticleReference(body: body, particleIndex: 1),
            restLength: 1,
            compliance: 0.2)

        let projection = try XCTUnwrap(constraint.projections().first)

        XCTAssertEqual(projection.value, 1)
        XCTAssertEqual(projection.compliance, 0.2)
        XCTAssertEqual(projection.gradients.map(\.gradient), [
            Vector3(-1, 0, 0), Vector3(1, 0, 0)
        ])
    }

    func testRopeBuildsBendingPairsAcrossSharedVertices() {
        let rope = RopeBody(particles: [
            XPBDParticle(position: Vector3(0, 0, 0)),
            XPBDParticle(position: Vector3(1, 0, 0)),
            XPBDParticle(position: Vector3(2, 0, 0)),
            XPBDParticle(position: Vector3(3, 0, 0))
        ])

        let constraints = rope.makeBendingConstraints(compliance: 0.3)
        let edges = constraints.map {
            XPBDParticleEdge($0.particleA.particleIndex,
                             $0.particleB.particleIndex)
        }

        XCTAssertEqual(edges, [XPBDParticleEdge(0, 2),
                               XPBDParticleEdge(1, 3)])
        XCTAssertEqual(constraints.map(\.restLength), [2, 2])
        XCTAssertTrue(constraints.allSatisfy { $0.compliance == 0.3 })
    }

    func testRopeBranchBuildsEveryNeighborPair() {
        let rope = RopeBody(
            particles: [XPBDParticle(), XPBDParticle(),
                        XPBDParticle(), XPBDParticle()],
            segments: [XPBDParticleEdge(0, 1),
                       XPBDParticleEdge(0, 2),
                       XPBDParticleEdge(0, 3)])

        let edges = rope.makeBendingConstraints().map {
            XPBDParticleEdge($0.particleA.particleIndex,
                             $0.particleB.particleIndex)
        }

        XCTAssertEqual(edges, [XPBDParticleEdge(1, 2),
                               XPBDParticleEdge(1, 3),
                               XPBDParticleEdge(2, 3)])
    }

    func testClothBuildsBendingPairAcrossInteriorEdge() {
        let cloth = ClothBody(
            particles: [
                XPBDParticle(position: Vector3(0, 0, 0)),
                XPBDParticle(position: Vector3(1, 0, 0)),
                XPBDParticle(position: Vector3(1, 1, 0)),
                XPBDParticle(position: Vector3(0, 1, 0))
            ],
            triangles: [XPBDParticleTriangle(0, 1, 2),
                        XPBDParticleTriangle(0, 2, 3)])

        let constraints = cloth.makeBendingConstraints()

        XCTAssertEqual(constraints.count, 1)
        XCTAssertEqual(XPBDParticleEdge(
            constraints[0].particleA.particleIndex,
            constraints[0].particleB.particleIndex),
            XPBDParticleEdge(1, 3))
        XCTAssertEqual(constraints[0].restLength,
                       sqrt(2),
                       accuracy: 1.0e-9)
    }

    func testClothSkipsBoundaryAndNonmanifoldBendingEdges() {
        let cloth = ClothBody(
            particles: Array(repeating: XPBDParticle(), count: 5),
            triangles: [XPBDParticleTriangle(0, 1, 2),
                        XPBDParticleTriangle(1, 0, 3),
                        XPBDParticleTriangle(0, 1, 4)])

        XCTAssertTrue(cloth.makeBendingConstraints().isEmpty)
    }

    func testBendingConstraintParticipatesInProjectionSolver() {
        let rope = RopeBody(particles: [
            XPBDParticle(position: .zero, inverseMass: 0),
            XPBDParticle(position: Vector3(2, 0, 0), inverseMass: 1)
        ])
        let constraint = XPBDBendingConstraint(
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
