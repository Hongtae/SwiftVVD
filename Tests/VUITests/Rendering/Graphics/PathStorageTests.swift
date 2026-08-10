import XCTest
@testable import VUI

final class PathStorageTests: XCTestCase {
    private let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
    private let secondRect = CGRect(x: 60, y: 70, width: 20, height: 10)

    func testConstructorsSelectSpecializedStorage() {
        assertEmpty(Path())
        assertRect(Path(rect), equals: rect)
        assertEllipse(Path(ellipseIn: rect), equals: rect)

        let rounded = Path(
            roundedRect: rect,
            cornerSize: CGSize(width: 6, height: 7),
            style: .continuous
        )
        assertRoundedRect(
            rounded,
            rect: rect,
            cornerSize: CGSize(width: 6, height: 7),
            style: .continuous
        )

        assertRect(
            Path(roundedRect: rect, cornerRadius: 0, style: .circular),
            equals: rect
        )

        let negativeRect = CGRect(x: 10, y: 20, width: -3, height: -4)
        let rectPath = Path(negativeRect)
        assertRect(rectPath, equals: negativeRect)
        XCTAssertEqual(rectPath.currentPoint, negativeRect.origin)

        let ellipsePath = Path(ellipseIn: negativeRect)
        assertEllipse(ellipsePath, equals: negativeRect)
        XCTAssertEqual(ellipsePath.currentPoint, CGPoint(x: 10, y: 18))

        let roundedPath = Path(
            roundedRect: negativeRect,
            cornerSize: CGSize(width: 6, height: 6),
            style: .circular
        )
        assertRoundedRect(
            roundedPath,
            rect: negativeRect,
            cornerSize: CGSize(width: 6, height: 6),
            style: .circular
        )
        XCTAssertEqual(roundedPath.currentPoint, CGPoint(x: 10, y: 18))

        let zeroWidthCorner = Path(
            roundedRect: rect,
            cornerSize: CGSize(width: 0, height: 6),
            style: .circular
        )
        assertRoundedRect(
            zeroWidthCorner,
            rect: rect,
            cornerSize: CGSize(width: 0, height: 6),
            style: .circular
        )
        XCTAssertEqual(zeroWidthCorner.currentPoint, rect.origin)
    }

    func testAddOperationsStandardizeRectButRetainCornerPayload() {
        let negativeRect = CGRect(x: 10, y: 20, width: -3, height: -4)
        let standardizedRect = CGRect(x: 7, y: 16, width: 3, height: 4)

        var rectPath = Path()
        rectPath.addRect(negativeRect)
        assertRect(rectPath, equals: standardizedRect)

        var ellipsePath = Path()
        ellipsePath.addEllipse(in: negativeRect)
        assertEllipse(ellipsePath, equals: standardizedRect)

        var roundedPath = Path()
        roundedPath.addRoundedRect(
            in: negativeRect,
            cornerSize: CGSize(width: 100, height: 80),
            style: .circular
        )
        assertRoundedRect(
            roundedPath,
            rect: standardizedRect,
            cornerSize: CGSize(width: 100, height: 80),
            style: .circular
        )
    }

