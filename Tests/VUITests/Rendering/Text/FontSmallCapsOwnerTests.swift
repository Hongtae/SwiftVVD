import Foundation
import XCTest
@testable import VUI

// ASSERTIONS fontSmallCaps27Observed

final class FontSmallCapsOwnerTests: XCTestCase {
    private typealias FeatureProvider = Font.ModifierProvider<Font.FeatureSettingModifier>

    private func featureProvider(
        _ font: Font,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FeatureProvider {
        try XCTUnwrap(
            (font.provider as? FontBox<FeatureProvider>)?.base,
            file: file,
            line: line
        )
    }

    private func request(_ tag: String, _ value: UInt32) -> TypefaceShapingFeature {
        TypefaceShapingFeature(tag: tag, value: value)!
    }

    func testPublicProducersRetainTypedFeaturePayloadsInSourceOrder() throws {
        let base = Font.system(size: 31)

        let lower = try featureProvider(base.lowercaseSmallCaps())
        XCTAssertEqual(lower.base, base)
        XCTAssertEqual(lower.modifier.type, 37)
        XCTAssertEqual(lower.modifier.selector, 1)

        let lowerFalse = try featureProvider(base.lowercaseSmallCaps(false))
        XCTAssertEqual(lowerFalse.base, base)
        XCTAssertEqual(lowerFalse.modifier.type, 37)
        XCTAssertEqual(lowerFalse.modifier.selector, 0)

        let upper = try featureProvider(base.uppercaseSmallCaps())
        XCTAssertEqual(upper.base, base)
        XCTAssertEqual(upper.modifier.type, 38)
        XCTAssertEqual(upper.modifier.selector, 1)

        let upperFalse = try featureProvider(base.uppercaseSmallCaps(false))
        XCTAssertEqual(upperFalse.base, base)
        XCTAssertEqual(upperFalse.modifier.type, 38)
        XCTAssertEqual(upperFalse.modifier.selector, 0)

        let all = try featureProvider(base.smallCaps())
        XCTAssertEqual(all.modifier.type, 38)
        XCTAssertEqual(all.modifier.selector, 1)
        let innerAll = try featureProvider(all.base)
        XCTAssertEqual(innerAll.base, base)
        XCTAssertEqual(innerAll.modifier.type, 37)
        XCTAssertEqual(innerAll.modifier.selector, 1)

        let allFalse = try featureProvider(base.smallCaps(false))
        XCTAssertEqual(allFalse.modifier.type, 38)
        XCTAssertEqual(allFalse.modifier.selector, 0)
        let innerFalse = try featureProvider(allFalse.base)
        XCTAssertEqual(innerFalse.base, base)
        XCTAssertEqual(innerFalse.modifier.type, 37)
        XCTAssertEqual(innerFalse.modifier.selector, 0)

        let reversed = try featureProvider(
            base.uppercaseSmallCaps().lowercaseSmallCaps()
        )
        XCTAssertEqual(reversed.modifier.type, 37)
        XCTAssertEqual(try featureProvider(reversed.base).modifier.type, 38)
    }

    func testFeatureModifierCodingRetainsBothIntegers() throws {
        let font = Font.system(size: 31).lowercaseSmallCaps(false)
        let data = try JSONEncoder().encode(font.codingProxy)
        let archive = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let tag = try XCTUnwrap(archive["tag"] as? [String: Any])
        let modifierTag = try XCTUnwrap(tag["modifier"] as? [String: Any])
        XCTAssertEqual(modifierTag["_0"] as? String, "_featureSettings")
        let value = try XCTUnwrap(archive["value"] as? [String: Any])
        let modifier = try XCTUnwrap(value["modifier"] as? [String: Any])
        XCTAssertEqual(modifier["type"] as? Int, 37)
        XCTAssertEqual(modifier["selector"] as? Int, 0)

        let decoded = try JSONDecoder().decode(
            Font.CodingProxy.self,
            from: data
        ).base
        XCTAssertEqual(decoded, font)
        let decodedProvider = try featureProvider(decoded)
        XCTAssertEqual(decodedProvider.modifier.type, 37)
        XCTAssertEqual(decodedProvider.modifier.selector, 0)
    }

    func testDescriptorFeaturesPreserveRequestsAndRedaction() {
        let ordinary = EnvironmentValues().fontResolutionContext
        let smcp = request("smcp", 1)
        let c2sc = request("c2sc", 1)

        XCTAssertEqual(
            Font.system(size: 31).lowercaseSmallCaps()
                .resolveDescriptor(in: ordinary).shapingFeatures,
            [smcp]
        )
        XCTAssertEqual(
            Font.system(size: 31).uppercaseSmallCaps()
                .resolveDescriptor(in: ordinary).shapingFeatures,
            [c2sc]
        )
        XCTAssertEqual(
            Font.system(size: 31).smallCaps()
                .resolveDescriptor(in: ordinary).shapingFeatures,
            [smcp, c2sc]
        )
        XCTAssertEqual(
            Font.system(size: 31).smallCaps(false)
                .resolveDescriptor(in: ordinary).shapingFeatures,
            [request("smcp", 0), request("c2sc", 0)]
        )
        XCTAssertEqual(
            Font.system(size: 31).lowercaseSmallCaps()
                .lowercaseSmallCaps(false)
                .resolveDescriptor(in: ordinary).shapingFeatures,
            [smcp, request("smcp", 0)]
        )

        var redacted = ordinary
        redacted.shouldRedactContent = true
        for font in [
            Font.system(size: 31).lowercaseSmallCaps(),
            Font.system(size: 31).uppercaseSmallCaps(),
            Font.system(size: 31).smallCaps(),
            Font.system(size: 31).smallCaps(false),
        ] {
            XCTAssertTrue(font.resolveDescriptor(in: redacted).shapingFeatures.isEmpty)
            let resolved = font.resolve(in: redacted)
            XCTAssertFalse(resolved.isLowercaseSmallCaps)
            XCTAssertFalse(resolved.isSmallCaps)
            XCTAssertFalse(resolved.isUppercaseSmallCaps)
        }
    }
}
