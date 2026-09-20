import XCTest
import VVD

final class XPBDCollisionConstraintTests: XCTestCase {
    func testClosedPrimitiveProjectsContainedParticleOutward() throws {
        let body = RopeBody(particles: [XPBDParticle(position: .zero)])
        let collider = Collider(primitive: Sphere(center: .zero, radius: 1))
        let constraint = XPBDParticleCollisionConstraint(
            particle: reference(to: body),
            collider: collider,
            particleRadius: 0.25)

        let projection = try XCTUnwrap(constraint.projections().first)

        XCTAssertEqual(projection.value, -1.25)
        XCTAssertEqual(projection.gradients.first?.gradient, Vector3(1, 0, 0))
        XCTAssertEqual(projection.lowerMultiplier, 0)
        XCTAssertEqual(projection.upperMultiplier, .infinity)

        solve(body, constraint)

        XCTAssertEqual(body.particles[0].position, Vector3(1.25, 0, 0))
        XCTAssertEqual(constraint.accumulatedMultiplier, 1.25)
    }

    func testParticleRadiusMaintainsClearanceOutsideClosedPrimitive() {
        let body = RopeBody(particles: [
            XPBDParticle(position: Vector3(1.1, 0, 0))
        ])
        let collider = Collider(primitive: Sphere(center: .zero, radius: 1))
        let constraint = XPBDParticleCollisionConstraint(
            particle: reference(to: body),
            collider: collider,
            particleRadius: 0.25)

        solve(body, constraint)

        XCTAssertEqual(body.particles[0].position.x, 1.25, accuracy: 1.0e-9)
        XCTAssertEqual(body.particles[0].position.y, 0, accuracy: 1.0e-9)
    }

    func testOpenPlaneCollisionIsTwoSided() {
        let plane = Collider(primitive: StaticPlane(
            Plane(normal: Vector3(0, 1, 0), point: .zero)))
        let bodyAbove = RopeBody(particles: [
            XPBDParticle(position: Vector3(0, 0.1, 0))
        ])
        let bodyBelow = RopeBody(particles: [
            XPBDParticle(position: Vector3(0, -0.1, 0))
        ])
        let above = XPBDParticleCollisionConstraint(
            particle: reference(to: bodyAbove),
            collider: plane,
            particleRadius: 0.25)
        let below = XPBDParticleCollisionConstraint(
            particle: reference(to: bodyBelow),
            collider: plane,
            particleRadius: 0.25)

        solve(bodyAbove, above)
        solve(bodyBelow, below)

        XCTAssertEqual(bodyAbove.particles[0].position.y,
                       0.25,
                       accuracy: 1.0e-9)
        XCTAssertEqual(bodyBelow.particles[0].position.y,
                       -0.25,
                       accuracy: 1.0e-9)
    }

    func testColliderTransformConvertsCorrectionToWorldSpace() {
        let body = RopeBody(particles: [
            XPBDParticle(position: Vector3(2, 0, 0))
        ])
        let collider = Collider(
            primitive: Sphere(center: .zero, radius: 1),
            transform: Transform(position: Vector3(2, 0, 0)))
        let constraint = XPBDParticleCollisionConstraint(
            particle: reference(to: body),
            collider: collider)

        solve(body, constraint)

        XCTAssertEqual(body.particles[0].position, Vector3(3, 0, 0))
    }

    func testSeparatedOrUnavailableColliderProducesNoProjection() {
        let body = RopeBody(particles: [
            XPBDParticle(position: Vector3(4, 0, 0))
        ])
        let collider = Collider(primitive: Sphere(center: .zero, radius: 1))
        let constraint = XPBDParticleCollisionConstraint(
            particle: reference(to: body),
            collider: collider,
            particleRadius: 0.25)

        XCTAssertTrue(constraint.projections().isEmpty)
        collider.isEnabled = false
        body.particles[0].position = .zero
        XCTAssertTrue(constraint.projections().isEmpty)
    }

