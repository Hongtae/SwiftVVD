import XCTest
@testable import VUI

final class PathContainmentTests: XCTestCase {
    func testRoundedRectangleRejectsPointsOutsideItsBoundingRect() {
        let path = Path(
            roundedRect: CGRect(x: 0, y: 0, width: 8, height: 8),
            cornerRadius: 4
        )

        XCTAssertTrue(path.contains(CGPoint(x: 4, y: 4)))
        XCTAssertFalse(path.contains(CGPoint(x: 161, y: 4)))
        XCTAssertFalse(path.contains(CGPoint(x: -1, y: 4)))
    }

    func testRectAndEllipseEvaluateDegeneratePointCloudsIndependently() {
        let points = [CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 15)]

        XCTAssertEqual(
            batchContains(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), points),
            1
        )
        XCTAssertEqual(
            batchContains(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: 10, height: 10)),
                points
            ),
            1
        )
    }

    func testSpecializedRectAndEllipseUseObservedBoundaryRules() {
        let rect = Path(CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertTrue(rect.contains(CGPoint(x: 0, y: 0)))
        XCTAssertFalse(rect.contains(CGPoint(x: 10, y: 5)))
        XCTAssertFalse(Path(.zero).contains(.zero))
        XCTAssertTrue(
            Path(CGRect(x: 10, y: 20, width: -3, height: -4))
                .contains(CGPoint(x: 8.5, y: 18))
        )

        let ellipse = Path(ellipseIn: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertTrue(ellipse.contains(CGPoint(x: 5, y: 5)))
        XCTAssertFalse(ellipse.contains(CGPoint(x: 10, y: 5)))
        XCTAssertFalse(
            Path(ellipseIn: CGRect(x: 10, y: 20, width: -3, height: -4))
                .contains(CGPoint(x: 8.5, y: 18))
        )
    }

    func testRoundedRectBatchGateRejectsOneAxisPointClouds() {
        let path = Path(
            roundedRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            cornerRadius: 2,
            style: .circular
        )

        XCTAssertEqual(
            batchContains(path, [CGPoint(x: 5, y: 4), CGPoint(x: 5, y: 6)]),
            0
        )
        XCTAssertEqual(
            batchContains(path, [CGPoint(x: 4, y: 5), CGPoint(x: 6, y: 5)]),
            0
        )
        XCTAssertEqual(
            batchContains(path, [CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)]),
            3
        )
        XCTAssertEqual(
            batchContains(path, [CGPoint(x: 4, y: 4), CGPoint(x: 6, y: 6)]),
            3
        )
    }

    func testBufferBatchGateRejectsOneAxisPointClouds() {
        var path = Path(CGRect(x: 0, y: 0, width: 10, height: 10))
        path.addRect(CGRect(x: 20, y: 20, width: 10, height: 10))

        XCTAssertEqual(
            batchContains(path, [CGPoint(x: 4, y: 5), CGPoint(x: 6, y: 5)]),
            0
        )
        XCTAssertEqual(
            batchContains(path, [CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)]),
            3
        )
        XCTAssertEqual(
            batchContains(path, [CGPoint(x: 4, y: 4), CGPoint(x: 6, y: 6)]),
            3
        )
    }

    func testBatchContainmentSubtractsOriginBeforeBoundsGate() {
        let path = Path(
            roundedRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            cornerRadius: 2,
            style: .circular
        )
        let points = [CGPoint(x: 24, y: 34), CGPoint(x: 26, y: 36)]

        XCTAssertEqual(
            batchContains(path, points, origin: CGPoint(x: 20, y: 30)),
            3
        )
    }

    func testCurveBuffersPreserveWindingResults() {
        let quadratic = Path { path in
            path.move(to: CGPoint(x: -12, y: -8))
            path.addQuadCurve(
                to: CGPoint(x: 12, y: -8),
                control: CGPoint(x: -2, y: 22)
            )
            path.closeSubpath()
        }
        let cubic = Path { path in
            path.move(to: CGPoint(x: -12, y: -8))
            path.addCurve(
                to: CGPoint(x: 12, y: -8),
                control1: CGPoint(x: -9, y: 25),
                control2: CGPoint(x: 8, y: 5)
            )
            path.closeSubpath()
        }
        let points = [
            CGPoint(x: -13, y: 0), CGPoint(x: 13, y: 0),
            CGPoint(x: 0, y: -9), CGPoint(x: 0, y: -7),
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 6),
            CGPoint(x: 0, y: 8), CGPoint(x: -8, y: 0),
            CGPoint(x: 8, y: 0), CGPoint(x: -5, y: 5),
            CGPoint(x: 5, y: 5), CGPoint(x: 0, y: 15),
        ]

        for eoFill in [false, true] {
            XCTAssertEqual(
                publicContainsMask(quadratic, points, eoFill: eoFill),
                0x538
            )
            XCTAssertEqual(
                publicContainsMask(cubic, points, eoFill: eoFill),
                0x3f8
            )
            XCTAssertEqual(
                batchContains(quadratic, points, eoFill: eoFill),
                0x538
            )
            XCTAssertEqual(
                batchContains(cubic, points, eoFill: eoFill),
                0x3f8
            )
        }
    }

    private func publicContainsMask(
        _ path: Path,
        _ points: [CGPoint],
        eoFill: Bool
    ) -> UInt64 {
        var result: UInt64 = 0
        for (index, point) in points.enumerated() {
            if path.contains(point, eoFill: eoFill) {
                result |= UInt64(1) << UInt64(index)
            }
        }
        return result
    }

    private func batchContains(
        _ path: Path,
        _ points: [CGPoint],
        eoFill: Bool = false,
        origin: CGPoint = .zero
    ) -> UInt64 {
        points.withUnsafeBufferPointer {
            path.contains(points: $0, eoFill: eoFill, origin: origin).rawValue
        }
    }
}