    func testAxisAlignedTransformsPreserveSpecializedStorage() {
        let scale = CGAffineTransform(scaleX: -2, y: 3)
        let axisSwap = CGAffineTransform(
            a: 0,
            b: 1,
            c: -1,
            d: 0,
            tx: 0,
            ty: 0
        )

        var scaledRect = Path()
        scaledRect.addRect(rect, transform: scale)
        assertRect(
            scaledRect,
            equals: CGRect(x: -80, y: 60, width: 60, height: 120)
        )

        var swappedEllipse = Path()
        swappedEllipse.addEllipse(in: rect, transform: axisSwap)
        assertEllipse(
            swappedEllipse,
            equals: CGRect(x: -60, y: 10, width: 40, height: 30)
        )

        var scaledRoundedRect = Path()
        scaledRoundedRect.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: 6, height: 6),
            style: .circular,
            transform: scale
        )
        assertRoundedRect(
            scaledRoundedRect,
            rect: CGRect(x: -80, y: 60, width: 60, height: 120),
            cornerSize: CGSize(width: 12, height: 18),
            style: .circular
        )

        var rotatedRect = Path()
        rotatedRect.addRect(
            rect,
            transform: CGAffineTransform(rotationAngle: .pi / 4)
        )
        assertBuffer(rotatedRect)
    }

    func testAdditionalMutationPromotesSpecializedStorageToBuffer() {
        var twoRects = Path(rect)
        twoRects.addRect(secondRect)
        assertBuffer(twoRects)

        var ellipseThenLine = Path(ellipseIn: rect)
        ellipseThenLine.addLine(to: CGPoint(x: 100, y: 100))
        assertBuffer(ellipseThenLine)

        var moveOnly = Path()
        moveOnly.move(to: CGPoint(x: 1, y: 2))
        assertBuffer(moveOnly)
        XCTAssertEqual(
            moveOnly.boundingRect,
            CGRect(x: 1, y: 2, width: 0, height: 0)
        )

        var callbackRect = Path { path in
            path.addRect(rect)
        }
        assertRect(callbackRect, equals: rect)
        callbackRect.closeSubpath()
        assertBuffer(callbackRect)

        var oneRect = Path()
        oneRect.addRects([rect])
        assertRect(oneRect, equals: rect)
        oneRect.addRects([secondRect])
        assertBuffer(oneRect)
    }

    func testPromotionRetainsSpecializedBoundsAndMaterializedStartPoint() {
        let negativeRect = CGRect(x: 10, y: 20, width: -3, height: -4)

        var rectPath = Path(negativeRect)
        rectPath.closeSubpath()
        assertBuffer(rectPath)
        XCTAssertEqual(rectPath.boundingRect, negativeRect)
        XCTAssertEqual(rectPath.currentPoint, CGPoint(x: 7, y: 16))

        var ellipsePath = Path(ellipseIn: negativeRect)
        ellipsePath.closeSubpath()
        assertBuffer(ellipsePath)
        XCTAssertEqual(ellipsePath.boundingRect, negativeRect)
        XCTAssertEqual(ellipsePath.currentPoint, CGPoint(x: 10, y: 18))

        var roundedPath = Path(
            roundedRect: negativeRect,
            cornerSize: CGSize(width: 6, height: 6),
            style: .circular
        )
        roundedPath.closeSubpath()
        assertBuffer(roundedPath)
        XCTAssertEqual(roundedPath.boundingRect, negativeRect)
        XCTAssertEqual(roundedPath.currentPoint, CGPoint(x: 10, y: 18))
    }

    func testRoundedPayloadMaterializesWithClampedGeometry() {
        let path = Path(
            roundedRect: rect,
            cornerSize: CGSize(width: 0, height: 6),
            style: .circular
        )
        var elements: [Path.Element] = []
        path.forEach { elements.append($0) }

        XCTAssertEqual(elements.count, 10)
        XCTAssertEqual(elements[0], .move(to: CGPoint(x: 40, y: 40)))
        XCTAssertEqual(elements[1], .line(to: CGPoint(x: 40, y: 54)))
        guard case .curve(let end, _, _) = elements[2] else {
            return XCTFail("Expected a clamped rounded corner curve")
        }
        XCTAssertEqual(end, CGPoint(x: 40, y: 60))
        assertRoundedRect(
            path,
            rect: rect,
            cornerSize: CGSize(width: 0, height: 6),
            style: .circular
        )
    }

    func testAddingPathAndApplyingTransformPreserveSpecializedStorage() {
        let translation = CGAffineTransform(translationX: 5, y: 7)
        let translatedRect = CGRect(x: 15, y: 27, width: 30, height: 40)

        var destination = Path()
        destination.addPath(Path(rect), transform: translation)
        assertRect(destination, equals: translatedRect)

        destination.addPath(Path())
        assertRect(destination, equals: translatedRect)

        assertRect(Path(rect).applying(.identity), equals: rect)
        assertRect(Path(rect).applying(translation), equals: translatedRect)
        assertBuffer(
            Path(ellipseIn: rect).applying(
                CGAffineTransform(rotationAngle: .pi / 4)
            )
        )
    }

    func testStrokingAndTrimmingUseObservedStorageTransitions() {
        let positiveStroke = Path(rect).strokedPath(.init(lineWidth: 4))
        assertBuffer(positiveStroke)
        XCTAssertEqual(
            positiveStroke.boundingRect,
            CGRect(x: 8, y: 18, width: 34, height: 44)
        )

        let zeroStroke = Path(rect).strokedPath(.init(lineWidth: 0))
        assertBuffer(zeroStroke)
        XCTAssertEqual(zeroStroke.boundingRect, rect)

        let negativeStroke = Path(rect).strokedPath(.init(lineWidth: -4))
        assertBuffer(negativeStroke)
        assertEmpty(Path().strokedPath(.init(lineWidth: 4)))

        assertRect(Path(rect).trimmedPath(from: 0, to: 1), equals: rect)
        let partialTrim = Path(rect).trimmedPath(from: 0.25, to: 0.75)
        assertBuffer(partialTrim)
        assertEmpty(Path().trimmedPath(from: 0.25, to: 0.75))
    }

    func testPathBoxSharesUntilMutationThenCopies() {
        var original = Path(rect)
        original.addRect(secondRect)
        var copy = original

        let originalBoxBefore = pathBox(original)
        let copyBoxBefore = pathBox(copy)
        XCTAssertTrue(originalBoxBefore === copyBoxBefore)

        copy.addLine(to: CGPoint(x: 200, y: 200))

        let originalBoxAfter = pathBox(original)
        let copyBoxAfter = pathBox(copy)
        XCTAssertTrue(originalBoxBefore === originalBoxAfter)
        XCTAssertFalse(originalBoxAfter === copyBoxAfter)
        XCTAssertEqual(original.boundingRect, CGRect(x: 10, y: 20, width: 70, height: 60))
        XCTAssertEqual(copy.boundingRect, CGRect(x: 10, y: 20, width: 190, height: 180))
    }

    func testBoundsAndElementReadsDoNotPromoteSpecializedStorage() {
        let path = Path(rect)

        XCTAssertEqual(path.boundingRect, rect)
        XCTAssertTrue(path.contains(CGPoint(x: 20, y: 30)))
        var elementCount = 0
        path.forEach { _ in elementCount += 1 }

        XCTAssertEqual(elementCount, 5)
        assertRect(path, equals: rect)
    }

    private func assertEmpty(
        _ path: Path,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .empty = path.storage else {
            return XCTFail("Expected empty storage, got \(path.storage)", file: file, line: line)
        }
    }

    private func assertRect(
        _ path: Path,
        equals rect: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .rect(let value) = path.storage else {
            return XCTFail("Expected rect storage, got \(path.storage)", file: file, line: line)
        }
        XCTAssertEqual(value, rect, file: file, line: line)
    }

    private func assertEllipse(
        _ path: Path,
        equals rect: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .ellipse(let value) = path.storage else {
            return XCTFail("Expected ellipse storage, got \(path.storage)", file: file, line: line)
        }
        XCTAssertEqual(value, rect, file: file, line: line)
    }

    private func assertRoundedRect(
        _ path: Path,
        rect: CGRect,
        cornerSize: CGSize,
        style: RoundedCornerStyle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .roundedRect(let value) = path.storage else {
            return XCTFail(
                "Expected roundedRect storage, got \(path.storage)",
                file: file,
                line: line
            )
        }
        XCTAssertEqual(value.rect, rect, file: file, line: line)
        XCTAssertEqual(value.cornerSize, cornerSize, file: file, line: line)
        XCTAssertEqual(value.style, style, file: file, line: line)
    }

    private func assertBuffer(
        _ path: Path,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .path(let box) = path.storage else {
            return XCTFail("Expected path storage, got \(path.storage)", file: file, line: line)
        }
        XCTAssertEqual(box.kind, .buffer, file: file, line: line)
    }

    private func pathBox(
        _ path: Path,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Path.PathBox {
        guard case .path(let box) = path.storage else {
            XCTFail("Expected path storage, got \(path.storage)", file: file, line: line)
            return Path.PathBox()
        }
        return box
    }
}
