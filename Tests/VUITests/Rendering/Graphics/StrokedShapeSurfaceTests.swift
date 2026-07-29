import XCTest
@testable import VUI

final class StrokedShapeSurfaceTests: XCTestCase {
    func testDefaultShapeSizingReplacesOnlyUnspecifiedDimensions() {
        let shape = DefaultSizingProbeShape()
        let exact = ProposedViewSize(width: 240, height: 110)

        XCTAssertEqual(
            shape.path(in: CGRect(x: 0, y: 0, width: 240, height: 110))
                .boundingRect.size,
            CGSize(width: 200, height: 50)
        )
        XCTAssertEqual(
            shape.sizeThatFits(exact),
            CGSize(width: 240, height: 110)
        )
        XCTAssertEqual(
            shape.sizeThatFits(ProposedViewSize(width: 240, height: nil)),
            CGSize(width: 240, height: 10)
        )
        XCTAssertEqual(
            shape.sizeThatFits(ProposedViewSize(width: nil, height: 110)),
            CGSize(width: 10, height: 110)
        )
        XCTAssertEqual(
            shape.sizeThatFits(.unspecified),
            CGSize(width: 10, height: 10)
        )
        XCTAssertEqual(
            shape.sizeThatFits(ProposedViewSize(width: -3, height: -7)),
            CGSize(width: -3, height: -7)
        )
        XCTAssertEqual(
            shape.sizeThatFits(.infinity),
            CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
        )
    }

    func testStrokedShapeForwardsSizingToWrappedShape() {
        let exact = ProposedViewSize(width: 240, height: 110)
        let defaultShape = DefaultSizingProbeShape()
        let strokedDefault = _StrokedShape(
            shape: defaultShape,
            style: StrokeStyle(lineWidth: 5, lineCap: .round)
        )
        XCTAssertEqual(
            strokedDefault.sizeThatFits(exact),
            defaultShape.sizeThatFits(exact)
        )
        XCTAssertEqual(
            strokedDefault.sizeThatFits(.unspecified),
            defaultShape.sizeThatFits(.unspecified)
        )

        let intrinsicShape = IntrinsicSizingProbeShape()
        let strokedIntrinsic = _StrokedShape(
            shape: intrinsicShape,
            style: StrokeStyle(lineWidth: 23)
        )
        XCTAssertEqual(
            strokedIntrinsic.sizeThatFits(exact),
            CGSize(width: 37, height: 19)
        )
        XCTAssertEqual(
            strokedIntrinsic.sizeThatFits(.unspecified),
            CGSize(width: 37, height: 19)
        )
    }

    func testStrokedShapeAnimatableDataCarriesShapeAndStrokeStyle() {
        var shape = _StrokedShape(
            shape: AnimatableProbeShape(amount: 2),
            style: StrokeStyle(lineWidth: 3, miterLimit: 5, dashPhase: 7)
        )

        XCTAssertEqual(shape.animatableData.first, 2)
        XCTAssertEqual(shape.animatableData.second.first, 3)
        XCTAssertEqual(shape.animatableData.second.second.first, 5)
        XCTAssertEqual(shape.animatableData.second.second.second, 7)

        shape.animatableData = _StrokedShape<AnimatableProbeShape>.AnimatableData(
            11,
            StrokeStyle.AnimatableData(13, AnimatablePair(17, 19))
        )

        XCTAssertEqual(shape.shape.amount, 11)
        XCTAssertEqual(shape.style.lineWidth, 13)
        XCTAssertEqual(shape.style.miterLimit, 17)
        XCTAssertEqual(shape.style.dashPhase, 19)
    }
}

private struct DefaultSizingProbeShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: 20, dy: 30))
    }
}

private struct IntrinsicSizingProbeShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect)
    }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: 37, height: 19)
    }
}

private struct AnimatableProbeShape: Shape {
    var amount: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: amount, dy: amount))
    }

    typealias AnimatableData = CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    typealias Body = _ShapeView<Self, ForegroundStyle>
}
