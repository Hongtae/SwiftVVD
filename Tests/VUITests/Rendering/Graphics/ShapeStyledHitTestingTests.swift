import XCTest
@testable import VUI

final class ShapeStyledHitTestingTests: XCTestCase {
    func testPathLeafMaterializesBeforeFrameRejectAndRebuildsForNextCall() {
        let counter = ShapeInvocationCounter()
        let leaf = CountingStrokedLeaf(counter: counter)
        let outsidePoint = CGPoint(x: 50, y: 106)
        let strokedPath = Circle()
            .path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
            .strokedPath(StrokeStyle(lineWidth: 24))

        XCTAssertTrue(strokedPath.contains(outsidePoint))
        XCTAssertEqual(contains(leaf, points: [outsidePoint]).rawValue, 0)
        XCTAssertEqual(counter.shapeCalls, 1)

        XCTAssertEqual(contains(leaf, points: [outsidePoint]).rawValue, 0)
        XCTAssertEqual(counter.shapeCalls, 2)
    }

    func testPathLeafUsesFillStyleAndFrameOrigin() {
        var nestedRectangles = Path()
        nestedRectangles.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
        nestedRectangles.addRect(CGRect(x: 2, y: 2, width: 6, height: 6))
        let frame = CGRect(x: 20, y: 30, width: 10, height: 10)
        let point = CGPoint(x: 25, y: 35)

        let nonzero = FixedShapeLeaf(
            renderedShape: .path(nestedRectangles, FillStyle(eoFill: false)),
            frame: frame
        )
        let evenOdd = FixedShapeLeaf(
            renderedShape: .path(nestedRectangles, FillStyle(eoFill: true)),
            frame: frame
        )

        XCTAssertEqual(contains(nonzero, points: [point]).rawValue, 1)
        XCTAssertEqual(contains(evenOdd, points: [point]).rawValue, 0)
    }

    func testNonPathLeafBuildsMaskFromReturnedFrame() {
        let leaf = FixedShapeLeaf(
            renderedShape: .empty,
            frame: CGRect(x: 20, y: 30, width: 10, height: 10)
        )

        let result = contains(
            leaf,
            points: [CGPoint(x: 25, y: 35), CGPoint(x: 5, y: 5)]
        )

        XCTAssertEqual(result.rawValue, 1)
    }

    func testBackgroundShapeIsPreferredUnlessItIsEmpty() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let foreground = _ShapeStyle_RenderedShape.Shape.path(
            Path(frame),
            FillStyle()
        )

        let fallbackCounter = ShapeInvocationCounter()
        let fallbackLeaf = BackgroundShapeLeaf(
            foreground: foreground,
            background: .empty,
            frame: frame,
            counter: fallbackCounter
        )
        XCTAssertEqual(
            contains(fallbackLeaf, points: [CGPoint(x: 50, y: 50)]).rawValue,
            1
        )
        XCTAssertEqual(fallbackCounter.backgroundCalls, 1)
        XCTAssertEqual(fallbackCounter.shapeCalls, 1)

        let preferredCounter = ShapeInvocationCounter()
        let preferredLeaf = BackgroundShapeLeaf(
            foreground: foreground,
            background: .path(
                Path(CGRect(x: 0, y: 0, width: 10, height: 10)),
                FillStyle()
            ),
            frame: frame,
            counter: preferredCounter
        )
        XCTAssertEqual(
            contains(preferredLeaf, points: [CGPoint(x: 50, y: 50)]).rawValue,
            0
        )
        XCTAssertEqual(preferredCounter.backgroundCalls, 1)
        XCTAssertEqual(preferredCounter.shapeCalls, 0)
    }

    func testContentResponderHelperForwardsFullBufferWhileMaskCapsAt64() {
        let recorder = PointCountRecorder()
        var helper = ContentResponderHelper<CountingContentResponder>()
        helper.data = CountingContentResponder(recorder: recorder)
        helper.size = CGSize(width: 100, height: 100)

        let result = helper.containsGlobalPoints(
            Array(repeating: CGPoint(x: 50, y: 50), count: 65),
            cacheKey: nil,
            options: [],
            children: []
        )

        XCTAssertEqual(recorder.count, 65)
        XCTAssertEqual(result.mask.rawValue, UInt64.max)
    }

    private func contains<Leaf: ShapeStyledLeafView>(
        _ leaf: Leaf,
        points: [CGPoint]
    ) -> BitVector64 {
        points.withUnsafeBufferPointer {
            leaf.contains(points: $0, size: CGSize(width: 100, height: 100))
        }
    }
}

private final class ShapeInvocationCounter {
    var shapeCalls = 0
    var backgroundCalls = 0
}

private final class PointCountRecorder {
    var count = 0
}

private struct CountingContentResponder: ContentResponder {
    var recorder: PointCountRecorder

    func contains(
        points: UnsafeBufferPointer<CGPoint>,
        size: CGSize
    ) -> BitVector64 {
        recorder.count = points.count
        var result = BitVector64()
        for index in points.indices.prefix(64) {
            result[index] = true
        }
        return result
    }
}

private struct CountingStrokedLeaf: ShapeStyledLeafView {
    typealias ShapeUpdateData = Void

    var counter: ShapeInvocationCounter

    func shape(
        in size: CGSize
    ) -> (shape: _ShapeStyle_RenderedShape.Shape, frame: CGRect) {
        counter.shapeCalls += 1
        let frame = CGRect(origin: .zero, size: size)
        let path = Circle()
            .path(in: frame)
            .strokedPath(StrokeStyle(lineWidth: 24))
        return (.path(path, FillStyle()), frame)
    }
}

private struct FixedShapeLeaf: ShapeStyledLeafView {
    typealias ShapeUpdateData = Void

    var renderedShape: _ShapeStyle_RenderedShape.Shape
    var frame: CGRect

    func shape(
        in size: CGSize
    ) -> (shape: _ShapeStyle_RenderedShape.Shape, frame: CGRect) {
        (renderedShape, frame)
    }
}

private struct BackgroundShapeLeaf: ShapeStyledLeafView {
    typealias ShapeUpdateData = Void

    static var hasBackground: Bool { true }

    var foreground: _ShapeStyle_RenderedShape.Shape
    var background: _ShapeStyle_RenderedShape.Shape
    var frame: CGRect
    var counter: ShapeInvocationCounter

    func shape(
        in size: CGSize
    ) -> (shape: _ShapeStyle_RenderedShape.Shape, frame: CGRect) {
        counter.shapeCalls += 1
        return (foreground, frame)
    }

    func backgroundShape(
        in size: CGSize
    ) -> (shape: _ShapeStyle_RenderedShape.Shape, frame: CGRect) {
        counter.backgroundCalls += 1
        return (background, frame)
    }
}
