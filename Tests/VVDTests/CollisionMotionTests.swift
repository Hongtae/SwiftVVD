import XCTest
import VVD

final class CollisionMotionTests: XCTestCase {
    let algorithms = CollisionAlgorithmRegistry()

    func testRelativeSphereSweepHasWorldSpaceWitnesses() throws {
        let sphere = Sphere(center: .zero, radius: 0.5)
        let result = algorithms.sweepMotion(sphere,
            motionA: CollisionMotion(start: Transform(position: Vector3(10, 0, 0)), translation: Vector3(5, 0, 0)),
            sphere, motionB: CollisionMotion(start: Transform(position: Vector3(13, 0, 0)), translation: Vector3(-1, 0, 0)))
        guard case .hit(let hit) = result else { return XCTFail("Expected impact, got \(result)") }
        XCTAssertEqual(hit.fraction, 1.0 / 3, accuracy: 1.0e-9)
        XCTAssertEqual(hit.pointOnA.x, 12 + 1.0 / 6, accuracy: 1.0e-9)
        XCTAssertEqual(hit.pointOnA.x, hit.pointOnB.x, accuracy: 1.0e-9)
    }

    func testPublicSweepStillReportsInitialNonclosingCompoundContact() {
        let obstacle = CompoundPrimitive(children: [
            .init(StaticPlane(Plane(normal: Vector3(0, 1, 0), point: .zero))),
            .init(Box(halfExtents: Vector3(0.1, 2, 2)),
                  transform: Transform(position: Vector3(3, 1.5, 0)))
        ])
        let result = algorithms.sweepMotion(Sphere(center: .zero, radius: 0.5),
            motionA: CollisionMotion(start: Transform(position: Vector3(0, 0.5, 0)),
                                     translation: Vector3(5, 0, 0)),
            obstacle, motionB: CollisionMotion())
        guard case .hit(let hit) = result else { return XCTFail("Expected initial contact") }
        XCTAssertEqual(hit.fraction, 0)
    }

    func testRotationFindsObstacleBetweenDisjointEndpoints() {
        let bar = Box(halfExtents: Vector3(2, 0.05, 0.05))
        let obstacle = Sphere(center: .zero, radius: 0.1)
        let motion = CollisionMotion(angularDisplacement: Vector3(0, 0, .pi))
        let target = CollisionMotion(start: Transform(position: Vector3(0, 1.5, 0)))
        XCTAssertFalse(CollisionAlgorithms.intersects(bar, obstacle, frame: target.start))
        XCTAssertFalse(CollisionAlgorithms.intersects(bar, obstacle, frame: target.start * motion.transform(at: 1).inverted()))
        let result = algorithms.sweepMotion(bar, motionA: motion, obstacle, motionB: target)
        guard case .hit(let hit) = result else { return XCTFail("Expected rotational impact, got \(result)") }
        XCTAssertGreaterThan(hit.fraction, 0.4)
        XCTAssertLessThan(hit.fraction, 0.5)
        XCTAssertLessThan((hit.pointOnA - hit.pointOnB).length, 2.0e-6)
    }

    func testRotationAboutOffsetPivotPreservesPivotTrajectory() {
        let motion = CollisionMotion(start: Transform(position: Vector3(5, 2, 0)),
            translation: Vector3(3, 0, 0), angularDisplacement: Vector3(0, 0, .pi),
            localPivot: Vector3(1, 0, 0))
        let pivot = motion.localPivot.applying(motion.transform(at: 0.5))
        XCTAssertEqual(pivot.x, 7.5, accuracy: 1.0e-9)
        XCTAssertEqual(pivot.y, 2, accuracy: 1.0e-9)
    }

    func testConvexMeshSweepUsesTriangleCandidates() {
        let mesh = TriangleMesh(triangles: [Triangle(Vector3(3, -5, -5), Vector3(3, 5, -5), Vector3(3, 0, 5))])
        let result = algorithms.sweepMotion(Box(halfExtents: Vector3(0.5, 0.5, 0.5)),
            motionA: CollisionMotion(translation: Vector3(5, 0, 0)), mesh, motionB: CollisionMotion())
        guard case .hit(let hit) = result else { return XCTFail("Expected mesh hit, got \(result)") }
        XCTAssertEqual(hit.fraction, 0.5, accuracy: 1.0e-5)
    }

