import Foundation
import XCTest
import VVD
@testable import VUI

final class FontLeadingTests: XCTestCase {
    private let variants: [VUI.Font.Leading] = [.standard, .tight, .loose]

    private func resource(_ name: String = "Roboto/Roboto-VariableFont_wdth,wght.ttf") -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Sources/VUI/Resources/Fonts").appendingPathComponent(name)
    }

    private func face(scale: CGFloat = 1, referenceMetrics: Bool = false) throws -> Typeface {
        var data = try Data(contentsOf: resource())
        if referenceMetrics {
            func u16(_ p: Int) -> Int { Int(data[p]) << 8 | Int(data[p + 1]) }
            func u32(_ p: Int) -> Int { u16(p) << 16 | u16(p + 2) }
            func put(_ p: Int, _ value: Int) {
                data[p] = UInt8(truncatingIfNeeded: value >> 8)
                data[p + 1] = UInt8(truncatingIfNeeded: value)
            }
            for index in 0..<u16(4) {
                let p = 12 + index * 16
                let tag = String(decoding: data[p..<p + 4], as: UTF8.self)
                let offset = u32(p + 8)
                if tag == "hhea" {
                    put(offset + 4, 1980); put(offset + 6, -432); put(offset + 8, 0)
                } else if tag == "OS/2" {
                    put(offset + 62, u16(offset + 62) & ~128)
                }
            }
        }
        let font = try XCTUnwrap(VVD.Font(data: data))
        let raster = try XCTUnwrap(VVD.Font(data: data))
        font.setPointSize(13, dpi: (72, 72))
        raster.setPointSize(13, dpi: (UInt32(72 * scale), UInt32(72 * scale)))
        return VectorTypeface(font: raster, layoutFont: font, renderScale: scale)
    }

    private func request(_ font: VUI.Font, language: String = "en", ratio: Double? = nil) -> FontResource {
        let context = EnvironmentValues().fontResolutionContext
        var modifiers: [AnyFontModifier] = [.dynamic(LanguageFontModifier(identifier: language))]
        if let ratio { modifiers.append(.dynamic(LanguageAwareLineHeightRatioFontModifier(ratio: ratio))) }
        return font.platformFont(in: context, modifiers: modifiers)
    }

    private func text(_ string: String, font: VUI.Font, face: Typeface, scale: CGFloat = 1,
                      spacing: CGFloat = 0, language: String = "en", ratio: Double? = nil) -> GraphicsContext.ResolvedText {
        var attributes = _ResolvedTextRunAttributes()
        attributes.fontResource = request(font, language: language, ratio: ratio)
        var paragraph = TextParagraphStyle()
        paragraph.lineSpacing = spacing
        attributes.paragraphStyle = paragraph
        return GraphicsContext.ResolvedText(runs: [.styledText([face], string, .init(), attributes)],
            scaleFactor: scale, displayScale: 2, preferredLanguages: ["en"])
    }

    // ASSERTIONS fontLeadingDescriptorFlagsAndCodingObserved
    // ASSERTIONS fontLeadingFixedFaceNoEffectObserved
    func testTypedModifierCodingCopiesAndUnsupportedResources() throws {
        let context = EnvironmentValues().fontResolutionContext
        for (leading, proxy): (VUI.Font.Leading, UInt32) in [(.standard, 0), (.tight, 32768), (.loose, 65536)] {
            let base = VUI.Font.body
            let modified = base.leading(leading)
            let box = try XCTUnwrap(modified.provider as? FontBox<VUI.Font.ModifierProvider<VUI.Font.LeadingModifier>>)
            XCTAssertTrue(box.base.base.provider === base.provider)
            XCTAssertNotEqual(base, modified)
            XCTAssertFalse(modified.provider === base.leading(leading).provider)
            XCTAssertEqual(modified, base.leading(leading))
            XCTAssertEqual(box.base.modifier.codingProxy, proxy)
            XCTAssertEqual(try JSONDecoder().decode(VUI.Font.CodingProxy.self,
                from: JSONEncoder().encode(modified.codingProxy)).base, modified)
            var traits = VUI.Font.ResolvedTraits(pointSize: 17, weight: 0.23)
            box.base.modifier.modify(traits: &traits)
            XCTAssertEqual(traits.pointSize, 17)
            XCTAssertEqual(traits.weight, 0.23)
            XCTAssertNil(traits.width)
            for font in [VUI.Font.system(size: 13), .custom("Roboto-Regular", fixedSize: 13),
                         .custom("Roboto-Regular", size: 13, relativeTo: .body),
                         .file(resource(), size: 13), .data(try Data(contentsOf: resource()), size: 13)] {
                XCTAssertEqual(font.leading(leading).resolve(in: context).leading, .standard)
                XCTAssertNil(font.leading(leading).resolve(in: context).resource.stylePolicy)
            }
        }
        for value: UInt32 in [1, 3, 32769, 65537, 98304, .max] {
            XCTAssertEqual(VUI.Font.LeadingModifier.unwrap(codingProxy: value).leading, .standard)
        }
    }

    // ASSERTIONS fontSystemStylePolicyDesignWeightObserved
    // ASSERTIONS fontSystemStylePolicyCopyObserved
    // ASSERTIONS fontLeadingStyleGapDerivationObserved
    func testStyleTargetsPreservePhysicalMetricsAndResolvedCopies() throws {
        let face = try face()
        let original = face.designMetrics
        let environment = EnvironmentValues()
        var context = environment.fontResolutionContext
        // Keep role-target controls independent of the host's preferred languages.
        context.fontModifiers = [.dynamic(LanguageFontModifier(identifier: "en"))]
        let targets: [VUI.Font.TextStyle: CGFloat] = [.largeTitle: 32, .title: 26, .title2: 22,
            .title3: 20, .headline: 16, .body: 16, .callout: 15, .subheadline: 14,
            .footnote: 13, .caption: 13, .caption2: 13]
        let weights: [VUI.Font.Weight?] = [nil, .ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        for style in VUI.Font.TextStyle.allCases {
            for design: VUI.Font.Design in [.default, .serif, .rounded, .monospaced] {
                for weight in weights {
                    for leading in variants {
                        let font = VUI.Font.system(style, design: design, weight: weight).leading(leading)
                        let selected: VUI.Font.Leading = leading == .loose && [.subheadline, .footnote].contains(style) ? .standard : leading
                        let expected = targets[style]! + (selected == .tight ? -2 : selected == .loose ? 2 : 0)
                        for copy in [font, font.resolved(in: environment), font.resolved(in: environment).resolved(in: environment)] {
                            let resolved = copy.resolve(in: context)
                            XCTAssertEqual(resolved.leading, selected)
                            let value = try XCTUnwrap(resolved.resource.resolvedMetrics(for: face, scaleFactor: 1))
                            XCTAssertEqual(value.ascender - value.descender + value.leading, expected, accuracy: 1e-10)
                            XCTAssertEqual(value.ascender, 1900 * resolved.pointSize / 2048, accuracy: 1e-10)
                            XCTAssertEqual(value.descender, -500 * resolved.pointSize / 2048, accuracy: 1e-10)
                        }
                    }
                }
            }
        }
        XCTAssertEqual(face.designMetrics, original)
        let first = request(.body.leading(.tight))
        XCTAssertTrue(first === request(.body.leading(.tight)))
        XCTAssertNotEqual(first, request(.body.leading(.loose)))
        XCTAssertEqual(request(.body.leading(.tight).leading(.standard)).stylePolicy?.leading, .standard)
        XCTAssertEqual(request(.body.leading(.loose).weight(.heavy).italic().monospacedDigit()).stylePolicy?.leading, .loose)
    }

    // ASSERTIONS textComponentFontLanguageAndRatioObserved
    // ASSERTIONS textComponentFontStyleTargetSourceObserved
    func testLanguageMetricsKeepRatioOneAndOutsetAdjustmentSeparate() throws {
        let face = try face(referenceMetrics: true)
        let cases: [(VUI.Font.Leading, String, Double?, CGFloat, CGFloat, CGFloat)] = [
            (.standard, "en", nil, 12.568359375, 2.7421875, 16),
            (.standard, "ur", nil, 15.70948889287945, 4.851057982120547, 21.25),
            (.standard, "ur", 0, 12.568359375, 2.7421875, 16),
            (.standard, "ur", 0.5, 13.912656875, 4.882904, 19.485014),
            (.loose, "ar", nil, 14.421886375, 6.4090195, 23.520359)
        ]
        for (leading, language, ratio, ascent, descent, height) in cases {
            let result = text("Ågj", font: .body.leading(leading), face: face, language: language, ratio: ratio)
            let metrics = try XCTUnwrap(result.maximumFontMetrics)
            XCTAssertEqual(metrics.ascender, ascent, accuracy: 1e-8)
            XCTAssertEqual(-metrics.descender, descent, accuracy: 1e-8)
            XCTAssertEqual(metrics.ascender - metrics.descender + metrics.leading, height, accuracy: 1e-8)
            if language != "en" {
                XCTAssertEqual(metrics.outsets.top, 1.24186309, accuracy: 1e-8)
                XCTAssertEqual(metrics.outsets.bottom, 2.45677744, accuracy: 1e-8)
            }
        }
        for leading in variants {
            let metrics = try XCTUnwrap(request(.body.leading(leading), language: "ur")
                .resolvedMetrics(for: face, scaleFactor: 1))
            XCTAssertEqual(metrics.ascender - metrics.descender + metrics.leading, 21.25, accuracy: 1e-8)
        }
    }

    // ASSERTIONS fontStyleLinePlacementObserved
    // ASSERTIONS fontLeadingNativeMetricConsumerObserved
    // ASSERTIONS fontLeadingSpacingInteractionObserved
    func testNativeVerticalFixturesReachSharedTextPlacement() throws {
        let cases: [(String, VUI.Font.Leading, CGFloat, [CGFloat], [CGFloat], [CGFloat])] = [
            ("Hg\nHg\nHg", .tight, 0, [13, 27.689453125, 41.689453125], [13, 11.689453125, 11.689453125], [3, 2.310546875, 2.310546875]),
            ("Hg\nHg\nHg", .loose, 0, [13, 31.689453125, 49.689453125], [13, 13, 13], [3, 2.310546875, 2.310546875]),
            ("Hg\nHg\nHg", .loose, 7, [13, 36, 58.310546875], [13, 13, 13], [3, 2.310546875, 2.310546875]),
            ("Hg\n\nHg", .loose, 0, [13, 29, 49.689453125], [13, 13, 13], [3, 5, 2.310546875]),
            ("Hg\n\nHg", .tight, 7, [13, 27.689453125, 55.689453125], [13, 11.689453125, 11.689453125], [3, 9.310546875, 2.310546875]),
            ("\nHg\nHg", .loose, 7, [13, 36, 58.310546875], [13, 13, 13], [3, 2.310546875, 2.310546875]),
            ("Hg\nHg\n", .tight, 0, [13, 27.689453125, 41.689453125], [13, 11.689453125, 11.689453125], [3, 2.310546875, 2.310546875])
        ]
        for scale: CGFloat in [1, 1.5, 2] {
            let face = try face(scale: scale, referenceMetrics: true)
            for (string, leading, spacing, baselines, ascents, descents) in cases {
                let source = text(string, font: .body.leading(leading), face: face, scale: scale, spacing: spacing)
                let lines = source.makeGlyphs()
                let layout = source.makeLayout(in: .init(width: 400, height: 400), layoutDirection: .leftToRight)
                XCTAssertEqual(lines.count, baselines.count)
                XCTAssertEqual(layout.count, baselines.count)
                for i in lines.indices {
                    XCTAssertEqual(lines[i].baseline / scale, baselines[i], accuracy: 1e-10)
                    XCTAssertEqual(lines[i].ascender / scale, ascents[i], accuracy: 1e-10)
                    XCTAssertEqual(-lines[i].descender / scale, descents[i], accuracy: 1e-10)
                    XCTAssertEqual(layout[i].origin.y, baselines[i], accuracy: 1e-10)
                    XCTAssertEqual(layout[i].typographicBounds.leading, 0)
                }
                XCTAssertEqual(source.measure().height, ceil((baselines.last! + descents.last!) * 2) / 2)
            }
        }
    }

    // ASSERTIONS fontLeadingMixedRunAggregationObserved
    // ASSERTIONS fontStyleLinePlacementObserved
    func testMixedParagraphStartUsesItsFirstAttribute() throws {
        let system = try face(referenceMetrics: true)
        let ordinary = try face()
        for (reversed, expected): (Bool, [CGFloat]) in [(false, [13, 31.689453125, 49.689453125]), (true, [13, 29, 47])] {
            let style = text("Hg", font: .body.leading(.loose), face: system)
            let file = text("Hg", font: .file(resource(), size: 13), face: ordinary)
            var runs: [GraphicsContext.ResolvedText.Run] = []
            for i in 0..<3 {
                let first = reversed ? file : style
                let second = reversed ? style : file
                runs.append(first.runs[0])
                guard case let .styledText(faces, _, attributes, values) = second.runs[0] else { return XCTFail() }
                runs.append(.styledText(faces, i == 2 ? "Hg" : "Hg\n", attributes, values))
            }
            let source = GraphicsContext.ResolvedText(runs: runs, scaleFactor: 1)
            let lines = source.makeGlyphs()
            XCTAssertEqual(lines.count, 3)
            for i in lines.indices { XCTAssertEqual(lines[i].baseline, expected[i], accuracy: 1e-10) }
        }
    }

    // ASSERTIONS fontStyleLinePlacementObserved
    // ASSERTIONS fontLeadingSignedMetricsAndMultilineObserved
    func testWrapAndTruncationPreserveParagraphContinuationMetricFlags() throws {
        for scale: CGFloat in [1, 2] {
            let face = try face(scale: scale, referenceMetrics: true)
            for (leading, expected): (VUI.Font.Leading, [CGFloat]) in [(.tight, [13, 27, 41]), (.loose, [13, 31, 49])] {
                let source = text("Hg Hg Hg Hg Hg Hg", font: .body.leading(leading), face: face, scale: scale)
                let lines = source.makeGlyphs(maxWidth: Int(52 * scale))
                XCTAssertEqual(lines.count, 3)
                guard lines.count == 3 else { continue }
                for i in lines.indices {
                    XCTAssertEqual(lines[i].baseline / scale, expected[i], accuracy: 1e-8)
                    XCTAssertEqual(-lines[i].descender / scale, i == 2 ? 3 : 2.310546875, accuracy: 1e-8)
                }
                for mode: Text.TruncationMode in [.head, .middle, .tail] {
                    let clipped = source.makeGlyphs(maxWidth: Int(52 * scale), lineLimit: 2, truncationMode: mode)
                    XCTAssertEqual(clipped.count, 2)
                    let last = try XCTUnwrap(clipped.last)
                    XCTAssertTrue(last.isTruncated)
                    XCTAssertEqual(last.baseline / scale, expected[1], accuracy: 1e-8)
                    XCTAssertEqual(-last.descender / scale, 2.310546875, accuracy: 1e-8)
                    XCTAssertEqual(last.glyphs.filter(\.isTruncationToken).count, 1)
                }
            }
        }
    }

    // ASSERTIONS fontStyleLinePlacementObserved
    func testFractionalMeasuredHeightRemainsAValidLayoutProposal() throws {
        for scale: CGFloat in [1, 1.5, 2] {
            let face = try face(scale: scale)
            for leading in variants {
                let source = text("Hg\nHg\nHg", font: .body.leading(leading), face: face, scale: scale)
                let measured = source.measure()
                XCTAssertEqual(source.measure(in: measured), measured)
                XCTAssertEqual(source.measure(maxWidth: measured.width, maxHeight: measured.height), measured)
                let layout = source.makeLayout(in: measured, layoutDirection: .leftToRight)
                XCTAssertEqual(layout.count, 3)
                XCTAssertEqual(source.glyphAtoms(in: measured).count, 6)
                let last = try XCTUnwrap(source.makeGlyphs().last)
                XCTAssertEqual(source.lastBaseline(in: measured), last.baseline / scale, accuracy: 1e-8)
                XCTAssertEqual(source.makeGlyphs(maximumHeight: last.maxY).count, 3)
                XCTAssertEqual(source.makeGlyphs(maximumHeight: last.maxY.nextDown).count, 2)
            }
        }
    }
}
