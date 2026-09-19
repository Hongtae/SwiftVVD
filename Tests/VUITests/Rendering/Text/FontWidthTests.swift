import Foundation
import VVD
import XCTest
@testable import VUI

final class FontWidthTests: XCTestCase {
    private let widthTag: UInt32 = 0x7764_7468

    // ASSERTIONS textFontWidthRouting27Observed
    func testTextWidthKeepsTypedOptionalOwnershipAndEquality() throws {
        let text = Text(verbatim: "Hg").fontWidth(nil)
        guard case let .anyTextModifier(owner) = text.modifiers.first else { return XCTFail() }
        let width = try XCTUnwrap(owner as? TextWidthModifier)
        XCTAssertNil(width.width)
        XCTAssertFalse(width.isEqual(to: MonospacedDigitTextModifier()))
        XCTAssertEqual(text, Text(verbatim: "Hg").fontWidth(nil))
        XCTAssertNotEqual(text, Text(verbatim: "Hg").fontWidth(.standard))
        XCTAssertEqual(Text(verbatim: "Hg").fontWidth(.condensed), Text(verbatim: "Hg").fontWidth(.condensed))
        XCTAssertNotEqual(Text(verbatim: "Hg").fontWidth(.init(.nan)), Text(verbatim: "Hg").fontWidth(.init(.nan)))
        let repeated = text.fontWidth(.init(2))
        XCTAssertEqual(repeated.modifiers.count, 2)
        guard case let .anyTextModifier(last) = repeated.modifiers.last else { return XCTFail() }
        XCTAssertEqual((last as? TextWidthModifier)?.width, 2)
        var first = Hasher(), second = Hasher()
        width.hashResolution(into: &first)
        TextWidthModifier(width: nil).hashResolution(into: &second)
        XCTAssertEqual(first.finalize(), second.finalize())
    }

    // ASSERTIONS viewFontWidthEnvironment27Observed
    func testViewWidthAppendsWithoutDeduplicationAndNilRemovesOnlyWidths() throws {
        typealias Modified = ModifiedContent<EmptyView, _EnvironmentKeyTransformModifier<[AnyFontModifier]>>
        let some = try XCTUnwrap(EmptyView().fontWidth(.condensed) as? Modified)
        let none = try XCTUnwrap(EmptyView().fontWidth(nil) as? Modified)
        XCTAssertEqual(some.modifier.keyPath, \EnvironmentValues.fontModifiers)
        let italic = AnyFontModifier.static(VUI.Font.ItalicModifier.self)
        let digit = AnyFontModifier.static(VUI.Font.MonospacedDigitModifier.self)
        var modifiers: [AnyFontModifier] = [italic, .dynamic(VUI.Font.WidthModifier(width: 0.2)), digit]
        some.modifier.transform(&modifiers)
        some.modifier.transform(&modifiers)
        XCTAssertEqual(modifiers.count, 5)
        XCTAssertEqual(modifiers.compactMap { ($0 as? AnyDynamicFontModifier<VUI.Font.WidthModifier>)?.modifier.width }, [0.2, -0.2, -0.2])
        none.modifier.transform(&modifiers)
        XCTAssertEqual(modifiers, [italic, digit])
    }

    private func provider(_ font: VUI.Font, environment: EnvironmentValues = .init()) throws -> BundledFontProvider {
        try XCTUnwrap(font.resolved(in: environment).typefaceProvider as? BundledFontProvider)
    }

    // ASSERTIONS fontWidthValuesAndWrapperObserved
    func testWidthValuesRemainMutableAndUnclamped() {
        XCTAssertEqual([VUI.Font.Width.compressed, .condensed, .standard, .expanded].map(\.value), [-0.3, -0.2, 0, 0.2])
        var value = VUI.Font.Width(-2)
        XCTAssertEqual(value.value, -2)
        value.value = 2
        XCTAssertEqual(value, VUI.Font.Width(2))
        XCTAssertEqual(value.hashValue, VUI.Font.Width(2).hashValue)
        XCTAssertEqual(VUI.Font.Width(.infinity), VUI.Font.Width(.infinity))
        let nan = VUI.Font.Width(.nan)
        XCTAssertFalse(nan == nan)
    }

