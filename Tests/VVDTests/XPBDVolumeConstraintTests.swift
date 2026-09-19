import XCTest
import VVD

final class XPBDVolumeConstraintTests: XCTestCase {
    func testTetrahedronTopologyRequiresFourDistinctValidIndices() {
        XCTAssertTrue(XPBDParticleTetrahedron(0, 1, 2, 3)
            .isValid(particleCount: 4))
        XCTAssertFalse(XPBDParticleTetrahedron(0, 1, 2, 2)
            .isValid(particleCount: 4))
        XCTAssertFalse(XPBDParticleTetrahedron(0, 1, 2, 4)
            .isValid(particleCount: 4))
        XCTAssertFalse(XPBDParticleTetrahedron(-1, 1, 2, 3)
            .isValid(particleCount: 4))
    }

    func testVolumeConstraintCapturesSignedVolumeAndBuildsGradients() throws {
        let body = makeUnitTetrahedron()
        let references = (0..<4).map {
            XPBDParticleReference(body: body, particleIndex: $0)
        }
        let constraint = XPBDVolumeConstraint(
            particleA: references[0],
            particleB: references[1],
            particleC: references[2],
            particleD: references[3],
            compliance: 0.25)

        XCTAssertEqual(constraint.restVolume, 1.0 / 6.0, accuracy: 1.0e-9)
        body.particles[3].position.z = 2
        let projection = try XCTUnwrap(constraint.projections().first)

        XCTAssertEqual(projection.value, 1.0 / 6.0, accuracy: 1.0e-9)
        XCTAssertEqual(projection.compliance, 0.25)
        XCTAssertEqual(projection.gradients[0].gradient.x,
                       -1.0 / 3.0,
                       accuracy: 1.0e-9)
        XCTAssertEqual(projection.gradients[0].gradient.y,
                       -1.0 / 3.0,
                       accuracy: 1.0e-9)
        XCTAssertEqual(projection.gradients[0].gradient.z,
                       -1.0 / 6.0,
                       accuracy: 1.0e-9)
        XCTAssertEqual(projection.gradients[1].gradient,
                       Vector3(1.0 / 3.0, 0, 0))
        XCTAssertEqual(projection.gradients[2].gradient,
                       Vector3(0, 1.0 / 3.0, 0))
        XCTAssertEqual(projection.gradients[3].gradient,
                       Vector3(0, 0, 1.0 / 6.0))
    }

    func testVolumeConstraintRestoresExpandedTetrahedron() {
        let body = makeUnitTetrahedron(pinBase: true)
        let constraint = makeConstraint(body)
        body.particles[3].position.z = 2

        XPBDProjectionSolver(projectionIterations: 1).solve(
            XPBDSolverContext(timeStep: 0.1,
                              gravity: .zero,
                              bodies: [body],
                              constraints: [constraint]))

        XCTAssertEqual(body.particles[3].position.z, 1, accuracy: 1.0e-9)
        XCTAssertEqual(XPBDVolumeConstraint.signedVolume(
            body.particles[0].position,
            body.particles[1].position,
            body.particles[2].position,
            body.particles[3].position),
            1.0 / 6.0,
            accuracy: 1.0e-9)
    }

    func testSignedVolumeConstraintRepairsInversion() {
        let body = makeUnitTetrahedron(pinBase: true)
        let constraint = makeConstraint(body)
        body.particles[3].position.z = -1

        XPBDProjectionSolver(projectionIterations: 1).solve(
            XPBDSolverContext(timeStep: 0.1,
                              gravity: .zero,
                              bodies: [body],
                              constraints: [constraint]))

        XCTAssertEqual(body.particles[3].position.z, 1, accuracy: 1.0e-9)
    }

    func testSoftBodyBuildsConstraintsForValidTetrahedraOnly() {
        let body = SoftBody(
            particles: makeUnitTetrahedron().particles,
            tetrahedra: [XPBDParticleTetrahedron(0, 1, 2, 3),
                         XPBDParticleTetrahedron(0, 1, 1, 3),
                         XPBDParticleTetrahedron(0, 1, 2, 9)])

        let constraints = body.makeVolumeConstraints(compliance: 0.4)

        XCTAssertEqual(constraints.count, 1)
        XCTAssertEqual(constraints[0].restVolume,
                       1.0 / 6.0,
                       accuracy: 1.0e-9)
        XCTAssertEqual(constraints[0].compliance, 0.4)
        XCTAssertEqual(constraints[0].particleReferences.map(\.particleIndex),
                       [0, 1, 2, 3])
    }

    private func makeUnitTetrahedron(pinBase: Bool = false) -> SoftBody {
        let baseInverseMass: Scalar = pinBase ? 0 : 1
        return SoftBody(particles: [
            XPBDParticle(position: .zero, inverseMass: baseInverseMass),
            XPBDParticle(position: Vector3(1, 0, 0),
                         inverseMass: baseInverseMass),
            XPBDParticle(position: Vector3(0, 1, 0),
                         inverseMass: baseInverseMass),
            XPBDParticle(position: Vector3(0, 0, 1), inverseMass: 1)
        ])
    }

    private func makeConstraint(_ body: SoftBody) -> XPBDVolumeConstraint {
        XPBDVolumeConstraint(
            particleA: XPBDParticleReference(body: body, particleIndex: 0),
            particleB: XPBDParticleReference(body: body, particleIndex: 1),
            particleC: XPBDParticleReference(body: body, particleIndex: 2),
            particleD: XPBDParticleReference(body: body, particleIndex: 3))
    }
}
