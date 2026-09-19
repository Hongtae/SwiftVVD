import XCTest
import VVD

final class XPBDProjectionSolverTests: XCTestCase {
    func testPredictsDynamicParticlesAndKeepsPinnedParticlesFixed() {
        let body = RopeBody(particles: [
            XPBDParticle(position: .zero,
                         velocity: Vector3(2, 0, 0),
                         inverseMass: 1),
            XPBDParticle(position: Vector3(1, 0, 0),
                         velocity: Vector3(5, 0, 0),
                         inverseMass: 0)
        ])
        let solver = XPBDProjectionSolver(projectionIterations: 0)

        solver.solve(XPBDSolverContext(
            timeStep: 0.5,
            gravity: Vector3(0, -10, 0),
            bodies: [body],
            constraints: []))

        XCTAssertEqual(body.particles[0].previousPosition, .zero)
        XCTAssertEqual(body.particles[0].position, Vector3(1, -2.5, 0))
        XCTAssertEqual(body.particles[0].velocity, Vector3(2, -5, 0))
        XCTAssertEqual(body.particles[1].previousPosition, Vector3(1, 0, 0))
        XCTAssertEqual(body.particles[1].position, Vector3(1, 0, 0))
        XCTAssertEqual(body.particles[1].velocity, .zero)
    }

    func testFixedConstraintProjectsToWorldAnchorAndUpdatesVelocity() {
        let body = RopeBody(particles: [
            XPBDParticle(position: Vector3(1, 2, 3))
        ])
        let constraint = XPBDFixedJointConstraint(
            particleA: XPBDParticleReference(body: body, particleIndex: 0),
            worldAnchor: .zero)
        let solver = XPBDProjectionSolver(projectionIterations: 1)

        solver.solve(XPBDSolverContext(
            timeStep: 0.5,
            gravity: .zero,
            bodies: [body],
            constraints: [constraint]))

        XCTAssertEqual(body.particles[0].position, .zero)
        XCTAssertEqual(body.particles[0].velocity, Vector3(-2, -4, -6))
        XCTAssertEqual(constraint.accumulatedMultipliers,
                       Vector3(1, 2, 3))
    }

    func testComplianceUsesTimeScaledAccumulatedMultiplier() {
        let body = RopeBody(particles: [
            XPBDParticle(position: Vector3(1, 0, 0))
        ])
        let constraint = XPBDFixedJointConstraint(
            particleA: XPBDParticleReference(body: body, particleIndex: 0),
            worldAnchor: .zero,
            compliance: 0.25)

        XPBDProjectionSolver().solve(XPBDSolverContext(
            timeStep: 0.5,
            gravity: .zero,
            bodies: [body],
            constraints: [constraint]))

        XCTAssertEqual(body.particles[0].position.x, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(body.particles[0].velocity.x, -1, accuracy: 1.0e-9)
        XCTAssertEqual(constraint.accumulatedMultipliers.x,
                       0.5,
                       accuracy: 1.0e-9)
    }

    func testPairConstraintDistributesCorrectionByInverseMass() {
        let bodyA = RopeBody(particles: [
            XPBDParticle(position: .zero, inverseMass: 1)
        ])
        let bodyB = RopeBody(particles: [
            XPBDParticle(position: Vector3(2, 0, 0), inverseMass: 3)
        ])
        let constraint = XPBDFixedJointConstraint(
            particleA: XPBDParticleReference(body: bodyA, particleIndex: 0),
            particleB: XPBDParticleReference(body: bodyB, particleIndex: 0),
            restOffset: .zero)

        XPBDProjectionSolver(projectionIterations: 1).solve(
            XPBDSolverContext(timeStep: 0.1,
                              gravity: .zero,
                              bodies: [bodyA, bodyB],
                              constraints: [constraint]))

        XCTAssertEqual(bodyA.particles[0].position.x, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(bodyB.particles[0].position.x, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(constraint.accumulatedMultipliers.x,
                       -0.5,
                       accuracy: 1.0e-9)
    }

    func testConfigurableUpperLimitUsesUnilateralMultiplier() {
        let body = RopeBody(particles: [XPBDParticle(position: .zero)])
        let constraint = XPBDConfigurableJointConstraint(
            particleA: XPBDParticleReference(body: body, particleIndex: 0),
            worldAnchor: Vector3(2, 0, 0),
            restOffset: .zero,
            xAxis: .limited(-1, 1))

        XPBDProjectionSolver(projectionIterations: 2).solve(
            XPBDSolverContext(timeStep: 0.1,
                              gravity: .zero,
                              bodies: [body],
                              constraints: [constraint]))

        XCTAssertEqual(body.particles[0].position.x, 1, accuracy: 1.0e-9)
        XCTAssertEqual(constraint.accumulatedMultipliers.x,
                       -1,
                       accuracy: 1.0e-9)
    }

    func testGearConstraintProjectsRatioWeightedCoordinates() {
        let bodyA = RopeBody(particles: [
            XPBDParticle(position: Vector3(1, 0, 0))
        ])
        let bodyB = RopeBody(particles: [
            XPBDParticle(position: Vector3(0, 2, 0))
        ])
        let constraint = XPBDGearJointConstraint(
            particleA: XPBDParticleReference(body: bodyA, particleIndex: 0),
            particleB: XPBDParticleReference(body: bodyB, particleIndex: 0),
            axisA: Vector3(1, 0, 0),
            axisB: Vector3(0, 1, 0),
            ratio: 2,
            targetCoordinate: 0)

        XPBDProjectionSolver(projectionIterations: 1).solve(
            XPBDSolverContext(timeStep: 0.1,
                              gravity: .zero,
                              bodies: [bodyA, bodyB],
                              constraints: [constraint]))

        XCTAssertEqual(bodyA.particles[0].position.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(bodyB.particles[0].position.y, 0, accuracy: 1.0e-9)
        XCTAssertEqual(constraint.accumulatedMultiplier, -1, accuracy: 1.0e-9)
    }

    func testDuplicateParticleGradientsAreCombinedBeforeEffectiveMass() {
        let body = RopeBody(particles: [
            XPBDParticle(position: Vector3(1, 0, 0))
        ])
        let reference = XPBDParticleReference(body: body, particleIndex: 0)
        let constraint = CancellingGradientConstraint(reference: reference)

        XPBDProjectionSolver(projectionIterations: 1).solve(
            XPBDSolverContext(timeStep: 0.1,
                              gravity: .zero,
                              bodies: [body],
                              constraints: [constraint]))

        XCTAssertEqual(body.particles[0].position, Vector3(1, 0, 0))
        XCTAssertEqual(constraint.multiplier, 0)
    }
}

private final class CancellingGradientConstraint: XPBDConstraint {
    let reference: XPBDParticleReference
    var isEnabled = true
    var multiplier: Scalar = 0

    var particleReferences: [XPBDParticleReference] { [reference] }

    init(reference: XPBDParticleReference) {
        self.reference = reference
    }

    func resetAccumulatedMultipliers() {
        multiplier = 0
    }

    func projections() -> [XPBDConstraintProjection] {
        [XPBDConstraintProjection(
            multiplierIndex: 0,
            value: 1,
            gradients: [
                XPBDConstraintGradient(particle: reference,
                                       gradient: Vector3(1, 0, 0)),
                XPBDConstraintGradient(particle: reference,
                                       gradient: Vector3(-1, 0, 0))
            ],
            accumulatedMultiplier: multiplier)]
    }

    func setAccumulatedMultiplier(_ multiplier: Scalar, at index: Int) {
        guard index == 0 else { return }
        self.multiplier = multiplier
    }
}
