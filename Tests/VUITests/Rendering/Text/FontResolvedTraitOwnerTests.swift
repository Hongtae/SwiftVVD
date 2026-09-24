import Foundation
import XCTest
@testable import VUI

// ASSERTIONS fontResolvedTraits27Observed

final class FontResolvedTraitOwnerTests: XCTestCase {
    private var context: Font.Context {
        EnvironmentValues().fontResolutionContext
    }

    func testResourceRetainsTraitsFromTheSelectedFace() {
        let resource = Font.custom("Roboto-Regular", fixedSize: 31)
            .weight(.heavy).platformFont(in: context)
        let traits = resource.realizedTraits

        XCTAssertEqual(traits.symbolic & 2, 2)
        XCTAssertEqual(traits.weight, 0.6000000238418579)
        XCTAssertEqual(traits.width, 0)
        XCTAssertNil(traits.design)

        let monospaced = Font.custom("RobotoMono-Regular", fixedSize: 31)
            .platformFont(in: context).realizedTraits
        XCTAssertEqual(monospaced.symbolic & 0x400, 0x400)
        XCTAssertTrue(monospaced.isMonospaced)
    }

    func testSystemResourceKeepsLogicalTraitsSeparateFromLegibilitySelection() {
        var environment = EnvironmentValues()
        environment.legibilityWeight = .bold
        let regular = Font.system(size: 31)
            .platformFont(in: environment.fontResolutionContext).realizedTraits
        let light = Font.system(size: 31, weight: .light)
            .platformFont(in: environment.fontResolutionContext).realizedTraits

        XCTAssertEqual(regular.symbolic & 2, 0)
        XCTAssertEqual(regular.weight, 0)
        XCTAssertEqual(light.symbolic & 2, 0)
        XCTAssertEqual(light.weight, -0.4000000059604645)
    }

    func testMonospacedCopyUsesRealizedFaceTraits() {
        let proportional = Font.custom("Roboto-Regular", fixedSize: 31)
        let monospaced = Font.custom("RobotoMono-Regular", fixedSize: 31)

        XCTAssertTrue(proportional.monospaced().resolve(in: context).isMonospaced)
        XCTAssertFalse(monospaced.monospaced(false).resolve(in: context).isMonospaced)
        XCTAssertTrue(monospaced.italic().resolve(in: context).isItalic)
        XCTAssertTrue(monospaced.italic().resolve(in: context).isMonospaced)
    }

    func testRedactionDoesNotChangeResolvedTraits() {
        let font = Font.system(
            size: 31,
            weight: .heavy,
            design: .monospaced
        ).italic().width(.expanded)
        let ordinary = font.platformFont(in: context).realizedTraits
        var environment = EnvironmentValues()
        environment.shouldRedactContent = true
        let redacted = font.platformFont(
            in: environment.fontResolutionContext
        ).realizedTraits

        XCTAssertEqual(ordinary.symbolic, redacted.symbolic)
        XCTAssertEqual(ordinary.weight, redacted.weight)
        XCTAssertEqual(ordinary.width, redacted.width)
        XCTAssertEqual(ordinary.design, redacted.design)
    }
}
