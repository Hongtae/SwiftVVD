import XCTest
@testable import VUI

final class StrokedShapeSurfaceTests: XCTestCase {
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
