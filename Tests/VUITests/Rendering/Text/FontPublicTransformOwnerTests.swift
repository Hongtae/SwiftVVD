import Foundation
import XCTest
@testable import VUI

// ASSERTIONS fontPublicTransforms27Observed

final class FontPublicTransformOwnerTests: XCTestCase {
    private func archive(_ font: Font) throws -> [String: Any] {
        let data = try JSONEncoder().encode(font.codingProxy)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    func testPublicProducersUseDistinctTypedProviders() throws {
        XCTAssertNotNil(Font.default.provider as? FontBox<Font.DefaultProvider>)

        let base = Font.system(size: 17.125, weight: .light)
        let point = try XCTUnwrap(
            base.pointSize(19.125).provider
                as? FontBox<Font.ModifierProvider<Font.PointSizeModifier>>
        )
        XCTAssertEqual(point.base.modifier.pointSize, 19.125)
        XCTAssertEqual(point.base.base, base)

        let scale = try XCTUnwrap(
            base.scaled(by: 1.1).provider
                as? FontBox<Font.ModifierProvider<Font.ScalePointSizeModifier>>
        )
        XCTAssertEqual(scale.base.modifier.scaleFactor, 1.1)
        XCTAssertEqual(scale.base.base, base)

        let nested = try XCTUnwrap(
            base.scaled(by: 1.1).pointSize(19.125).provider
                as? FontBox<Font.ModifierProvider<Font.PointSizeModifier>>
        )
        XCTAssertNotNil(
            nested.base.base.provider
                as? FontBox<Font.ModifierProvider<Font.ScalePointSizeModifier>>
        )
    }

    func testDescriptorMutationPreservesRawAndRealizedSizeBoundaries() throws {
        let context = EnvironmentValues().fontResolutionContext
        let original = FontDescriptor(
            source: .system(.default, .light, false),
            pointSize: 17.125
        )

        var scaleOne = original
        Font.ScalePointSizeModifier(scaleFactor: 1)
            .modify(descriptor: &scaleOne, in: context)
        XCTAssertTrue(scaleOne === original)

        var scale = original
        Font.ScalePointSizeModifier(scaleFactor: 1.000_000_000_1)
            .modify(descriptor: &scale, in: context)
        XCTAssertFalse(scale === original)
        XCTAssertEqual(scale.pointSize, 17.25)

        var point = original
        Font.PointSizeModifier(pointSize: -3)
            .modify(descriptor: &point, in: context)
        XCTAssertEqual(point.pointSize, -3)
        let resource = FontResource(descriptor: point, in: context)
        XCTAssertEqual(resource.pointSize, 12)
        XCTAssertEqual(
            try XCTUnwrap(resource.provider as? SystemFontProvider).pointSize,
            12
        )
    }

    func testCodingUsesCurrentDynamicModifierTags() throws {
        let base = Font.system(size: 17.125)
        let point = try archive(base.pointSize(19.125))
        let scale = try archive(base.scaled(by: 1.1))

        func modifierName(_ archive: [String: Any]) throws -> String {
            let tag = try XCTUnwrap(archive["tag"] as? [String: Any])
            let modifier = try XCTUnwrap(tag["modifier"] as? [String: Any])
            return try XCTUnwrap(modifier["_0"] as? String)
        }
        XCTAssertEqual(try modifierName(point), "setPointSize")
        XCTAssertEqual(try modifierName(scale), "scalePointSize")

        let pointValue = try XCTUnwrap(point["value"] as? [String: Any])
        let scaleValue = try XCTUnwrap(scale["value"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(pointValue["modifier"] as? Double), 19.125)
        XCTAssertEqual(try XCTUnwrap(scaleValue["modifier"] as? Double), 1.1)

        for archive in [point, scale] {
            let data = try JSONSerialization.data(withJSONObject: archive)
            let decoded = try JSONDecoder().decode(
                Font.CodingProxy.self,
                from: data
            ).base
            XCTAssertEqual(try self.archive(decoded) as NSDictionary,
                           archive as NSDictionary)
        }
    }
}
