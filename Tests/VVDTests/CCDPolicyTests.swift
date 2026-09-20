import XCTest
import VVD

final class CCDPolicyTests: XCTestCase {
    private func body(_ x: Scalar, motion: RigidBodyMotionType = .dynamic,
                      restitution: Scalar = 0) -> RigidBody {
        let body = RigidBody(primitive: Sphere(center: .zero, radius: 0.5),
            transform: Transform(position: Vector3(x, 0, 0)), motionType: motion,
            material: PhysicsMaterial(friction: 0, restitution: restitution))
        body.isContinuousCollisionDetectionEnabled = motion == .dynamic
        return body
    }

    private func simulator(_ bodies: [RigidBody], configuration: CCDConfiguration)
        -> (RigidBodySimulator, SequentialImpulseRigidBodySolver) {
        let solver = SequentialImpulseRigidBodySolver(ccdConfiguration: configuration)
        let simulator = RigidBodySimulator(gravity: .zero, solver: solver)
        bodies.forEach { simulator.add($0) }
        return (simulator, solver)
    }

    func testPoliciesHaveDistinctDocumentedBehavior() {
        for mode in CCDConfiguration.Mode.allCases {
            let moving = body(0), wall = body(3, motion: .static)
            moving.linearVelocity = Vector3(10, 0, 0)
            let (simulator, solver) = simulator([moving, wall], configuration: .init(mode: mode))
            simulator.step(timeStep: 0.5)
            XCTAssertEqual(moving.transform.position.x, mode == .discrete ? 5 : 2,
                           accuracy: 1.0e-8, "\(mode)")
            let velocity: Scalar
            switch mode {
            case .discrete, .motionClamping: velocity = 10
            case .speculative, .hybrid: velocity = 4
            case .timeOfImpact: velocity = 0
            }
            XCTAssertEqual(moving.linearVelocity.x, velocity, accuracy: 1.0e-8, "\(mode)")
            if mode == .hybrid || mode == .speculative {
                XCTAssertEqual(solver.ccdStatistics.predictiveContactCount, 1)
            }
        }
        XCTAssertEqual(CCDConfiguration.default.mode, .hybrid)
    }

    func testJointSolvedVelocityControlsEveryCCDTrajectory() {
        for mode in CCDConfiguration.Mode.allCases {
            let moving = body(0), wall = body(3, motion: .static)
            moving.linearVelocity = Vector3(10, 0, 0)
            let (simulator, _) = simulator([moving, wall], configuration: .init(mode: mode))
            simulator.add(FixedJointConstraint(bodyA: moving))
            simulator.step(timeStep: 0.5)
            XCTAssertEqual(moving.transform.position.x, 0, accuracy: 1.0e-9, "\(mode)")
            XCTAssertEqual(moving.linearVelocity.x, 0, accuracy: 1.0e-9, "\(mode)")
        }
    }

    func testTOIResweepsAfterEachBounce() {
        let moving = body(0, restitution: 1)
        moving.linearVelocity = Vector3(20, 0, 0)
        let (simulator, solver) = simulator([moving, body(3, motion: .static, restitution: 1),
            body(-3, motion: .static, restitution: 1)], configuration: .init(mode: .timeOfImpact))
        simulator.step(timeStep: 0.45)
        XCTAssertEqual(moving.transform.position.x, 1, accuracy: 1.0e-8)
        XCTAssertEqual(moving.linearVelocity.x, 20, accuracy: 1.0e-8)
        XCTAssertEqual(solver.ccdStatistics.impactCount, 2)
        XCTAssertFalse(solver.ccdStatistics.reachedImpactLimit)
    }

    func testTOILimitClampsRemainingMotionAtNextObstacle() {
        let moving = body(0, restitution: 1)
        moving.linearVelocity = Vector3(20, 0, 0)
        let (simulator, solver) = simulator([moving, body(3, motion: .static, restitution: 1),
            body(-3, motion: .static, restitution: 1)],
            configuration: .init(mode: .timeOfImpact, maximumImpactIterations: 1))
        simulator.step(timeStep: 0.5)
        XCTAssertEqual(moving.transform.position.x, -2, accuracy: 1.0e-8)
        XCTAssertTrue(solver.ccdStatistics.reachedImpactLimit)
        XCTAssertEqual(solver.ccdStatistics.clampedBodyCount, 1)
    }

    func testClampingResweepsOtherBodiesAfterPartnerStops() {
        let leading = body(0), trailing = body(-3), wall = body(3, motion: .static)
        leading.linearVelocity = Vector3(10, 0, 0)
        trailing.linearVelocity = Vector3(10, 0, 0)
        let (simulator, _) = simulator([leading, trailing, wall], configuration: .init(mode: .motionClamping))
        simulator.step(timeStep: 1)
        XCTAssertEqual(leading.transform.position.x, 2, accuracy: 1.0e-8)
        XCTAssertEqual(trailing.transform.position.x, 1, accuracy: 1.0e-8)
    }

