import Foundation
import XCTest
import VUI

// ASSERTIONS fontSmallCaps27Observed

final class FontSmallCapsPublicAPITests: XCTestCase {
    private let context = EnvironmentValues().fontResolutionContext

    private func flags(_ font: Font) -> [Bool] {
        let resolved = font.resolve(in: context)
        return [
            resolved.isLowercaseSmallCaps,
            resolved.isSmallCaps,
            resolved.isUppercaseSmallCaps,
        ]
    }

    func testPublicProducersPreserveCurrentIdentityAndOrder() {
        let base = Font.system(size: 31)
        let lower = base.lowercaseSmallCaps()
        let upper = base.uppercaseSmallCaps()
        let all = base.smallCaps()

        XCTAssertEqual(lower, base.lowercaseSmallCaps(true))
        XCTAssertEqual(upper, base.uppercaseSmallCaps(true))
        XCTAssertEqual(all, base.smallCaps(true))
        XCTAssertEqual(all, lower.uppercaseSmallCaps())
        XCTAssertNotEqual(all, upper.lowercaseSmallCaps())
        XCTAssertNotEqual(base.lowercaseSmallCaps(false), base)
        XCTAssertNotEqual(base.smallCaps(false), base)
        XCTAssertNotEqual(lower.lowercaseSmallCaps(), lower)
    }

    func testResolvedFlagsFollowTheEffectiveLowercaseFeature() {
        let base = Font.system(size: 31)
        let lower = base.lowercaseSmallCaps()
        let upper = base.uppercaseSmallCaps()
        let all = base.smallCaps()
        let none = [false, false, false]
        let enabled = [true, true, true]

        XCTAssertEqual(flags(base), none)
        XCTAssertEqual(flags(lower), enabled)
        XCTAssertEqual(flags(base.lowercaseSmallCaps(false)), none)
        XCTAssertEqual(flags(upper), none)
        XCTAssertEqual(flags(base.uppercaseSmallCaps(false)), none)
        XCTAssertEqual(flags(all), enabled)
        XCTAssertEqual(flags(base.smallCaps(false)), none)
        XCTAssertEqual(flags(upper.lowercaseSmallCaps()), enabled)

        XCTAssertEqual(flags(lower.lowercaseSmallCaps(false)), none)
        XCTAssertEqual(
            flags(base.lowercaseSmallCaps(false).lowercaseSmallCaps()),
            enabled
        )
        XCTAssertEqual(flags(all.lowercaseSmallCaps(false)), none)
        XCTAssertEqual(
            flags(base.smallCaps(false).lowercaseSmallCaps()),
            enabled
        )
        XCTAssertEqual(flags(all.uppercaseSmallCaps(false)), enabled)
        XCTAssertEqual(
            flags(base.smallCaps(false).uppercaseSmallCaps()),
            none
        )

        for font in [base, lower, upper, all, base.smallCaps(false)] {
            XCTAssertEqual(font.resolve(in: context).pointSize, 31)
        }
    }
}
