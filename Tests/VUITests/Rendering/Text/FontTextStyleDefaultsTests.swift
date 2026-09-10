import XCTest
@testable import VUI

final class FontTextStyleDefaultsTests: XCTestCase {
    func testSystemTextStylesUseDesktopDefaultSizesAndWeights() throws {
        let rows: [(Font.TextStyle, CGFloat, Font.Weight)] = [
            (.largeTitle, 26, .regular),
            (.title, 22, .regular),
            (.headline, 13, .bold),
            (.subheadline, 11, .regular),
            (.body, 13, .regular),
            (.callout, 12, .regular),
            (.footnote, 10, .regular),
            (.caption, 10, .regular),
        ]

        for (style, size, weight) in rows {
            let font = Font.system(style)
            let provider = try XCTUnwrap(font.resolved(in: EnvironmentValues()).typefaceProvider as? SystemFontProvider)
            XCTAssertEqual(provider.size, size)
            XCTAssertEqual(provider.weight, weight)
        }
    }

    func testExplicitRenderingModesKeepTextStyleDefaultWeight() throws {
        for font in [Font.bitmap(.headline), Font.vector(.headline)] {
            let provider = try XCTUnwrap(font.resolved(in: EnvironmentValues()).typefaceProvider as? SystemFontProvider)
            XCTAssertEqual(provider.size, 13)
            XCTAssertEqual(provider.weight, .bold)
        }
    }
}