    func testTOIFollowsImpulseTransferredToBodyWithoutCCDFlag() {
        let moving = body(0, restitution: 1), target = body(3, restitution: 1)
        target.isContinuousCollisionDetectionEnabled = false
        moving.linearVelocity = Vector3(20, 0, 0)
        let (simulator, solver) = simulator([moving, target, body(6, motion: .static, restitution: 1)],
            configuration: .init(mode: .timeOfImpact))
        simulator.step(timeStep: 0.25)
        XCTAssertEqual(moving.transform.position.x, 2, accuracy: 1.0e-8)
        XCTAssertEqual(target.transform.position.x, 4, accuracy: 1.0e-8)
        XCTAssertEqual(target.linearVelocity.x, -20, accuracy: 1.0e-8)
        XCTAssertEqual(solver.ccdStatistics.impactCount, 2)
        XCTAssertFalse(target.isContinuousCollisionDetectionEnabled)
    }

    func testSubstepsPreserveForcesForFullOuterStep() {
        let moving = body(0)
        moving.addForce(Vector3(10, 0, 0))
        let (simulator, _) = simulator([moving], configuration: .init(substepCount: 4))
        simulator.step(timeStep: 1)
        XCTAssertEqual(moving.linearVelocity.x, 10, accuracy: 1.0e-9)
        XCTAssertEqual(moving.transform.position.x, 6.25, accuracy: 1.0e-9)
        XCTAssertEqual(moving.accumulatedForces, ForceAccumulator())
    }

    func testRotatingBarIsClampedBeforeCrossingObstacle() {
        let bar = RigidBody(primitive: Box(halfExtents: Vector3(2, 0.05, 0.05)))
        bar.isContinuousCollisionDetectionEnabled = true
        bar.angularVelocity = Vector3(0, 0, .pi)
        let obstacle = RigidBody(primitive: Sphere(center: .zero, radius: 0.1),
            transform: Transform(position: Vector3(0, 1.5, 0)), motionType: .static)
        let (simulator, solver) = simulator([bar, obstacle],
            configuration: .init(mode: .motionClamping, motion: .translationAndRotation))
        simulator.step(timeStep: 1)
        let tip = Vector3(2, 0, 0).applying(bar.transform)
        XCTAssertGreaterThan(tip.x, 0)
        XCTAssertGreaterThan(tip.y, 1.5)
        XCTAssertEqual(solver.ccdStatistics.clampedBodyCount, 1)
    }

    func testInconclusiveSweepCannotAdvanceUnchecked() {
        let moving = RigidBody(primitive: Box(halfExtents: Vector3(0.5, 0.5, 0.5)))
        moving.isContinuousCollisionDetectionEnabled = true
        moving.linearVelocity = Vector3(10, 0, 0)
        let (simulator, solver) = simulator([moving, body(3, motion: .static)],
            configuration: .init(mode: .timeOfImpact, maximumSweepIterations: 0))
        simulator.step(timeStep: 1)
        XCTAssertEqual(moving.transform.position.x, 0)
        XCTAssertEqual(solver.ccdStatistics.inconclusiveSweepCount, 1)
        XCTAssertEqual(solver.ccdStatistics.clampedBodyCount, 1)
    }

    func testUnsupportedPairReportsDiagnosticAndStopsMotion() {
        let moving = body(0)
        moving.linearVelocity = Vector3(10, 0, 0)
        let (simulator, solver) = simulator([moving, body(3, motion: .static)],
                                            configuration: .init(mode: .hybrid))
        simulator.collisionSpace.algorithms = CollisionAlgorithmRegistry(usesBuiltinFallback: false)
        simulator.step(timeStep: 1)
        XCTAssertEqual(moving.transform.position.x, 0)
        XCTAssertGreaterThan(solver.ccdStatistics.unsupportedPairCount, 0)
        XCTAssertEqual(solver.ccdStatistics.clampedBodyCount, 1)
    }

