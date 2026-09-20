import Foundation
import XCTest
import VVD
@testable import VUI

final class TextDecorationTests: XCTestCase {
    func testDecorationScaleUsesBothTransformedAxesAndDeviceScale() {
        // ASSERTIONS textDecorationAffineScale27Observed
        let samples: [([CGFloat], CGFloat)] = [
            ([1, 0, 0, 1, 0, 0], 1), ([1, 0, 0, 1, 9, -3], 1),
            ([2, 0, 0, 0.5, 0, 0], 1.25), ([0, 1, -1, 0, 0, 0], 1),
            ([-1, 0, 0, 1, 0, 0], 1), ([1, 1, 0, 1, 0, 0], 1.2071067811865475),
            ([0.5, 0.75, -1, 2, 0, 0], 1.5687278981828936)
        ]
        for scale: CGFloat in [1, 2] {
            for (values, expected) in samples {
                let viewport = CGRect(x: 0, y: 0, width: 256, height: 100)
                var context = GraphicsContext(recording: RBDisplayList(viewport: viewport), environment: .init(),
                    inputs: .init(sceneResources: SceneResources(), viewport: viewport,
                        contentScaleFactor: scale, resourceCommandQueue: nil))
                context.transform = CGAffineTransform(a: values[0], b: values[1], c: values[2],
                    d: values[3], tx: values[4], ty: values[5])
                XCTAssertEqual(context.userToDeviceScale, expected * scale, accuracy: 1e-12)
            }
        }
    }

    private var fontURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            .standardizedFileURL
    }

    func testRawDecorationMetricsPreserveFractionalSizesAndDefaultMetrics() throws {
        // ASSERTIONS textDecorationMetricQuantization27Observed
        let font = try XCTUnwrap(VVD.Font(path: fontURL.path))
        XCTAssertTrue(font.setVariationCoordinates([0x7767_6874: 400]))
        for size: CGFloat in [2, 6, 7.25, 8, 12, 13.5, 17, 23, 31, 48] {
            for dpi: UInt32 in [72, 144] {
                font.pointSize = size
                font.dpi = (dpi, dpi)
                let metrics = try XCTUnwrap(typefaceDecorationMetrics(for: font))
                let unit = size * CGFloat(dpi) / 72 / 2048
                XCTAssertEqual(try XCTUnwrap(metrics.xHeight), 1082 * unit, accuracy: 1e-12)
                XCTAssertEqual(metrics.underlinePosition, -150 * unit, accuracy: 1e-12)
                XCTAssertEqual(metrics.underlineThickness, 100 * unit, accuracy: 1e-12)
                XCTAssertEqual(try XCTUnwrap(metrics.defaultAscent), 1900 * unit, accuracy: 1e-12)
                XCTAssertEqual(try XCTUnwrap(metrics.defaultDescent), 500 * unit, accuracy: 1e-12)
            }
        }
    }

    func testOutlineAdmissionKeepsRawAdvanceSeparateFromRoundedEndpoint() throws {
        // ASSERTIONS textDecorationSpacingProducer27Observed
        for scale: CGFloat in [1, 2] {
            for transform in [CGAffineTransform.identity, CGAffineTransform(scaleX: 1, y: -1)] {
                for inside in [false, true] {
                    let face = DecorationBoundsTypeface(bounds: CGRect(x: inside ? 58.7 : 58.8,
                        y: -10, width: 0.1, height: 20))
                    var glyph = ResolvedTextSource.Glyph(scalar: "A", face: face)
                    glyph.glyphIndex = 37
                    glyph.advance.width = 58.716796875
                    glyph.baselineOffset = 3
                    glyph.style.underlineStyle = Text.LineStyle()
                    let segments = TextDecorationProducer.segments(glyphs: [glyph], runs: [0..<1],
                        origin: .zero, glyphTransform: transform, scaleFactor: 1, scale: scale,
                        displayScale: scale, environment: .init())
                    XCTAssertEqual(face.outlineRequests, inside ? 1 : 0)
                    if !inside {
                        let segment = try XCTUnwrap(segments.first).segment
                        XCTAssertEqual(segment.fragments.count, 1)
                        XCTAssertEqual(segment.fragments.first?.start.x, 0)
                        XCTAssertEqual(segment.fragments.first?.end.x, 59)
                    }
                }
            }
        }
    }
}

private final class DecorationBoundsTypeface: Typeface {
    let bounds: CGRect
    var outlineRequests = 0
    init(bounds: CGRect) { self.bounds = bounds }
    var ascender: CGFloat { 21.337890625 }
    var descender: CGFloat { -5.615234375 }
    var lineHeight: CGFloat { ascender - descender }
    var identifier: String { "decoration-bounds-fixture" }
    var decorationMetrics: TypefaceDecorationMetrics? {
        .init(xHeight: 12.1513671875, underlinePosition: -1.6845703125,
              underlineThickness: 1.123046875, defaultAscent: ascender, defaultDescent: -descender)
    }
    func glyphBounds(at index: UInt32) -> CGRect? { bounds }
    func glyphOutline(at index: UInt32) -> Path? {
        outlineRequests += 1
        return Path(bounds)
    }
    func glyph(for scalar: UnicodeScalar) -> TypefaceGlyph? { nil }
    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint { .zero }
    func hasGlyph(for scalar: UnicodeScalar) -> Bool { true }
    func isEqual(to other: any Typeface) -> Bool { (other as? Self) === self }
    func hashIdentity(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
