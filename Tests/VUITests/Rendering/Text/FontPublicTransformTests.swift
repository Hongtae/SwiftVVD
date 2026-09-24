import Foundation
import XCTest
import VUI

// ASSERTIONS fontPublicTransforms27Observed

final class FontPublicTransformTests: XCTestCase {
    private func context(font: Font? = nil) -> Font.Context {
        var environment = EnvironmentValues()
        environment.font = font
        return environment.fontResolutionContext
    }

    func testDefaultForwardsTheEffectiveFont() {
        let ordinary = context()
        XCTAssertEqual(Font.default.resolve(in: ordinary).pointSize, 13)
        XCTAssertEqual(
            Font.default.resolve(in: context(font: .system(size: 31))).pointSize,
            31
        )
        XCTAssertNotEqual(Font.default, .body)
        XCTAssertEqual(
            Font.default.resolve(in: ordinary),
            Font.body.resolve(in: ordinary)
        )
    }

    func testPointSizeAndScalePreserveOrderedTransforms() {
        let resolution = context()
        let base = Font.system(size: 17.125, weight: .light)

        XCTAssertEqual(base.pointSize(19.125).resolve(in: resolution).pointSize, 19.125)
        XCTAssertEqual(base.pointSize(17.125).resolve(in: resolution).pointSize, 17.125)
        XCTAssertEqual(base.pointSize(0).resolve(in: resolution).pointSize, 12)
        XCTAssertEqual(base.pointSize(-3).resolve(in: resolution).pointSize, 12)
        XCTAssertEqual(
            base.pointSize(.infinity).resolve(in: resolution).pointSize,
            .infinity
        )
        XCTAssertTrue(
            base.pointSize(.nan).resolve(in: resolution).pointSize.isNaN
        )

        XCTAssertEqual(base.scaled(by: 1).resolve(in: resolution).pointSize, 17.125)
        XCTAssertEqual(base.scaled(by: 1.000_000_000_1).resolve(in: resolution).pointSize, 17.25)
        XCTAssertEqual(base.scaled(by: 0.999_999_999_9).resolve(in: resolution).pointSize, 17)
        XCTAssertEqual(base.scaled(by: 0).resolve(in: resolution).pointSize, 12)
        XCTAssertEqual(base.scaled(by: -1).resolve(in: resolution).pointSize, 12)
        XCTAssertEqual(base.scaled(by: 1.1).resolve(in: resolution).pointSize, 18.75)

        XCTAssertEqual(
            base.scaled(by: 1.1).pointSize(19.125)
                .resolve(in: resolution).pointSize,
            19.125
        )
        XCTAssertEqual(
            base.pointSize(19.125).scaled(by: 1.1)
                .resolve(in: resolution).pointSize,
            21
        )
        XCTAssertEqual(
            base.scaled(by: 1.1).scaled(by: 1.1)
                .resolve(in: resolution).pointSize,
            20.75
        )
        XCTAssertEqual(
            base.pointSize(19.125).pointSize(23.375)
                .resolve(in: resolution).pointSize,
            23.375
        )
    }

    func testNoOpRequestsStillCreateDistinctFontValues() {
        let base = Font.system(size: 17.125, weight: .light)
        XCTAssertNotEqual(base.scaled(by: 1), base)
        XCTAssertNotEqual(base.pointSize(17.125), base)
        XCTAssertNotEqual(base.scaled(by: 0), base)
    }
}
