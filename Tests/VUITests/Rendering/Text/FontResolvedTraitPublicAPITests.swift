import Foundation
import XCTest
import VUI

// ASSERTIONS fontResolvedTraits27Observed

final class FontResolvedTraitPublicAPITests: XCTestCase {
    private var context: Font.Context {
        EnvironmentValues().fontResolutionContext
    }

    private func weightValue(_ weight: Font.Weight) -> CGFloat {
        let child = Mirror(reflecting: weight).children.first {
            $0.label == "value"
        }
        return child!.value as! CGFloat
    }

    func testPublicResolvedTraitsFollowRealizedSystemFont() {
        let base = Font.system(size: 31)
        let regular = base.resolve(in: context)
        XCTAssertFalse(regular.isBold)
        XCTAssertFalse(regular.isItalic)
        XCTAssertFalse(regular.isMonospaced)
        XCTAssertEqual(weightValue(regular.weight), 0)
        XCTAssertEqual(regular.width.value, 0)

        let weights: [(Font.Weight, CGFloat, Bool)] = [
            (.ultraLight, -0.800000011920929, false),
            (.thin, -0.6000000238418579, false),
            (.light, -0.4000000059604645, false),
            (.regular, 0, false),
            (.medium, 0.23000000417232513, false),
            (.semibold, 0.30000001192092896, true),
            (.bold, 0.4000000059604645, true),
            (.heavy, 0.5600000023841858, true),
            (.black, 0.6200000047683716, true),
        ]
        for (request, expected, isBold) in weights {
            let resolved = base.weight(request).resolve(in: context)
            XCTAssertEqual(resolved.isBold, isBold)
            XCTAssertFalse(resolved.isItalic)
            XCTAssertEqual(weightValue(resolved.weight), expected)
        }

        let italic = base.italic().resolve(in: context)
        XCTAssertFalse(italic.isBold)
        XCTAssertTrue(italic.isItalic)

        let monospaced = base.monospaced().resolve(in: context)
        XCTAssertTrue(monospaced.isMonospaced)
        XCTAssertFalse(base.monospacedDigit().resolve(in: context).isMonospaced)

        let widths: [(Font.Width, CGFloat)] = [
            (.compressed, -0.3),
            (.condensed, -0.2),
            (.standard, 0),
            (.expanded, 0.2),
        ]
        for (request, expected) in widths {
            let resolved = base.width(request).resolve(in: context)
            XCTAssertEqual(resolved.width.value, expected)
            XCTAssertFalse(resolved.isMonospaced)
        }
    }

    func testPublicResolvedTraitsUseOrderedResultAndContext() {
        let base = Font.system(size: 31)
        let regular = base.bold().bold(false).resolve(in: context)
        XCTAssertFalse(regular.isBold)
        XCTAssertEqual(weightValue(regular.weight), 0)

        let heavyCleared = base.weight(.heavy).bold(false).resolve(in: context)
        XCTAssertFalse(heavyCleared.isBold)
        XCTAssertEqual(weightValue(heavyCleared.weight), 0)

        XCTAssertTrue(
            base.monospaced().monospaced(false)
                .resolve(in: context).isMonospaced
        )
        XCTAssertTrue(
            base.monospaced(false).monospaced()
                .resolve(in: context).isMonospaced
        )

        var environment = EnvironmentValues()
        environment.legibilityWeight = .bold
        let legible = base.resolve(in: environment.fontResolutionContext)
        XCTAssertFalse(legible.isBold)
        XCTAssertEqual(weightValue(legible.weight), 0)

        let combined = Font.system(
            size: 31,
            weight: .heavy,
            design: .monospaced
        ).italic().width(.expanded)
        let ordinary = combined.resolve(in: context)
        XCTAssertTrue(ordinary.isBold)
        XCTAssertTrue(ordinary.isItalic)
        XCTAssertTrue(ordinary.isMonospaced)
        XCTAssertEqual(
            weightValue(ordinary.weight),
            0.5600000023841858
        )
        XCTAssertEqual(ordinary.width.value, 0)
    }

    func testPublicResolvedTraitsUseSelectedVariableFontValues() {
        let roboto = Font.custom("Roboto-Regular", fixedSize: 31)
        let heavy = roboto.weight(.heavy).resolve(in: context)
        XCTAssertTrue(heavy.isBold)
        XCTAssertEqual(
            weightValue(heavy.weight),
            0.6000000238418579
        )

        let condensed = roboto.width(.condensed).resolve(in: context)
        XCTAssertEqual(
            condensed.width.value,
            -0.20000000298023224
        )

        XCTAssertTrue(roboto.monospaced().resolve(in: context).isMonospaced)
        XCTAssertTrue(
            Font.custom("RobotoMono-Regular", fixedSize: 31)
                .resolve(in: context).isMonospaced
        )
        XCTAssertFalse(
            Font.custom("RobotoMono-Regular", fixedSize: 31)
                .monospaced(false).resolve(in: context).isMonospaced
        )
        let monospacedItalic = Font.custom(
            "RobotoMono-Regular",
            fixedSize: 31
        ).italic().resolve(in: context)
        XCTAssertTrue(monospacedItalic.isItalic)
        XCTAssertTrue(monospacedItalic.isMonospaced)
    }
}