    // ASSERTIONS fontWidthValuesAndWrapperObserved
    // ASSERTIONS fontModifierTagsAndCodingObserved
    func testWidthKeepsScalarCodingAndOrderedProviderBoxes() throws {
        let base = VUI.Font.system(size: 17)
        let font = base.width(.condensed)
        let box = try XCTUnwrap(font.provider as? FontBox<VUI.Font.ModifierProvider<VUI.Font.WidthModifier>>)
        XCTAssertTrue(box.base.base.provider === base.provider)
        XCTAssertEqual(box.base.modifier.width, -0.2)
        XCTAssertFalse(base.width(.standard).provider === base.provider)
        XCTAssertNotEqual(base, base.width(.standard))
        XCTAssertNotEqual(font, font.width(.condensed))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(font.codingProxy)
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
            #"{"tag":{"modifier":{"_0":"width"}},"value":{"font":{"tag":{"system":{}},"value":{"design":{},"size":17,"weight":{}}},"modifier":-0.2}}"#)
        XCTAssertEqual(try JSONDecoder().decode(VUI.Font.CodingProxy.self, from: data).base, font)
        XCTAssertEqual(try encoder.encode(box.base.modifier.codingProxy), Data("-0.2".utf8))
    }

    // ASSERTIONS fontWidthDescriptorRequestsObserved
    // ASSERTIONS fontModifierDescriptorBranchesObserved
    func testDirectTraitMutationDoesNotChangeProviderTraitResolution() {
        var traits = VUI.Font.ResolvedTraits(pointSize: 17.125, weight: 0.23)
        VUI.Font.WidthModifier(width: -0.2).modify(traits: &traits)
        XCTAssertEqual(traits.width, -0.2)
        XCTAssertEqual(traits.pointSize, 17.125)
        XCTAssertEqual(traits.weight, 0.23)
        let context = EnvironmentValues().fontResolutionContext
        for font in [VUI.Font.system(size: 17.125), .custom("Roboto-Regular", fixedSize: 17.125)] {
            let resolved = font.width(.condensed).resolveTraits(in: context)
            XCTAssertNil(resolved.width)
            XCTAssertEqual(resolved.pointSize, 17.125)
            XCTAssertEqual(resolved.weight, 0)
        }
    }

    // ASSERTIONS fontWidthNamedInstanceSelectionObserved
    func testNamedWidthSelectsAvailableInstancesWithoutInterpolatingCoordinates() throws {
        let values: [CGFloat] = [-2, -1, -0.5, -0.3, -0.2, -0.15, -0.1, -0.05, 0, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2]
        for name in ["Roboto-Regular", "Roboto-CondensedRegular"] {
            for value in values {
                let resolved = try provider(.custom(name, fixedSize: 17.125).width(.init(value)))
                XCTAssertEqual(resolved.variations.first { $0.tag == widthTag }?.value, value < -0.1 ? 75 : 100,
                               "\(name) width \(value)")
                XCTAssertEqual(resolved.resource.url.lastPathComponent, "Roboto-VariableFont_wdth,wght.ttf")
                XCTAssertFalse(resolved.appliesSyntheticWeight)
                XCTAssertNotNil(resolved.instanceIndex)
            }
        }
    }

    // ASSERTIONS fontWidthNamedInstanceSelectionObserved
    func testWidthMidpointUsesFloatCandidateTraitsAndStableTieOrder() throws {
        let midpoint = CGFloat(Float(-0.2)) / 2
        for (value, coordinate) in [(midpoint.nextDown, CGFloat(75)), (midpoint, 100), (midpoint.nextUp, 100)] {
            let resolved = try provider(.custom("Roboto-Regular", fixedSize: 17).width(.init(value)))
            XCTAssertEqual(resolved.variations.first { $0.tag == widthTag }?.value, coordinate)
        }
        for value: CGFloat in [-.infinity, .infinity, .nan] {
            let resolved = try provider(.custom("Roboto-Regular", fixedSize: 17).width(.init(value)))
            XCTAssertEqual(resolved.variations.first { $0.tag == widthTag }?.value, 100)
        }
    }

    // ASSERTIONS fontWidthRetainedRequestOrderObserved
    func testWidthWeightAndItalicOrdersRetainTheCorrectRequestedTraits() throws {
        let base = VUI.Font.custom("Roboto-Regular", fixedSize: 17.125)
        let context = EnvironmentValues().fontResolutionContext
        let a = base.width(.condensed).italic().width(.standard).resolveDescriptor(in: context)
        let b = base.italic().width(.condensed).width(.standard).resolveDescriptor(in: context)
        guard case let .family(_, _, first) = a.source, case let .family(_, _, second) = b.source else {
            return XCTFail("Width must replace the exact selection with a retained family request.")
        }
        XCTAssertEqual(first.width, 0)
        XCTAssertEqual(first.slant, 0)
        XCTAssertEqual(second.width, 0)
        XCTAssertEqual(second.slant, CGFloat(Float(bitPattern: 0x3d8e38e3)))
        let upright = try XCTUnwrap(a.typefaceProvider(in: .init()) as? BundledFontProvider)
        let italic = try XCTUnwrap(b.typefaceProvider(in: .init()) as? BundledFontProvider)
        XCTAssertEqual(upright.resource.url.lastPathComponent, "Roboto-VariableFont_wdth,wght.ttf")
        XCTAssertEqual(italic.resource.url.lastPathComponent, "Roboto-Italic-VariableFont_wdth,wght.ttf")
        for font in [base.width(.condensed).weight(.heavy), base.weight(.heavy).width(.condensed)] {
            let resolved = try provider(font)
            XCTAssertEqual(resolved.variations.first { $0.tag == widthTag }?.value, 75)
            XCTAssertEqual(resolved.variations.first { $0.tag == 0x7767_6874 }?.value, 800)
        }
    }

