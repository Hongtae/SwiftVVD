import Foundation
import XCTest
@testable import VUI

private final class PointCloudTestResponder: ViewResponder {
    var resultMask: BitVector64
    var resultPriority: Double
    var resultChildren: [ViewResponder]
    var policy: ViewResponder.HitTestPolicy
    var opacityValue: Double
    var calls = 0
    var receivedPoints: [[CGPoint]] = []
    var receivedCacheKeys: [UInt32?] = []

    init(
        mask: UInt64,
        priority: Double = 1.0,
        children: [ViewResponder] = [],
        policy: ViewResponder.HitTestPolicy = .include,
        opacity: Double = 1.0
    ) {
        resultMask = BitVector64(rawValue: mask)
        resultPriority = priority
        resultChildren = children
        self.policy = policy
        opacityValue = opacity
        super.init(host: nil)
    }

    override var opacity: Double {
        opacityValue
    }

    override func hitTestPolicy(
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.HitTestPolicy {
        policy
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        calls += 1
        receivedPoints.append(points)
        receivedCacheKeys.append(cacheKey)
        return ViewResponder.ContainsPointsResult(
            mask: resultMask,
            priority: resultPriority,
            children: resultChildren
        )
    }
}

final class PointCloudHitTestingTests: XCTestCase {
    override func tearDown() {
        HitTestPassThroughFeature.overrideValue = nil
        super.tearDown()
    }

    func testHitPointGeneratorUsesCenterAndFiveWeightedRings() {
        let center = CGPoint(x: 10, y: 20)

        let centerOnly = hitPoints(point: center, radius: 1.0)
        XCTAssertEqual(centerOnly.points, [center])
        XCTAssertEqual(centerOnly.weights, [24.0])

        let firstRing = hitPoints(point: center, radius: 5.0)
        XCTAssertEqual(firstRing.points.count, 5)
        XCTAssertEqual(firstRing.weights.count, 5)
        XCTAssertEqual(firstRing.points[1].x, 14.0, accuracy: 1e-12)
        XCTAssertEqual(firstRing.points[1].y, 20.0, accuracy: 1e-12)
        XCTAssertEqual(firstRing.weights[0], 24.0)
        XCTAssertEqual(firstRing.weights[1...4].reduce(0, +), 24.0)

        let maximumCloud = hitPoints(point: center, radius: 60.0)
        XCTAssertEqual(maximumCloud.points.count, 61)
        XCTAssertEqual(maximumCloud.weights.count, 61)
        XCTAssertEqual(maximumCloud.weights[0], 24.0)
        var ringStart = 1
        for ringPointCount in stride(from: 4, through: 20, by: 4) {
            let ringEnd = ringStart + ringPointCount
            XCTAssertEqual(
                maximumCloud.weights[ringStart..<ringEnd].reduce(0, +),
                24.0,
                accuracy: 1e-12
            )
            ringStart = ringEnd
        }
        XCTAssertEqual(maximumCloud.points[41].x, 60.0, accuracy: 1e-12)
        XCTAssertEqual(maximumCloud.points[41].y, 20.0, accuracy: 1e-12)

        let cappedCloud = hitPoints(point: center, radius: .infinity)
        XCTAssertEqual(cappedCloud.points.count, 61)
        XCTAssertEqual(cappedCloud.points[41].x, 60.0, accuracy: 1e-12)
    }

    func testPointCloudScoreUsesUnmaskedWeightsPriorityAndOpacity() {
        let responder = PointCloudTestResponder(
            mask: 0b111,
            priority: 2.0,
            opacity: 0.5
        )
        let result = responder.hitTest(
            globalPoints: [.zero, .zero, .zero],
            weights: [10.0, 20.0, 30.0],
            mask: BitVector64(rawValue: 0b010),
            cacheKey: nil,
            options: .platformDefault
        )

        XCTAssertTrue(result?.responder === responder)
        XCTAssertEqual(result?.priority, 40.0)
        XCTAssertEqual(result?.mask.rawValue, 0b010)

        responder.opacityValue = 0.5001
        let opaqueResult = responder.hitTest(
            globalPoints: [.zero, .zero, .zero],
            weights: [10.0, 20.0, 30.0],
            mask: BitVector64(rawValue: 0b010),
            cacheKey: nil,
            options: .platformDefault
        )
        XCTAssertEqual(opaqueResult?.priority ?? 0, 40.008, accuracy: 1e-12)
        XCTAssertEqual(opaqueResult?.mask.rawValue, 0b111)
    }

