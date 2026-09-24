import XCTest
@testable import VUI

// ASSERTIONS dynamicTypeEnvironment27Observed

final class LegibilityFontResolutionTests: XCTestCase {
    private let weightTag: UInt32 = 0x7767_6874

    private struct Snapshot {
        let provider: SystemFontProvider
        let selected: SelectedFont
    }

    private func snapshot(
        _ font: Font,
        legibilityWeight: LegibilityWeight?
    ) throws -> Snapshot {
        var environment = EnvironmentValues()
        environment.legibilityWeight = legibilityWeight
        environment.defaultFontRenderingMode = .vector()
        let resolved = font.resolved(in: environment)
        let provider = try XCTUnwrap(
            resolved.typefaceProvider as? SystemFontProvider
        )
        let selected = try XCTUnwrap(
            provider.makeTypeface(
                StyleTestAppContext(),
                dpi: UInt32(defaultDPI)
            )?.selectedFont
        )
        return Snapshot(provider: provider, selected: selected)
    }

    func testBoldLegibilityKeepsLogicalWeightAndSelectsHeavierSystemFace()
        throws
    {
        let cases: [(Font, Font.Weight, CGFloat?)] = [
            (.system(size: 20, weight: .light), .light, nil),
            (.system(size: 20, weight: .regular), .regular, 600),
            (.system(size: 20, weight: .bold), .bold, 810),
            (.body, .regular, 600),
            (.headline, .bold, 810),
        ]

        for (font, logicalWeight, selectedWeight) in cases {
            let snapshot = try snapshot(
                font,
                legibilityWeight: .bold
            )
            XCTAssertEqual(snapshot.provider.weight, logicalWeight)
            XCTAssertEqual(
                snapshot.selected.variation[weightTag],
                selectedWeight
            )
        }
    }

    func testRegularLegibilityAndUnaffectedDesignsKeepOriginalSelection()
        throws
    {
        for (font, legibilityWeight, selectedWeight): (
            Font,
            LegibilityWeight?,
            CGFloat?
        ) in [
            (.system(size: 20), nil, nil),
            (.system(size: 20), .regular, nil),
            (.system(size: 20, design: .rounded), .bold, nil),
            (.system(size: 20, design: .monospaced), .bold, nil),
        ] {
            let snapshot = try snapshot(
                font,
                legibilityWeight: legibilityWeight
            )
            XCTAssertEqual(snapshot.provider.weight, .regular)
            XCTAssertEqual(
                snapshot.selected.variation[weightTag],
                selectedWeight
            )
        }
    }

    func testSymbolicBoldModifierConsumesLegibilityBeforeFaceSelection()
        throws
    {
        let cases: [(Font, CGFloat?)] = [
            (Font.system(.largeTitle).bold(), 700),
            (Font.system(.title).bold(), 700),
            (Font.system(.title2).bold(), 700),
            (Font.system(.title3).bold(), 600),
            (.body.bold(), 600),
            (.body.weight(.light).bold(), 600),
            (.headline.bold(), 780),
            (Font.system(.subheadline).bold(), 600),
            (Font.system(.callout).bold(), 600),
            (Font.system(.footnote).bold(), 600),
            (Font.system(.caption).bold(), 530),
            (Font.system(.caption2).bold(), 600),
            (.system(size: 20).bold(), 700),
            (.system(size: 20, weight: .light).bold(), 200),
            (.body.bold(false), nil),
            (.headline.bold(false), 700),
            (Font.system(.caption2).bold(false), 530),
            (.system(size: 20).bold(false), nil),
        ]

        for legibilityWeight: LegibilityWeight? in [nil, .bold] {
            for (font, selectedWeight) in cases {
                let snapshot = try snapshot(
                    font,
                    legibilityWeight: legibilityWeight
                )
                XCTAssertEqual(
                    snapshot.selected.variation[weightTag],
                    selectedWeight
                )
            }
        }
    }
}