    func testTOIPropagatesNumericalClampingWithoutRepeatedStaleVelocityImpulses() {
        let leading = body(0), trailing = body(-3)
        leading.linearVelocity = Vector3(4, 0, 0)
        trailing.linearVelocity = Vector3(10, 0, 0)
        trailing.collider.filter = CollisionFilter(group: .bit(1))
        let wall = RigidBody(primitive: Box(halfExtents: Vector3(0.5, 0.5, 0.5)),
                            transform: Transform(position: Vector3(1.5, 0, 0)), motionType: .static)
        wall.collider.filter = CollisionFilter(mask: CollisionMask(.bit(0)))
        let (simulator, solver) = simulator([leading, trailing, wall],
            configuration: .init(mode: .timeOfImpact, maximumImpactIterations: 4))
        var registry = CollisionAlgorithmRegistry(usesBuiltinFallback: false)
        registry.registerSweep(Sphere.self, Sphere.self) { a, b, frame, translation in
            CollisionAlgorithms.timeOfImpact(a, b, frame: frame, translation: translation)
        }
        simulator.collisionSpace.algorithms = registry
        simulator.step(timeStep: 1)
        XCTAssertEqual(leading.transform.position.x, 0)
        XCTAssertEqual(trailing.transform.position.x, -1, accuracy: 1.0e-8)
        XCTAssertEqual(solver.ccdStatistics.impactCount, 0)
        XCTAssertEqual(solver.ccdStatistics.clampedBodyCount, 2)
        XCTAssertFalse(solver.ccdStatistics.reachedImpactLimit)
    }

    func testMotionClampingStopsKinematicPartnerPoseButKeepsItsVelocity() {
        let stationary = body(0), kinematic = body(-3, motion: .kinematic)
        kinematic.linearVelocity = Vector3(12, 0, 0)
        let (simulator, _) = simulator([stationary, kinematic], configuration: .init(mode: .motionClamping))
        simulator.step(timeStep: 0.5)
        XCTAssertEqual(stationary.transform.position.x, 0)
        XCTAssertEqual(kinematic.transform.position.x, -1, accuracy: 1.0e-8)
        XCTAssertEqual(kinematic.linearVelocity.x, 12)
    }

    func testSpeculationAloneDoesNotGuaranteeMotionRedirectedByOtherContacts() {
        // The plane's predictive contact changes this sphere's diagonal path.
        // Hybrid must re-sweep the solved path against a small third body.
        for mode in [CCDConfiguration.Mode.speculative, .hybrid] {
            let moving = body(0)
            moving.linearVelocity = Vector3(10, 10, 0)
            let wall = RigidBody(primitive: StaticPlane(Plane(1, 0, 0, -2)), motionType: .static,
                                material: PhysicsMaterial(friction: 0, restitution: 0))
            let obstacle = body(1.5, motion: .static)
            obstacle.transform.position.y = 4
            let (simulator, _) = simulator([moving, wall, obstacle], configuration: .init(mode: mode))
            simulator.step(timeStep: 1)
            if mode == .hybrid {
                XCTAssertLessThan(moving.transform.position.y, 4)
            } else {
                XCTAssertEqual(moving.transform.position.y, 10, accuracy: 1.0e-8)
            }
        }
    }

    func testDefaultHybridCatchesMovingKinematicAgainstSleepingCCD() {
        let moving = body(-3, motion: .kinematic), stationary = body(0)
        moving.linearVelocity = Vector3(12, 0, 0)
        stationary.putToSleep()
        let (simulator, _) = simulator([stationary, moving], configuration: .default)
        simulator.step(timeStep: 0.5)
        XCTAssertFalse(stationary.isSleeping)
        XCTAssertEqual(stationary.transform.position.x, 4, accuracy: 1.0e-8)
        XCTAssertEqual(moving.transform.position.x, 3, accuracy: 1.0e-8)
    }

    func testRepeatedSceneWithSameTickInputsHasMatchingResults() {
        func run() -> [(Transform, Vector3)] {
            let bodies = (0..<8).map { index -> RigidBody in
                let result = body(Scalar(index % 4) * 1.1, restitution: 0.5)
                result.transform.position.y = 1 + Scalar(index / 4) * 1.1
                result.linearVelocity = Vector3(index % 2 == 0 ? 2 : -2, 0, 0)
                return result
            }
            let floor = RigidBody(primitive: StaticPlane(Plane(0, 1, 0, 0)), motionType: .static)
            let (simulator, _) = simulator(bodies + [floor], configuration: .init(mode: .timeOfImpact, substepCount: 2))
            simulator.gravity = Vector3(0, -9.81, 0)
            for tick in 0..<60 {
                if tick == 20 { bodies[0].addForce(Vector3(30, 5, 0)) }
                simulator.step(timeStep: 1.0 / 60)
            }
            return bodies.map { ($0.transform, $0.linearVelocity) }
        }
        let first = run(), second = run()
        for (a, b) in zip(first, second) {
            XCTAssertLessThan((a.0.position - b.0.position).length, 1.0e-9)
            XCTAssertLessThan((a.1 - b.1).length, 1.0e-9)
            XCTAssertEqual(a.0.orientation, b.0.orientation)
        }
    }
}