    func testPlaneSweepAndExhaustedIterationResult() {
        let box = Box(halfExtents: Vector3(0.5, 0.5, 0.5))
        let plane = StaticPlane(Plane(1, 0, 0, -3))
        let motion = CollisionMotion(translation: Vector3(5, 0, 0))
        let hit = algorithms.sweepMotion(box, motionA: motion, plane, motionB: CollisionMotion())
        guard case .hit(let witness) = hit else { return XCTFail("Expected plane hit") }
        XCTAssertEqual(witness.fraction, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(algorithms.sweepMotion(box, motionA: motion, plane,
            motionB: CollisionMotion(), maximumIterations: 0), .inconclusive(safeFraction: 0))
        XCTAssertEqual(algorithms.sweepMotion(box, motionA: motion, plane,
            motionB: CollisionMotion(angularDisplacement: Vector3(0, 1, 0))), .unsupported)
    }

    func testCustomTranslationRegistrationRetainsPrecedence() {
        var registry = CollisionAlgorithmRegistry(usesBuiltinFallback: false)
        registry.registerSweep(Sphere.self, Sphere.self) { _, _, _, _ in
            TimeOfImpact(fraction: 0.25, pointOnA: .zero, pointOnB: .zero, normal: Vector3(1, 0, 0))
        }
        let sphere = Sphere(center: .zero, radius: 1)
        let result = registry.sweepMotion(sphere, motionA: CollisionMotion(translation: Vector3(5, 0, 0)),
            sphere, motionB: CollisionMotion(start: Transform(position: Vector3(3, 0, 0))))
        guard case .hit(let hit) = result else { return XCTFail("Custom cast was not used") }
        XCTAssertEqual(hit.fraction, 0.25)
    }

    func testRegisteredLeafInsideCompoundWorksWithoutBuiltinFallback() {
        var registry = CollisionAlgorithmRegistry(usesBuiltinFallback: false)
        registry.registerSweep(Sphere.self, Sphere.self) { _, _, _, _ in
            TimeOfImpact(fraction: 0.25, pointOnA: .zero, pointOnB: .zero, normal: Vector3(1, 0, 0))
        }
        let sphere = Sphere(center: .zero, radius: 0.5)
        let compound = CompoundPrimitive(children: [.init(sphere)])
        let result = registry.sweepMotion(compound, motionA: CollisionMotion(translation: Vector3(5, 0, 0)),
            sphere, motionB: CollisionMotion(start: Transform(position: Vector3(3, 0, 0))))
        guard case .hit(let hit) = result else { return XCTFail("Expected registered leaf cast, got \(result)") }
        XCTAssertEqual(hit.fraction, 0.25)
    }

    func testCompoundUnboundedLeafCannotBePrunedByFiniteChildren() {
        let compound = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 0.5)),
            .init(StaticPlane(Plane(1, 0, 0, -3)))
        ])
        let motion = CollisionMotion(start: Transform(position: Vector3(0, 100, 0)),
                                     translation: Vector3(5, 0, 0))
        let result = algorithms.sweepMotion(Sphere(center: .zero, radius: 0.5), motionA: motion,
                                            compound, motionB: CollisionMotion())
        guard case .hit(let hit) = result else { return XCTFail("Unbounded leaf was missed") }
        XCTAssertEqual(hit.fraction, 0.5, accuracy: 1.0e-8)
    }

    func testInvalidMotionIsInconclusiveInsteadOfMiss() {
        let sphere = Sphere(center: .zero, radius: 0.5)
        let motion = CollisionMotion(translation: Vector3(.nan, 0, 0))
        XCTAssertFalse(motion.isValid)
        XCTAssertTrue(motion.sweptBounds(of: sphere).isNull)
        XCTAssertEqual(algorithms.sweepMotion(sphere, motionA: motion,
            sphere, motionB: CollisionMotion()), .inconclusive(safeFraction: 0))
    }
}
