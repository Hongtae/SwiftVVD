import Foundation
import XCTest
import VVD
@testable import VUI

final class FontOutsetTests: XCTestCase {
    // ASSERTIONS textFontVerticalOutsets27Observed
    func testOrdinaryFontMetricsUnionVerticalOutsetsBeforePixelRounding() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        for rendering: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            for contentScale: CGFloat in [1, 2] {
                for displayScale: CGFloat in [1, 2] {
                    for size: CGFloat in [13, 23, 31] {
                        for string in ["Hg", "A\nB", "Ågj", "A\u{2028}B"] {
                            var environment = EnvironmentValues()
                            environment.defaultFontRenderingMode = rendering
                            environment._contentScaleFactor = contentScale
                            environment.displayScale = displayScale
                            let source = try XCTUnwrap(Text(verbatim: string).font(.file(resource(), size: size))
                                ._resolve(context: GraphTextResolutionContext(environment: environment,
                                    sceneResources: SceneResources()), referenceDate: Date(timeIntervalSince1970: 0)))
                            let ordinary = ResolvedStyledText.StringDrawing(resolvedText: source)
                            let manager = ResolvedStyledText.TextLayoutManager(resolvedText: source)
                            let horizontal = string == "Ågj" || string.contains("\u{2028}")
                            let expected = EdgeInsets(top: 0.142579 * size,
                                leading: horizontal ? 0.186524 * size : 0,
                                bottom: 0.282064 * size, trailing: horizontal ? 0.105001 * size : 0)
                            for owner: ResolvedStyledText in [ordinary, manager] {
                                XCTAssertEqual(owner.maxFontMetrics.outsets.top, expected.top, accuracy: 1e-12)
                                XCTAssertEqual(owner.maxFontMetrics.outsets.leading, expected.leading, accuracy: 1e-12)
                                XCTAssertEqual(owner.maxFontMetrics.outsets.bottom, expected.bottom, accuracy: 1e-12)
                                XCTAssertEqual(owner.maxFontMetrics.outsets.trailing, expected.trailing, accuracy: 1e-12)
                                XCTAssertEqual(owner.drawingMargins, EdgeInsets(
                                    top: ceil(expected.top * displayScale) / displayScale,
                                    leading: ceil(expected.leading * displayScale) / displayScale,
                                    bottom: ceil(expected.bottom * displayScale) / displayScale,
                                    trailing: ceil(expected.trailing * displayScale) / displayScale))
                                XCTAssertEqual(owner.layoutMargins, .init())
                            }
                        }
                    }
                }
            }
        }
    }

    private func resource(_ name: String = "Roboto/Roboto-VariableFont_wdth,wght.ttf") -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Sources/VUI/Resources/Fonts").appendingPathComponent(name)
    }

    private func font(_ name: String = "Roboto/Roboto-VariableFont_wdth,wght.ttf", size: CGFloat = 13) throws -> VVD.Font {
        let font = try XCTUnwrap(VVD.Font(path: resource(name).path))
        font.setPointSize(size, dpi: (72, 72))
        return font
    }

    private func run(_ text: String, font: VVD.Font, size: CGFloat, scale: CGFloat = 1) -> ResolvedTextSource.Run {
        let face = VectorTypeface(font: font, layoutFont: font, renderScale: scale)
        let resource = VUI.Font.file(resource(), size: size).platformFont(in: EnvironmentValues().fontResolutionContext)
        var attributes = _ResolvedTextRunAttributes()
        attributes.fontResource = resource
        return .styledText([face], text, .init(), attributes)
    }

    private func fixture(_ edges: [Double]) throws -> FontOutsetData {
        let object: [String: Any] = ["version": 2, "scalarRanges": [[197, 197]],
            "layoutScalarRanges": [[197, 197]], "referenceWeights": [0],
            "scriptGroups": [:],
            "referenceRows": [["normal": edges, "extended": edges]]]
        return try JSONDecoder().decode(FontOutsetData.self, from: JSONSerialization.data(withJSONObject: object))
    }

    // ASSERTIONS textOutsetDefaultDataSourceObserved
    // ASSERTIONS textAutomaticMargins27CharacterSetsObserved
    // ASSERTIONS textAutomaticMargins27ReferenceRowsObserved
    func testBundledMembershipAndReferencesNeedNoFontNameRegistry() throws {
        let data = try XCTUnwrap(BundledFontCatalog.shared.outsetData)
        XCTAssertEqual(data.referenceRows.count, 9)
        XCTAssertEqual(data.scalarRanges.count, 1586)
        XCTAssertEqual(data.scalarRanges.reduce(0) { $0 + Int($1.upperBound - $1.lowerBound + 1) }, 8030)
        XCTAssertEqual(data.layoutScalarRanges.count, 1450)
        XCTAssertEqual(data.layoutScalarRanges.reduce(0) { $0 + Int($1.upperBound - $1.lowerBound + 1) }, 6594)
        for scalar: Unicode.Scalar in ["Å", "\u{301}", "\u{212b}", "😀"] { XCTAssertTrue(data.contains(scalar)) }
        for scalar: Unicode.Scalar in ["H", "g", "漢", "한", "\u{fffc}"] { XCTAssertFalse(data.contains(scalar)) }
        for scalar: Unicode.Scalar in ["\u{030d}", "\u{0a76}", "\u{1df5}", "\u{a8fb}"] {
            XCTAssertTrue(data.contains(scalar))
            XCTAssertTrue(data.containsForLayout(scalar))
        }
        for scalar: Unicode.Scalar in ["😀", "\u{fe0f}", "\u{1d70}"] { XCTAssertFalse(data.containsForLayout(scalar)) }
        XCTAssertFalse(data.contains("\u{1d70}"))
        var attributes = FontOutsetAttributes(face: try font().faceTraits, scale: 1)
        let fallback = try XCTUnwrap(data.outsets(for: attributes, pointSize: 13, preferredGroup: 0))
        XCTAssertEqual(fallback.leading, 2.424812, accuracy: 1e-10)
        XCTAssertEqual(fallback.top, 1.853527, accuracy: 1e-10)
        XCTAssertEqual(fallback.trailing, 1.365013, accuracy: 1e-10)
        XCTAssertEqual(data.referenceRows[8].normal, [0.221681, 0.181204, 0.136001, 0.325064])
        XCTAssertEqual(data.referenceRows[8].extended, [0.041505, 0.373482, 0.136001, 0.348091])
        attributes.weight = nil
        XCTAssertNil(data.outsets(for: attributes, pointSize: 13, preferredGroup: 0))
    }

    // ASSERTIONS textOutsetLanguageAndActiveTraitsObserved
    // ASSERTIONS textOutsetDefaultDataSourceObserved
    func testReferenceSelectionUsesActiveWeightAndStrictTolerance() throws {
        let data = try XCTUnwrap(BundledFontCatalog.shared.outsetData)
        XCTAssertEqual(FontWeightScale.logicalWeight(forClass: 699), 0.39900001883506775)
        let font = try font("NanumSquareNeo/NanumSquareNeo-Variable.ttf")
        XCTAssertEqual(font.faceTraits.sfntStyle.weightClass, 400)
        var attributes = FontOutsetAttributes(face: font.faceTraits, scale: 1)
        XCTAssertEqual(attributes.weight, CGFloat(Float(-0.6)))
        XCTAssertEqual(data.referenceIndex(for: try XCTUnwrap(attributes.weight)), 1)
        for (coordinate, index): (CGFloat, Int) in [
            (400, 3), (500, 3), (529, 3), (530, 4),
            (599, 5), (699, 6), (779, 6), (780, 7), (809, 7), (810, 8)
        ] {
            XCTAssertTrue(font.setVariationCoordinates([0x7767_6874: coordinate]))
            attributes = FontOutsetAttributes(face: font.faceTraits, scale: 1)
            XCTAssertEqual(data.referenceIndex(for: try XCTUnwrap(attributes.weight)), index)
            XCTAssertEqual(attributes.needsOutsets, coordinate > 780)
        }
        XCTAssertTrue(font.setVariationCoordinates([:]))
        XCTAssertEqual(FontOutsetAttributes(face: font.faceTraits, scale: 1).weight, CGFloat(Float(-0.6)))
        XCTAssertNil(data.referenceIndex(for: .nan))
        XCTAssertEqual(data.referenceIndex(for: -10), 0)
        XCTAssertEqual(data.referenceIndex(for: 10), 8)
        let medium = CGFloat(Float(0.23))
        XCTAssertEqual(data.referenceIndex(for: medium - 0.001), 3)
        XCTAssertEqual(data.referenceIndex(for: (medium - 0.001).nextUp), 4)
    }

    // ASSERTIONS textOutsetLanguageAndActiveTraitsObserved
    func testPreferredLanguageOrderAndScriptGroups() throws {
        let data = try XCTUnwrap(BundledFontCatalog.shared.outsetData)
        let cases: [([String], Int)] = [
            ([], 0), (["en"], 0), (["ur"], 4), (["en", "ur"], 4), (["ar", "ur"], 2),
            (["ur", "ar"], 4), (["en", "ar", "ur"], 2), (["ar-Latn", "ur"], 0),
            (["ur-Latn"], 0), (["ur-Arab"], 2), (["ur-PK"], 4), (["my"], 4), (["ks"], 4),
            (["km"], 4), (["bo"], 4), (["vi"], 2), (["lut"], 2), (["und-Aran"], 4), (["pa-Arab"], 2)
        ]
        for (languages, expected) in cases { XCTAssertEqual(data.preferredGroup(for: languages), expected, languages.description) }
    }

    // ASSERTIONS textDrawingOutsetSelectionGatesObserved
    // ASSERTIONS textLanguageAwareOutsetBackendObserved
    func testWholeStringGateAppliesToEveryPrimaryAttributeFont() throws {
        let large = try font(size: 26)
        let small = try font(size: 13)
        let ordinary = ResolvedTextSource(runs: [run("Hg", font: large, size: 26), run("Hg", font: small, size: 13)],
            scaleFactor: 1, preferredLanguages: ["en"])
        let oversized = ResolvedTextSource(runs: [run("Hg", font: large, size: 26), run("Å", font: small, size: 13)],
            scaleFactor: 1, preferredLanguages: ["en"])
        XCTAssertEqual(try XCTUnwrap(ordinary.maximumFontMetrics).outsets.leading, 0)
        let metrics = try XCTUnwrap(oversized.maximumFontMetrics)
        XCTAssertEqual(metrics.outsets.leading, 4.849624, accuracy: 1e-10)
        XCTAssertEqual(metrics.outsets.top, 3.707054, accuracy: 1e-10)
        XCTAssertEqual(metrics.ascender, try XCTUnwrap(ordinary.maximumFontMetrics).ascender)
        XCTAssertEqual(metrics.descender, try XCTUnwrap(ordinary.maximumFontMetrics).descender)
        XCTAssertEqual(metrics.leading, try XCTUnwrap(ordinary.maximumFontMetrics).leading)
    }

    // ASSERTIONS textDrawingOutsetSelectionGatesObserved
    // ASSERTIONS textLanguageAwareOutsetBackendObserved
    func testSuccessfulZeroReplacesClippingWhileUnavailablePreservesIt() throws {
        let font = try font()
        let source = [run("Å", font: font, size: 13)]
        let unavailable = ResolvedTextSource(runs: source, scaleFactor: 1, outsetData: nil)
        let zero = ResolvedTextSource(runs: source, scaleFactor: 1, outsetData: try fixture([0, 0, 0, 0]))
        XCTAssertGreaterThan(try XCTUnwrap(unavailable.maximumFontMetrics).outsets.top, 0)
        XCTAssertEqual(try XCTUnwrap(zero.maximumFontMetrics).outsets, EdgeInsets())
        let first = ResolvedTextSource(runs: source, scaleFactor: 1, outsetData: try fixture([1, 2, 3, 4]))
        let second = ResolvedTextSource(runs: source, scaleFactor: 1, outsetData: try fixture([4, 3, 2, 1]))
        XCTAssertEqual(try XCTUnwrap(first.maximumFontMetrics).outsets, EdgeInsets(top: 26, leading: 13, bottom: 52, trailing: 39))
        XCTAssertEqual(try XCTUnwrap(second.maximumFontMetrics).outsets, EdgeInsets(top: 39, leading: 52, bottom: 13, trailing: 26))
        XCTAssertEqual(try XCTUnwrap(first.maximumFontMetrics).outsets.leading, 13)
    }

    // ASSERTIONS textOutsetLanguageAndActiveTraitsObserved
    // ASSERTIONS textDrawingFrameCompensationObserved
    func testLanguageAndPointSizeSnapshotsReachTheDrawingFrame() throws {
        let font = try font(size: 15.625)
        for scale: CGFloat in [1, 1.5, 2] {
            let runs = [run("Ågj", font: font, size: 15.625, scale: scale)]
            let normal = ResolvedTextSource(runs: runs, scaleFactor: scale, displayScale: 2, preferredLanguages: ["ar", "ur"])
            let extended = ResolvedTextSource(runs: runs, scaleFactor: scale, displayScale: 2, preferredLanguages: ["ur", "ar"])
            let ordinary = try XCTUnwrap(normal.maximumFontMetrics).outsets
            let other = try XCTUnwrap(extended.maximumFontMetrics).outsets
            XCTAssertEqual(ordinary.top, 0.142579 * 15.625, accuracy: 1e-10)
            XCTAssertEqual(other.top, 0.206815 * 15.625, accuracy: 1e-10)
            let styled = ResolvedStyledText.StringDrawing(resolvedText: normal)
            XCTAssertEqual(styled.drawingMargins.top, ceil(ordinary.top * 2) / 2)
            let size = normal.measure()
            let frame = styled.frame(in: size, renderer: nil)
            XCTAssertEqual(frame.minX, -styled.drawingMargins.leading)
            XCTAssertEqual(frame.minY, -styled.drawingMargins.top)
            XCTAssertEqual(frame.width, size.width + styled.drawingMargins.leading + styled.drawingMargins.trailing)
            XCTAssertEqual(frame.height, size.height + styled.drawingMargins.top + styled.drawingMargins.bottom)
        }
    }

    // ASSERTIONS textOutsetLanguageAndActiveTraitsObserved
    func testLogicalFaceTraitsPassThroughDeferredAndTerminalFallbacks() throws {
        let layout = try font("Roboto/Roboto-Italic-VariableFont_wdth,wght.ttf")
        let artwork = try font(size: 90)
        let base: Typeface = VectorTypeface(font: artwork, layoutFont: layout, renderScale: 2)
        var loads = 0
        let deferred = DeferredGlyphTypeface(metrics: base) { loads += 1; return nil }
        let cascade = TypefaceCascade(ordinaryFaces: [deferred], missingGlyphFace: base,
            shapingFeatures: VUI.Font.MonospacedDigitModifier.shapingFeatures)
        for face in cascade.runFaces {
            let traits = try XCTUnwrap(face.outsetAttributes)
            XCTAssertTrue(traits.isItalic)
            XCTAssertEqual(traits.pointSize, 26)
            XCTAssertEqual(traits.weight, 0)
        }
        XCTAssertEqual(loads, 0)
    }
}
