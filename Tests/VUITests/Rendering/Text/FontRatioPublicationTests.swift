import Foundation
import XCTest
import VVD
@testable import VUI

final class FontRatioPublicationTests: XCTestCase {
    private func environment() -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        return environment
    }

    // ASSERTIONS fontRatioPublication27Observed
    func testPendingRatioSurvivesModifiersButIsNotPublishedByAFont() throws {
        let environment = environment()
        let context = environment.fontResolutionContext
        for font in [Font.system(size: 23.375), .body, .callout,
                     .custom("Roboto-Regular", fixedSize: 23.375)] {
            let pending = font.resolveDescriptor(in: context)
                .withTypesetting(language: "ur-Aran-PK", lineHeightRatio: 0.5)
            let modified = pending.clearFeatures().adding(features: Font.MonospacedDigitModifier.shapingFeatures)
            XCTAssertEqual(modified.languageAwareLineHeightRatio, 0.5)
            let resource = FontResource(descriptor: modified, in: context)
            XCTAssertEqual(resource.languageAwareLineHeightRatio, 0.5)
            let copied = resource.descriptor()
            XCTAssertNil(copied.languageAwareLineHeightRatio)
            XCTAssertEqual(copied.language, "ur-Aran-PK")
            XCTAssertEqual(copied.pointSize, resource.pointSize)
            XCTAssertEqual(copied.stylePolicy, modified.stylePolicy)
            XCTAssertEqual(copied.shapingFeatures, Font.MonospacedDigitModifier.shapingFeatures)
            let replaced = FontResource(descriptor: copied.withTypesetting(lineHeightRatio: 0.75), in: context)
            XCTAssertEqual(replaced.languageAwareLineHeightRatio, 0.75)
            XCTAssertEqual(resource.languageAwareLineHeightRatio, 0.5)
            XCTAssertNil(replaced.descriptor().languageAwareLineHeightRatio)
        }
    }

    // ASSERTIONS fontRatioPublication27Observed
    func testSizeAndDescriptorCopiesReconstructAutomaticMetrics() throws {
        let environment = environment()
        let context = environment.fontResolutionContext
        let app = StyleTestAppContext()
        func metrics(_ resource: FontResource) throws -> ResolvedFontMetrics {
            let face = try XCTUnwrap(resource.provider.makeTypeface(app, dpi: 72))
            return try XCTUnwrap(resource.resolvedMetrics(for: face, scaleFactor: 1))
        }
        for font in [Font.body, .callout] {
            for language in ["en-Latn-US", "ur-Aran-PK", "ja-Jpan-JP"] {
                let pending = font.resolveDescriptor(in: context).withTypesetting(language: language)
                let automatic = FontResource(descriptor: pending, in: context)
                let natural = try metrics(automatic)
                let enlarged = try metrics(XCTUnwrap(automatic.fontWithSize(31.375)))
                for ratio in [0.0, 0.33, 0.5, 1.0, 1.2] {
                    let original = FontResource(descriptor: pending.withTypesetting(lineHeightRatio: ratio), in: context)
                    let initial = try metrics(original)
                    XCTAssertTrue(try XCTUnwrap(original.fontWithSize(original.pointSize)) === original)
                    let copied = FontResource(descriptor: original.descriptor(), in: context)
                    let zero = try XCTUnwrap(original.fontWithSize(0))
                    let resized = try XCTUnwrap(original.fontWithSize(31.375))
                    for resource in [copied, zero, resized] {
                        XCTAssertNil(resource.languageAwareLineHeightRatio)
                        XCTAssertEqual(resource.language, language)
                        XCTAssertEqual(resource.stylePolicy, original.stylePolicy)
                        let actual = try metrics(resource)
                        let expected = resource.pointSize == 31.375 ? enlarged : natural
                        XCTAssertEqual(actual.ascender, expected.ascender, accuracy: 1e-10)
                        XCTAssertEqual(actual.descender, expected.descender, accuracy: 1e-10)
                        XCTAssertEqual(actual.leading, expected.leading, accuracy: 1e-10)
                        XCTAssertEqual(actual.capHeight, expected.capHeight)
                        XCTAssertEqual(actual.outsets, expected.outsets)
                    }
                    if language == "ur-Aran-PK" {
                        XCTAssertNotEqual(initial.ascender, natural.ascender)
                        XCTAssertNotEqual(initial.descender, natural.descender)
                    }
                    let retained = try metrics(original)
                    XCTAssertEqual(retained.ascender, initial.ascender)
                    XCTAssertEqual(retained.descender, initial.descender)
                    XCTAssertEqual(original.languageAwareLineHeightRatio, ratio)
                }
            }
        }
    }
}