    func testParentMissesAreMaskedBeforeChildSelection() {
        HitTestPassThroughFeature.overrideValue = true
        let child = PointCloudTestResponder(mask: 0b10)
        let parent = PointCloudTestResponder(mask: 0b01, children: [child])

        let result = parent.hitTest(
            globalPoints: [.zero, .zero],
            weights: [10.0, 20.0],
            mask: [],
            cacheKey: nil,
            options: .platformDefault
        )

        XCTAssertTrue(result?.responder === parent)
        XCTAssertEqual(result?.priority, 10.0)
        XCTAssertEqual(result?.mask.rawValue, 0b01)
        XCTAssertEqual(child.calls, 1)
    }

    func testEqualChildrenKeepFirstReverseTraversalCandidate() {
        HitTestPassThroughFeature.overrideValue = true
        let first = PointCloudTestResponder(mask: 1, opacity: 0.5)
        let second = PointCloudTestResponder(mask: 1, opacity: 0.5)
        let parent = PointCloudTestResponder(
            mask: 1,
            children: [first, second]
        )

        let result = parent.hitTest(
            globalPoints: [.zero],
            weights: [24.0],
            mask: [],
            cacheKey: nil,
            options: .platformDefault
        )

        XCTAssertTrue(result?.responder === second)
        XCTAssertEqual(first.calls, 1)
        XCTAssertEqual(second.calls, 1)
    }

    func testLegacyChildThresholdUsesRunnerUpMultiplierAndMinimum() {
        HitTestPassThroughFeature.overrideValue = false
        let stronger = PointCloudTestResponder(
            mask: 1,
            priority: 1.2,
            opacity: 0.5
        )
        let runnerUp = PointCloudTestResponder(
            mask: 1,
            priority: 1.0,
            opacity: 0.5
        )
        let parent = PointCloudTestResponder(
            mask: 1,
            children: [stronger, runnerUp]
        )

        let tiedThreshold = parent.hitTest(
            globalPoints: [.zero],
            weights: [20.0],
            mask: [],
            cacheKey: nil,
            options: .platformDefault
        )
        XCTAssertTrue(tiedThreshold?.responder === parent)

        stronger.resultPriority = 1.21
        let aboveThreshold = parent.hitTest(
            globalPoints: [.zero],
            weights: [20.0],
            mask: [],
            cacheKey: nil,
            options: .platformDefault
        )
        XCTAssertTrue(aboveThreshold?.responder === stronger)

        parent.resultChildren = [runnerUp]
        let minimumThreshold = parent.hitTest(
            globalPoints: [.zero],
            weights: [16.0],
            mask: [],
            cacheKey: nil,
            options: .platformDefault
        )
        XCTAssertTrue(minimumThreshold?.responder === parent)
    }

    func testZeroSelfScoreStopsBeforeVisitingChildren() {
        let child = PointCloudTestResponder(mask: 1)
        let parent = PointCloudTestResponder(
            mask: 1,
            priority: 0,
            children: [child]
        )

        XCTAssertNil(parent.hitTest(
            globalPoints: [.zero],
            weights: [24.0],
            mask: [],
            cacheKey: nil,
            options: .platformDefault
        ))
        XCTAssertEqual(child.calls, 0)
    }

    func testPublicHitTestRouteHonorsPointCloudOptionAndCacheKey() {
        let responder = PointCloudTestResponder(mask: UInt64.max)
        XCTAssertTrue(responder.hitTest(
            globalPoint: CGPoint(x: 3, y: 4),
            radius: 60,
            cacheKey: 7,
            options: .platformDefault
        ) === responder)
        XCTAssertEqual(responder.receivedPoints.last?.count, 61)
        XCTAssertEqual(responder.receivedCacheKeys.last!, 7)

        XCTAssertTrue(responder.hitTest(
            globalPoint: CGPoint(x: 3, y: 4),
            radius: 60,
            cacheKey: 9,
            options: [.disablePointCloudHitTesting, .uncached]
        ) === responder)
        XCTAssertEqual(responder.receivedPoints.last?.count, 1)
        XCTAssertNil(responder.receivedCacheKeys.last!)
    }
}
