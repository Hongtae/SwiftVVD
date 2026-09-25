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

    // ASSERTIONS recordedPrimitiveUnevenCornerSurface27Observed
    func testUnevenRoundedRectangleUsesObservedStorageAndLaneOrder() {
        XCTAssertEqual(MemoryLayout<RectangleCornerRadii>.size, 32)
        XCTAssertEqual(MemoryLayout<RectangleCornerRadii>.alignment, 8)
        XCTAssertEqual(MemoryLayout<RectangleCornerRadii>.stride, 32)
        XCTAssertEqual(MemoryLayout<UnevenRoundedRectangle>.size, 33)
        XCTAssertEqual(MemoryLayout<UnevenRoundedRectangle>.alignment, 8)
        XCTAssertEqual(MemoryLayout<UnevenRoundedRectangle>.stride, 40)

        var radii = RectangleCornerRadii(
            topLeading: 2, bottomLeading: 4,
            bottomTrailing: 6, topTrailing: 8)
        XCTAssertEqual([radii.topLeading, radii.topTrailing,
                        radii.bottomTrailing, radii.bottomLeading], [2, 8, 6, 4])
        XCTAssertEqual(Edge.Corner.allCases.map(\.rawValue), [0, 1, 2, 3])
        XCTAssertEqual(Edge.Corner.allCases.map { radii[$0] }, [2, 8, 4, 6])
        XCTAssertEqual([
            Edge.Corner.Set.none.rawValue, Edge.Corner.Set.topLeading.rawValue,
            Edge.Corner.Set.topTrailing.rawValue, Edge.Corner.Set.bottomLeading.rawValue,
            Edge.Corner.Set.bottomTrailing.rawValue, Edge.Corner.Set.all.rawValue,
            Edge.Corner.Set.leading.rawValue, Edge.Corner.Set.trailing.rawValue,
            Edge.Corner.Set.bottom.rawValue, Edge.Corner.Set.top.rawValue,
        ], [0, 1, 2, 4, 8, 15, 5, 10, 12, 3])

        radii.animatableData = .init(.init(11, 12), .init(13, 14))
        XCTAssertEqual([radii.topLeading, radii.topTrailing,
                        radii.bottomTrailing, radii.bottomLeading], [11, 12, 13, 14])

        let rect = CGRect(x: 10, y: 20, width: 144, height: 80)
        let source = RectangleCornerRadii(
            topLeading: 2, bottomLeading: 4,
            bottomTrailing: 6, topTrailing: 8)
        let circularShape = UnevenRoundedRectangle(cornerRadii: source, style: .circular)
        let circular = circularShape.path(in: rect)
        guard case let .roundedRect(payload) = circular.storage,
              case let .uneven(topLeft, topRight, bottomRight, bottomLeft) = payload.radii else {
            return XCTFail("Expected specialized uneven roundedRect storage")
        }
        XCTAssertEqual(payload.rect, rect)
        XCTAssertEqual([topLeft, topRight, bottomRight, bottomLeft], [2, 8, 6, 4])
        XCTAssertEqual(payload.style, .circular)
        XCTAssertEqual(circular.currentPoint, CGPoint(x: 154, y: 61))
        XCTAssertEqual(circular,
            Path(roundedRect: rect, cornerRadii: source, style: .circular))
        XCTAssertEqual(Path(roundedRect: rect, cornerRadii: .init(), style: .circular), Path(rect))

        var circularElements: [Path.Element] = []
        circular.forEach { circularElements.append($0) }
        XCTAssertEqual(circularElements.count, 10)
        XCTAssertEqual(circularElements[0], .move(to: CGPoint(x: 154, y: 61)))
        XCTAssertEqual(circularElements[1], .line(to: CGPoint(x: 154, y: 94)))
        XCTAssertEqual(circularElements[3], .line(to: CGPoint(x: 14, y: 100)))
        XCTAssertEqual(circularElements.last, .closeSubpath)

        let continuous = UnevenRoundedRectangle(
            cornerRadii: source, style: .continuous).path(in: rect)
        var continuousElements: [Path.Element] = []
        continuous.forEach { continuousElements.append($0) }
        XCTAssertEqual(continuousElements.count, 18)
        XCTAssertEqual(continuousElements[0], .move(to: CGPoint(x: 154, y: 61)))
        guard case let .line(point) = continuousElements[1] else {
            return XCTFail("Expected the bottom-right continuous-corner entry")
        }
        assertPoint(point, equals: CGPoint(x: 154, y: 90.82801032066345),
                    accuracy: 0.000001, file: #filePath, line: #line)
        XCTAssertEqual(continuousElements.last, .closeSubpath)

        let inset = circularShape.inset(by: 3)
        XCTAssertEqual(inset.path(in: rect), Path(
            roundedRect: rect.insetBy(dx: 3, dy: 3),
            cornerRadii: .init(
                topLeading: 0, bottomLeading: 1,
                bottomTrailing: 3, topTrailing: 5),
            style: .circular))
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

    func testTrimmedMixedSubpathsPreserveExactElements() {
        let firstCubicControl = 20.0 + 10.0 / 3.0
        let secondCubicControl = 20.0 + 20.0 / 3.0
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 10, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: 20, y: 0),
            control: CGPoint(x: 15, y: 0)
        )
        path.addCurve(
            to: CGPoint(x: 30, y: 0),
            control1: CGPoint(x: firstCubicControl, y: 0),
            control2: CGPoint(x: secondCubicControl, y: 0)
        )
        path.closeSubpath()
        path.move(to: CGPoint(x: 100, y: 0))
        path.addLine(to: CGPoint(x: 110, y: 0))

        let trimmed = path.trimmedPath(from: 0.125, to: 0.875)

        XCTAssertEqual(
            pathBox(trimmed).data.elements,
            [
                .move(to: CGPoint(x: 5, y: 0)),
                .line(to: CGPoint(x: 10, y: 0)),
                .quadCurve(
                    to: CGPoint(x: 20, y: 0),
                    control: CGPoint(x: 15, y: 0)
                ),
                .curve(
                    to: CGPoint(x: 30, y: 0),
                    control1: CGPoint(x: firstCubicControl, y: 0),
                    control2: CGPoint(x: secondCubicControl, y: 0)
                ),
                .closeSubpath,
                .move(to: CGPoint(x: 100, y: 0)),
                .line(to: CGPoint(x: 105, y: 0)),
            ]
        )
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

    func testUniqueMutationReusesReservedElementBuffer() {
        var path = Path()
        path.move(to: CGPoint(x: 1, y: 2))
        pathBox(path).data.elements.reserveCapacity(64)

        let identityBefore = bufferIdentity(path)
        path.addLine(to: CGPoint(x: 3, y: 4))
        let identityAfter = bufferIdentity(path)

        XCTAssertEqual(identityAfter.box, identityBefore.box)
        XCTAssertEqual(identityAfter.elements, identityBefore.elements)
    }

    func testConsecutiveMovesRemainDistinctBufferElements() {
        var path = Path()
        path.move(to: CGPoint(x: -4, y: 8))
        path.move(to: CGPoint(x: -3, y: 7))

        XCTAssertEqual(
            pathBox(path).data.elements,
            [
                .move(to: CGPoint(x: -4, y: 8)),
                .move(to: CGPoint(x: -3, y: 7)),
            ]
        )
        XCTAssertEqual(
            path.boundingRect,
            CGRect(x: -4, y: 7, width: 1, height: 1)
        )
        XCTAssertEqual(path.currentPoint, CGPoint(x: -3, y: 7))
    }

    func testAddPathUsesSingleReservedDestinationBuffer() {
        var source = Path()
        source.move(to: CGPoint(x: 10, y: 20))
        source.addLine(to: CGPoint(x: 30, y: 40))
        source.addQuadCurve(
            to: CGPoint(x: 50, y: 60),
            control: CGPoint(x: 35, y: 55)
        )
        source.addCurve(
            to: CGPoint(x: 80, y: 90),
            control1: CGPoint(x: 55, y: 65),
            control2: CGPoint(x: 70, y: 85)
        )
        source.closeSubpath()

        var destination = Path()
        destination.move(to: CGPoint(x: -2, y: -3))
        destination.addLine(to: CGPoint(x: -1, y: -1))
        pathBox(destination).data.elements.reserveCapacity(64)
        let identityBefore = bufferIdentity(destination)

        destination.addPath(
            source,
            transform: CGAffineTransform(
                a: 1.25,
                b: 0.2,
                c: -0.1,
                d: 0.75,
                tx: 7,
                ty: -11
            )
        )
        let identityAfter = bufferIdentity(destination)

        XCTAssertEqual(identityAfter.box, identityBefore.box)
        XCTAssertEqual(identityAfter.elements, identityBefore.elements)
        XCTAssertEqual(pathBox(destination).data.elements.count, 7)
    }

    func testAxisAlignedAddPathBulkAppendMatchesElementReplay() {
        var source = Path()
        source.move(to: CGPoint(x: 10, y: 20))
        source.addLine(to: CGPoint(x: 30, y: 40))
        source.addQuadCurve(
            to: CGPoint(x: 50, y: 60),
            control: CGPoint(x: 35, y: 55)
        )
        source.addCurve(
            to: CGPoint(x: 80, y: 90),
            control1: CGPoint(x: 55, y: 65),
            control2: CGPoint(x: 70, y: 85)
        )
        source.closeSubpath()

        var actual = Path()
        actual.move(to: CGPoint(x: -2, y: -3))
        actual.addLine(to: CGPoint(x: -1, y: -1))
        var expected = actual
        let transform = CGAffineTransform(
            a: 0,
            b: -2,
            c: 3,
            d: 0,
            tx: 7,
            ty: -11
        )

        actual.addPath(source, transform: transform)
        appendElements(of: source, transform: transform, to: &expected)

        XCTAssertEqual(pathBox(actual).data, pathBox(expected).data)
    }

    func testAxisAlignedShapeAppendsMatchElementReplay() {
        let rect = CGRect(x: 2, y: 4, width: 12, height: 20)
        let transform = CGAffineTransform(
            a: 0,
            b: -2,
            c: 3,
            d: 0,
            tx: 7,
            ty: -11
        )

        func basePath() -> Path {
            var path = Path()
            path.move(to: CGPoint(x: -2, y: -3))
            path.addLine(to: CGPoint(x: -1, y: -1))
            return path
        }

        var actualRect = basePath()
        actualRect.addRect(rect, transform: transform)
        var expectedRect = basePath()
        appendElements(
            of: Path(rect),
            transform: transform,
            to: &expectedRect
        )
        XCTAssertEqual(
            pathBox(actualRect).data,
            pathBox(expectedRect).data
        )

        var actualEllipse = basePath()
        actualEllipse.addEllipse(in: rect, transform: transform)
        var expectedEllipse = basePath()
        appendElements(
            of: Path(ellipseIn: rect),
            transform: transform,
            to: &expectedEllipse
        )
        XCTAssertEqual(
            pathBox(actualEllipse).data,
            pathBox(expectedEllipse).data
        )

        let cornerSize = CGSize(width: 4, height: 7)
        var actualRoundedRect = basePath()
        actualRoundedRect.addRoundedRect(
            in: rect,
            cornerSize: cornerSize,
            style: .circular,
            transform: transform
        )
        var expectedRoundedRect = basePath()
        appendElements(
            of: Path(
                roundedRect: rect,
                cornerSize: cornerSize,
                style: .circular
            ),
            transform: transform,
            to: &expectedRoundedRect
        )
        assertPathDataApproximatelyEqual(
            pathBox(actualRoundedRect).data,
            pathBox(expectedRoundedRect).data
        )
    }

    func testAddLinesStartsANewSubpathInOneBufferMutation() {
        var empty = Path()
        empty.addLines([])
        assertEmpty(empty)

        var onePoint = Path()
        onePoint.addLines([CGPoint(x: 1, y: 2)])
        XCTAssertEqual(
            pathBox(onePoint).data.elements,
            [.move(to: CGPoint(x: 1, y: 2))]
        )

        var path = Path()
        path.move(to: CGPoint(x: -2, y: -3))
        path.addLine(to: CGPoint(x: -1, y: -1))
        pathBox(path).data.elements.reserveCapacity(64)
        let identityBefore = bufferIdentity(path)

        path.addLines([
            CGPoint(x: 10, y: 20),
            CGPoint(x: 30, y: 40),
        ])

        XCTAssertEqual(bufferIdentity(path).box, identityBefore.box)
        XCTAssertEqual(bufferIdentity(path).elements, identityBefore.elements)
        XCTAssertEqual(
            pathBox(path).data.elements,
            [
                .move(to: CGPoint(x: -2, y: -3)),
                .line(to: CGPoint(x: -1, y: -1)),
                .move(to: CGPoint(x: 10, y: 20)),
                .line(to: CGPoint(x: 30, y: 40)),
            ]
        )
        XCTAssertEqual(path.currentPoint, CGPoint(x: 30, y: 40))
        XCTAssertEqual(path.boundingRect, CGRect(x: -2, y: -3, width: 32, height: 43))
    }

    func testAddingPathToItselfPreservesSourceElements() {
        var path = Path()
        path.move(to: CGPoint(x: 1, y: 2))
        path.addLine(to: CGPoint(x: 3, y: 4))
        path.addQuadCurve(
            to: CGPoint(x: 8, y: 9),
            control: CGPoint(x: 5, y: 7)
        )
        path.addCurve(
            to: CGPoint(x: 13, y: 17),
            control1: CGPoint(x: 9, y: 11),
            control2: CGPoint(x: 12, y: 15)
        )
        path.closeSubpath()

        let originalElements = pathBox(path).data.elements
        let transform = CGAffineTransform(
            a: 1.25,
            b: 0.2,
            c: -0.1,
            d: 0.75,
            tx: 7,
            ty: -11
        )
        path.addPath(path, transform: transform)

        let elements = pathBox(path).data.elements
        XCTAssertEqual(Array(elements.prefix(originalElements.count)), originalElements)
        XCTAssertEqual(elements.count, originalElements.count * 2)

        var expectedSuffix = Path()
        expectedSuffix.addPath(
            Path { source in
                for element in originalElements {
                    switch element {
                    case .move(let point):
                        source.move(to: point)
                    case .line(let point):
                        source.addLine(to: point)
                    case .quadCurve(let point, let control):
                        source.addQuadCurve(to: point, control: control)
                    case .curve(let point, let control1, let control2):
                        source.addCurve(
                            to: point,
                            control1: control1,
                            control2: control2
                        )
                    case .closeSubpath:
                        source.closeSubpath()
                    }
                }
            },
            transform: transform
        )
        XCTAssertEqual(
            Array(elements.suffix(originalElements.count)),
            pathBox(expectedSuffix).data.elements
        )
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
        guard case let .elliptic(width, height) = value.radii else {
            return XCTFail(
                "Expected elliptic roundedRect radii, got \(value.radii)",
                file: file,
                line: line
            )
        }
        XCTAssertEqual(CGSize(width: width, height: height), cornerSize,
                       file: file, line: line)
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

    private func bufferIdentity(
        _ path: Path,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (box: ObjectIdentifier, elements: UnsafeRawPointer?) {
        let box = pathBox(path, file: file, line: line)
        let elements = box.data.elements.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.map(UnsafeRawPointer.init)
        }
        return (ObjectIdentifier(box), elements)
    }

    private func appendElements(
        of source: Path,
        transform: CGAffineTransform,
        to destination: inout Path
    ) {
        source.forEach { element in
            switch element {
            case .move(let point):
                destination.move(to: point.applying(transform))
            case .line(let point):
                destination.addLine(to: point.applying(transform))
            case .quadCurve(let point, let control):
                destination.addQuadCurve(
                    to: point.applying(transform),
                    control: control.applying(transform)
                )
            case .curve(let point, let control1, let control2):
                destination.addCurve(
                    to: point.applying(transform),
                    control1: control1.applying(transform),
                    control2: control2.applying(transform)
                )
            case .closeSubpath:
                destination.closeSubpath()
            }
        }
    }

    private func assertPathDataApproximatelyEqual(
        _ actual: Path.PathData,
        _ expected: Path.PathData,
        accuracy: CGFloat = 0.000_000_000_001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.elements.count,
            expected.elements.count,
            file: file,
            line: line
        )
        for (actual, expected) in zip(actual.elements, expected.elements) {
            switch (actual, expected) {
            case (.move(let actual), .move(let expected)),
                 (.line(let actual), .line(let expected)):
                assertPoint(
                    actual,
                    equals: expected,
                    accuracy: accuracy,
                    file: file,
                    line: line
                )
            case (
                .quadCurve(let actualPoint, let actualControl),
                .quadCurve(let expectedPoint, let expectedControl)
            ):
                assertPoint(
                    actualPoint,
                    equals: expectedPoint,
                    accuracy: accuracy,
                    file: file,
                    line: line
                )
                assertPoint(
                    actualControl,
                    equals: expectedControl,
                    accuracy: accuracy,
                    file: file,
                    line: line
                )
            case (
                .curve(let actualPoint, let actualControl1, let actualControl2),
                .curve(
                    let expectedPoint,
                    let expectedControl1,
                    let expectedControl2
                )
            ):
                assertPoint(
                    actualPoint,
                    equals: expectedPoint,
                    accuracy: accuracy,
                    file: file,
                    line: line
                )
                assertPoint(
                    actualControl1,
                    equals: expectedControl1,
                    accuracy: accuracy,
                    file: file,
                    line: line
                )
                assertPoint(
                    actualControl2,
                    equals: expectedControl2,
                    accuracy: accuracy,
                    file: file,
                    line: line
                )
            case (.closeSubpath, .closeSubpath):
                break
            default:
                XCTFail(
                    "Path element cases differ: \(actual) != \(expected)",
                    file: file,
                    line: line
                )
            }
        }
        assertRect(
            actual.boundingBox,
            equals: expected.boundingBox,
            accuracy: accuracy,
            file: file,
            line: line
        )
        assertRect(
            actual.boundingBoxOfPath,
            equals: expected.boundingBoxOfPath,
            accuracy: accuracy,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.initialPoint, expected.initialPoint)
        XCTAssertEqual(actual.currentPoint, expected.currentPoint)
    }

    private func assertPoint(
        _ actual: CGPoint,
        equals expected: CGPoint,
        accuracy: CGFloat,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(
            actual.x,
            expected.x,
            accuracy: accuracy,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.y,
            expected.y,
            accuracy: accuracy,
            file: file,
            line: line
        )
    }

    private func assertRect(
        _ actual: CGRect,
        equals expected: CGRect,
        accuracy: CGFloat,
        file: StaticString,
        line: UInt
    ) {
        assertPoint(
            actual.origin,
            equals: expected.origin,
            accuracy: accuracy,
            file: file,
            line: line
        )
        assertPoint(
            CGPoint(x: actual.width, y: actual.height),
            equals: CGPoint(x: expected.width, y: expected.height),
            accuracy: accuracy,
            file: file,
            line: line
        )
    }
}