    func testContactMultiplierReleasesAfterAnotherConstraintSeparatesParticle() {
        let timeStep: Scalar = 1.0 / 60.0
        for compliance in [Scalar.zero, timeStep * timeStep] {
            for contactFirst in [true, false] {
                let body = RopeBody(particles: [
                    XPBDParticle(position: Vector3(0, -1, 0))
                ])
                let collider = Collider(
                    primitive: Box(halfExtents: Vector3(10, 5, 10)),
                    transform: Transform(position: Vector3(0, -5, 0)))
                let contact = XPBDParticleCollisionConstraint(
                    particle: reference(to: body),
                    collider: collider,
                    compliance: compliance)
                let joint = XPBDFixedJointConstraint(
                    particleA: reference(to: body),
                    worldAnchor: Vector3(0, 2, 0),
                    compliance: timeStep * timeStep)
                let simulator = XPBDSimulator(gravity: .zero)
                XCTAssertTrue(simulator.add(body))
                if contactFirst {
                    XCTAssertTrue(simulator.add(contact))
                    XCTAssertTrue(simulator.add(joint))
                } else {
                    XCTAssertTrue(simulator.add(joint))
                    XCTAssertTrue(simulator.add(contact))
                }

                simulator.step(timeStep: timeStep)

                // The spring's equilibrium is above the surface, where the
                // contact must contribute neither displacement nor velocity.
                let scenario = "compliance=\(compliance), contactFirst=\(contactFirst)"
                XCTAssertEqual(body.particles[0].position.y, 0.5,
                               accuracy: 1.0e-9, scenario)
                XCTAssertEqual(body.particles[0].velocity.y, 1.5 / timeStep,
                               accuracy: 1.0e-9, scenario)
                XCTAssertEqual(contact.accumulatedMultiplier, 0,
                               accuracy: 1.0e-9, scenario)
            }
        }
    }

    func testSurfaceContactRetainsItsSupportingMultiplierAcrossIterations() {
        let body = RopeBody(particles: [
            XPBDParticle(position: Vector3(0, 0.25, 0))
        ])
        let collider = Collider(primitive: StaticPlane(
            Plane(normal: Vector3(0, 1, 0), point: .zero)))
        let contact = XPBDParticleCollisionConstraint(
            particle: reference(to: body),
            collider: collider,
            particleRadius: 0.5)
        let simulator = XPBDSimulator(gravity: .zero)
        XCTAssertTrue(simulator.add(body))
        XCTAssertTrue(simulator.add(contact))

        simulator.step(timeStep: 0.1)

        XCTAssertEqual(body.particles[0].position.y, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(contact.accumulatedMultiplier, 0.25, accuracy: 1.0e-9)
    }

    func testBodyFactoryBuildsConstraintsForCurrentParticles() {
        let body = ClothBody(particles: [XPBDParticle(), XPBDParticle()])
        let collider = Collider(primitive: Box(halfExtents: Vector3(1, 1, 1)))

        let constraints = body.makeCollisionConstraints(
            against: collider,
            particleRadius: 0.2,
            compliance: 0.3)

        XCTAssertEqual(constraints.count, 2)
        XCTAssertEqual(constraints.map { $0.particle.particleIndex }, [0, 1])
        XCTAssertTrue(constraints.allSatisfy { $0.collider === collider })
        XCTAssertTrue(constraints.allSatisfy { $0.particleRadius == 0.2 })
        XCTAssertTrue(constraints.allSatisfy { $0.compliance == 0.3 })
    }

    private func reference(to body: any XPBDBody) -> XPBDParticleReference {
        XPBDParticleReference(body: body, particleIndex: 0)
    }

    private func solve(_ body: any XPBDBody,
                       _ constraint: any XPBDConstraint) {
        XPBDProjectionSolver(projectionIterations: 1).solve(
            XPBDSolverContext(timeStep: 0.1,
                              gravity: .zero,
                              bodies: [body],
                              constraints: [constraint]))
    }
}
