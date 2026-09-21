import XCTest
import VVD

final class ConvexSweepRobustnessTests: XCTestCase {
    func testSmallAxisAlignedSweepsRetainTheFirstContact() throws {
        for scale: Scalar in [1.0e-4, 1.0e-3, 0.01, 1] {
            let a = Box(halfExtents: Vector3(0.5, 0.1, 0.3) * scale)
            let b = Box(halfExtents: Vector3(0.5, 0.5, 0.5) * scale)
            let hit = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(a, b,
                frame: Transform(position: Vector3(3, 0, 0) * scale),
                translation: Vector3(6, 0, 0) * scale), "scale=\(scale)")
            XCTAssertEqual(hit.fraction, 1.0 / 3.0, accuracy: 1.0e-7)
        }
    }

    func testScaledRotatedBoxSweepsMatchContinuousSAT() {
        for scale: Scalar in [1.0e-4, 1.0e-3, 0.01, 1] {
            for angle: Scalar in [0.1, 0.7, 1.3] {
                for height: Scalar in [0.1, 0.5] {
                    for y: Scalar in [-0.6, 0, 0.6] {
                        for z: Scalar in [-0.3, 0, 0.3] {
                            let a = Box(halfExtents: Vector3(0.5, height, 0.3) * scale)
                            let b = Box(halfExtents: Vector3(0.5, 0.5, 0.5) * scale)
                            let frame = Transform(orientation: Quaternion(angle: angle, axis: Vector3(1, 2, 3)),
                                                  position: Vector3(3, y, z) * scale)
                            let translation = Vector3(6, 0, 0) * scale
                            let expected = boxTimeOfImpact(a, b, frame: frame, translation: translation)
                            let hit = CollisionAlgorithms.timeOfImpact(a, b, frame: frame, translation: translation)
                            let scenario = "scale=\(scale), angle=\(angle), height=\(height), y=\(y), z=\(z)"
                            if let expected {
                                XCTAssertNotNil(hit, scenario)
                                if let hit { XCTAssertEqual(hit.fraction, expected, accuracy: 1.0e-6, scenario) }
                            } else {
                                XCTAssertNil(hit, scenario)
                            }
                        }
                    }
                }
            }
        }
    }

    func testSmallMotionSweepConvergesWithoutAnUnnecessaryStop() {
        let scale = Scalar(1.0e-4)
        let a = Box(halfExtents: Vector3(0.5, 0.1, 0.3) * scale)
        let b = Box(halfExtents: Vector3(0.5, 0.5, 0.5) * scale)
        let frame = Transform(orientation: Quaternion(angle: 0.1, axis: Vector3(1, 2, 3)),
                              position: Vector3(3, -0.6, -0.3) * scale)
        let translation = Vector3(6, 0, 0) * scale
        let result = CollisionAlgorithmRegistry().sweepMotion(a, motionA: .init(translation: translation),
            b, motionB: .init(start: frame), distanceTolerance: scale * 1.0e-8)
        guard case .hit(let hit) = result else { return XCTFail("Unexpected sweep result: \(result)") }
        XCTAssertEqual(hit.fraction, boxTimeOfImpact(a, b, frame: frame, translation: translation)!, accuracy: 1.0e-6)
    }

    // Independent exact reference for boxes with fixed orientations: intersect
    // the time intervals of all 15 separating axes, without GJK or a step loop.
    private func boxTimeOfImpact(_ a: Box, _ b: Box, frame: Transform,
                                 translation: Vector3) -> Scalar? {
        let axesA = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
        let axesB = axesA.map { $0.applying(frame.orientation) }
        let axes = axesA + axesB + axesA.flatMap { a in axesB.map { Vector3.cross(a, $0) } }
        var lower: Scalar = 0, upper: Scalar = 1
        for raw in axes where raw.lengthSquared > 1.0e-24 {
            let axis = raw.normalized()
            let radius = (0..<3).reduce(Scalar.zero) {
                $0 + a.halfExtents[$1] * abs(Vector3.dot(axis, axesA[$1])) +
                    b.halfExtents[$1] * abs(Vector3.dot(axis, axesB[$1]))
            }
            let center = Vector3.dot(axis, frame.position)
            let speed = Vector3.dot(axis, translation)
            if abs(speed) < 1.0e-20 {
                if abs(center) > radius { return nil }
                continue
            }
            let first = (center - radius) / speed, last = (center + radius) / speed
            lower = Swift.max(lower, Swift.min(first, last))
            upper = Swift.min(upper, Swift.max(first, last))
            if lower > upper { return nil }
        }
        return lower
    }
}
