import Foundation
import XCTest
import VVD
@testable import VUI

final class FontOutsetTests: XCTestCase {
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

    private func run(_ text: String, font: VVD.Font, size: CGFloat, scale: CGFloat = 1) -> GraphicsContext.ResolvedText.Run {
        let face = VectorTypeface(font: font, layoutFont: font, renderScale: scale)
        let resource = VUI.Font.file(resource(), size: size).platformFont(in: EnvironmentValues().fontResolutionContext)
        var attributes = _ResolvedTextRunAttributes()
        attributes.fontResource = resource
        return .styledText([face], text, .init(), attributes)
    }

    private func fixture(_ edges: [Double]) throws -> FontOutsetData {
        let object: [String: Any] = ["version": 1, "scalarRanges": [[197, 197]], "referenceWeights": [0],
            "scriptGroups": [:],
            "referenceRows": [["normal": edges, "extended": edges]]]
        return try JSONDecoder().decode(FontOutsetData.self, from: JSONSerialization.data(withJSONObject: object))
    }

    // ASSERTIONS textOutsetDefaultDataSourceObserved
    func testBundledMembershipAndReferencesNeedNoFontNameRegistry() throws {
        let data = try XCTUnwrap(BundledFontCatalog.shared.outsetData)
        XCTAssertEqual(data.referenceRows.count, 9)
        XCTAssertEqual(data.scalarRanges.count, 1584)
        XCTAssertEqual(data.scalarRanges.reduce(0) { $0 + Int($1.upperBound - $1.lowerBound + 1) }, 8028)
        for scalar: Unicode.Scalar in ["Å", "\u{301}", "\u{212b}", "😀"] { XCTAssertTrue(data.contains(scalar)) }
        for scalar: Unicode.Scalar in ["H", "g", "漢", "한", "\u{fffc}"] { XCTAssertFalse(data.contains(scalar)) }
        var attributes = FontOutsetAttributes(face: try font().faceTraits, scale: 1)
        let fallback = try XCTUnwrap(data.outsets(for: attributes, pointSize: 13, preferredGroup: 0))
        XCTAssertEqual(fallback.leading, 2.424812, accuracy: 1e-10)
        XCTAssertEqual(fallback.top, 1.853527, accuracy: 1e-10)
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
        let ordinary = GraphicsContext.ResolvedText(runs: [run("Hg", font: large, size: 26), run("Hg", font: small, size: 13)],
            scaleFactor: 1, preferredLanguages: ["en"])
        let oversized = GraphicsContext.ResolvedText(runs: [run("Hg", font: large, size: 26), run("Å", font: small, size: 13)],
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
        let unavailable = GraphicsContext.ResolvedText(runs: source, scaleFactor: 1, outsetData: nil)
        let zero = GraphicsContext.ResolvedText(runs: source, scaleFactor: 1, outsetData: try fixture([0, 0, 0, 0]))
        XCTAssertGreaterThan(try XCTUnwrap(unavailable.maximumFontMetrics).outsets.top, 0)
        XCTAssertEqual(try XCTUnwrap(zero.maximumFontMetrics).outsets, EdgeInsets())
        let first = GraphicsContext.ResolvedText(runs: source, scaleFactor: 1, outsetData: try fixture([1, 2, 3, 4]))
        let second = GraphicsContext.ResolvedText(runs: source, scaleFactor: 1, outsetData: try fixture([4, 3, 2, 1]))
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
            let normal = GraphicsContext.ResolvedText(runs: runs, scaleFactor: scale, displayScale: 2, preferredLanguages: ["ar", "ur"])
            let extended = GraphicsContext.ResolvedText(runs: runs, scaleFactor: scale, displayScale: 2, preferredLanguages: ["ur", "ar"])
            let ordinary = try XCTUnwrap(normal.maximumFontMetrics).outsets
            let other = try XCTUnwrap(extended.maximumFontMetrics).outsets
            XCTAssertEqual(ordinary.top, 0.142579 * 15.625, accuracy: 1e-10)
            XCTAssertEqual(other.top, 0.206815 * 15.625, accuracy: 1e-10)
            let styled = ResolvedStyledText(resolvedText: normal)
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
