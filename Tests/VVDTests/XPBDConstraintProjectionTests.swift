import XCTest
import VVD

final class XPBDConstraintProjectionTests: XCTestCase {
    func testParticleReferenceUsesBodyIdentityAndCurrentStorage() throws {
        let body = RopeBody(particles: [
            XPBDParticle(position: Vector3(1, 2, 3))
        ])
        let reference = XPBDParticleReference(body: body, particleIndex: 0)
        let equalReference = XPBDParticleReference(body: body, particleIndex: 0)
        let invalidReference = XPBDParticleReference(body: body, particleIndex: 1)

        XCTAssertEqual(reference, equalReference)
        XCTAssertTrue(reference.isValid)
        XCTAssertFalse(invalidReference.isValid)
        XCTAssertEqual(try XCTUnwrap(reference.particle).position,
                       Vector3(1, 2, 3))

        body.particles[0].position = Vector3(4, 5, 6)
        XCTAssertEqual(try XCTUnwrap(reference.particle).position,
                       Vector3(4, 5, 6))
    }

    func testFixedJointBuildsThreeScalarProjectionsAndOwnsMultipliers() {
        let body = RopeBody(particles: [
            XPBDParticle(position: Vector3(1, 2, 3))
        ])
        let reference = XPBDParticleReference(body: body, particleIndex: 0)
        let constraint = XPBDFixedJointConstraint(
            particleA: reference,
            worldAnchor: .zero,
            compliance: 0.25)

        let projections = constraint.projections()

        XCTAssertEqual(projections.map(\.multiplierIndex), [0, 1, 2])
        XCTAssertEqual(projections.map(\.value), [-1, -2, -3])
        XCTAssertTrue(projections.allSatisfy { $0.compliance == 0.25 })
        XCTAssertEqual(projections[0].gradients,
                       [XPBDConstraintGradient(
                            particle: reference,
                            gradient: Vector3(-1, 0, 0))])

        constraint.setAccumulatedMultiplier(2, at: 1)
        XCTAssertEqual(constraint.accumulatedMultipliers, Vector3(0, 2, 0))
        XCTAssertEqual(constraint.projections()[1].accumulatedMultiplier, 2)
        constraint.resetAccumulatedMultipliers()
        XCTAssertEqual(constraint.accumulatedMultipliers, .zero)
    }

    func testFixedJointCapturesPairRestOffsetByDefault() {
        let bodyA = RopeBody(particles: [
            XPBDParticle(position: Vector3(1, 0, 0))
        ])
        let bodyB = ClothBody(particles: [
            XPBDParticle(position: Vector3(3, 0, 0))
        ])
        let referenceA = XPBDParticleReference(body: bodyA, particleIndex: 0)
        let referenceB = XPBDParticleReference(body: bodyB, particleIndex: 0)
        let constraint = XPBDFixedJointConstraint(
            particleA: referenceA,
            particleB: referenceB)

        XCTAssertEqual(constraint.restOffset, Vector3(2, 0, 0))
        XCTAssertEqual(constraint.projections().map(\.value), [0, 0, 0])
        XCTAssertEqual(constraint.projections()[0].gradients.count, 2)
    }

    func testConfigurableJointBuildsLockedAndViolatedLimitProjections() {
        let body = RopeBody(particles: [XPBDParticle(position: .zero)])
        let reference = XPBDParticleReference(body: body, particleIndex: 0)
        let constraint = XPBDConfigurableJointConstraint(
            particleA: reference,
            worldAnchor: Vector3(2, -2, 0.5),
            restOffset: .zero,
            xAxis: .limited(-1, 1, compliance: 0.1),
            yAxis: .limited(-1, 1, compliance: 0.2),
            zAxis: .locked)

        let projections = constraint.projections()

        XCTAssertEqual(projections.map(\.multiplierIndex), [0, 1, 2])
        XCTAssertEqual(projections.map(\.value), [1, -1, 0.5])
        XCTAssertEqual(projections[0].lowerMultiplier, -.infinity)
        XCTAssertEqual(projections[0].upperMultiplier, 0)
        XCTAssertEqual(projections[1].lowerMultiplier, 0)
        XCTAssertEqual(projections[1].upperMultiplier, .infinity)
        XCTAssertEqual(projections[2].lowerMultiplier, -.infinity)
        XCTAssertEqual(projections[2].upperMultiplier, .infinity)
        XCTAssertEqual(projections.map(\.compliance), [0.1, 0.2, 0])
    }

    func testGearJointBuildsRatioGradientAndTargetError() throws {
        let bodyA = RopeBody(particles: [
            XPBDParticle(position: Vector3(1, 0, 0))
        ])
        let bodyB = SoftBody(particles: [
            XPBDParticle(position: Vector3(0, 2, 0))
        ])
        let referenceA = XPBDParticleReference(body: bodyA, particleIndex: 0)
        let referenceB = XPBDParticleReference(body: bodyB, particleIndex: 0)
        let constraint = XPBDGearJointConstraint(
            particleA: referenceA,
            particleB: referenceB,
            axisA: Vector3(1, 0, 0),
            axisB: Vector3(0, 1, 0),
            ratio: 2,
            targetCoordinate: 0,
            compliance: 0.5)

        let projection = try XCTUnwrap(constraint.projections().first)

        XCTAssertEqual(projection.value, 5)
        XCTAssertEqual(projection.compliance, 0.5)
        XCTAssertEqual(projection.gradients, [
            XPBDConstraintGradient(particle: referenceA,
                                   gradient: Vector3(1, 0, 0)),
            XPBDConstraintGradient(particle: referenceB,
                                   gradient: Vector3(0, 2, 0))
        ])

        constraint.setAccumulatedMultiplier(-3, at: 0)
        XCTAssertEqual(constraint.accumulatedMultiplier, -3)
        constraint.resetAccumulatedMultipliers()
        XCTAssertEqual(constraint.accumulatedMultiplier, 0)
    }

    func testSimulatorValidatesConstraintOwnershipAndRemovesOwnedConstraints() {
        let body = RopeBody(particles: [XPBDParticle()])
        let reference = XPBDParticleReference(body: body, particleIndex: 0)
        let constraint = XPBDFixedJointConstraint(particleA: reference)
        let simulator = XPBDSimulator()

        XCTAssertFalse(simulator.add(constraint))
        XCTAssertTrue(simulator.add(body))
        XCTAssertTrue(simulator.add(constraint))
        XCTAssertEqual(simulator.constraints.count, 1)
        XCTAssertTrue(simulator.remove(body))
        XCTAssertTrue(simulator.constraints.isEmpty)
    }
}