    // ASSERTIONS fontWidthUnsupportedFaceObserved
    func testFontsWithoutWidthVariantsKeepTheirSourceAndCoordinates() throws {
        for name in ["RobotoMono-Regular", "NanumSquareNeo-Variable", "LastResort-Regular"] {
            let base = VUI.Font.custom(name, fixedSize: 17.125)
            let original = try provider(base)
            for width in [VUI.Font.Width.compressed, .expanded] {
                let resolved = try provider(base.width(width))
                XCTAssertEqual(resolved.resource, original.resource)
                XCTAssertEqual(resolved.instanceIndex, original.instanceIndex)
                XCTAssertEqual(resolved.variations, original.variations)
            }
        }
    }

    // ASSERTIONS fontWidthNamedInstanceSelectionObserved
    // ASSERTIONS fontWidthUnsupportedFaceObserved
    func testRealGlyphAdvancesAndCoordinatesUseTheSelectedFaceAtBothScales() throws {
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        let context = WidthTestAppContext()
        for dpi: UInt32 in [72, 144] {
            for (name, width, advance) in [
                ("Roboto-Regular", VUI.Font.Width.standard, CGFloat(12.21661376953125)),
                ("Roboto-Regular", .condensed, 10.6195068359375),
                ("RobotoMono-Regular", .condensed, 10.27667236328125),
                ("RobotoMono-Regular", .expanded, 10.27667236328125)
            ] {
                let resolved = try provider(.custom(name, fixedSize: 17.125).width(width), environment: environment)
                let face = try XCTUnwrap(resolved.makeTypeface(context, dpi: dpi) as? VectorTypeface)
                let shaped = try XCTUnwrap(face.shape("H", direction: nil, language: nil, features: []))
                let glyph = try XCTUnwrap(shaped.glyphs.first)
                XCTAssertEqual(glyph.advance.width / (CGFloat(dpi) / 72), advance, accuracy: 1.0 / 64.0)
                if name == "Roboto-Regular" {
                    XCTAssertEqual(face.font.variationCoordinates[widthTag], width == .condensed ? 75 : 100)
                }
                guard case .vector = face.glyph(for: "H") else { return XCTFail("Expected an outline glyph.") }
            }
        }
    }

    func testConfiguredSystemWidthKeepsWeightPolicyAndRenderingMode() throws {
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        let context = WidthTestAppContext()
        let base = VUI.Font.system(size: 17.125, weight: .medium)
        for font in [base.width(.condensed), base.width(.condensed).italic()] {
            let system = try XCTUnwrap(font.resolved(in: environment).typefaceProvider as? SystemFontProvider)
            XCTAssertEqual(system.width, .condensed)
            XCTAssertEqual(system.weight, .medium)
            let face = try XCTUnwrap(system.makeTypeface(context, dpi: 144) as? VectorTypeface)
            XCTAssertEqual(face.font.variationCoordinates[widthTag], 75)
            XCTAssertEqual(face.font.variationCoordinates[0x7767_6874], 530)
        }
        let regular = base.resolved(in: environment)
        let condensed = base.width(.condensed).resolved(in: environment)
        XCTAssertNotEqual(regular, condensed)
        let changed = base.width(.condensed).weight(.heavy).monospacedDigit().resolved(in: environment)
        let system = try XCTUnwrap(changed.typefaceProvider as? SystemFontProvider)
        XCTAssertEqual(system.width, .condensed)
        XCTAssertEqual(system.weight, .heavy)
        XCTAssertEqual(changed.typefaceFeatures, VUI.Font.MonospacedDigitModifier.shapingFeatures)
    }
}

private final class WidthTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    private var resources: [URL: any DataProtocol] = [:]

    func resourceData(forURL url: URL) -> (any DataProtocol)? { resources[url] }
    func setResource(data: (any DataProtocol)?, forURL url: URL) { resources[url] = data }
}
