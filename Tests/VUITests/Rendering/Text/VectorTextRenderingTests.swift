import Foundation
import XCTest
@testable import VVD
@testable import VUI

final class VectorTextRenderingTests: XCTestCase {
    func testDrawingBatchesGlyphPathsByForegroundColor() {
        let face = VectorTextTestTypeface()
        let resolved = ResolvedTextSource(
            runs: [
                .styledText(
                    [face],
                    "A",
                    _TextAttributeValues(),
                    _ResolvedTextRunAttributes(foregroundColor: .red)
                ),
                .styledText(
                    [face],
                    "BC",
                    _TextAttributeValues(),
                    _ResolvedTextRunAttributes(foregroundColor: .blue)
                ),
            ],
            scaleFactor: 1
        )

        let drawing = resolved.makeDrawing(
            in: CGSize(width: 100, height: 100)
        )

        XCTAssertEqual(drawing.vectorBatches.count, 2)
        XCTAssertEqual(drawing.vectorBatches[0].foregroundColor, .red)
        XCTAssertEqual(
            drawing.vectorBatches[0].paths.map(\.boundingRect),
            [CGRect(x: 1, y: 0, width: 6, height: 10)]
        )
        XCTAssertEqual(drawing.vectorBatches[1].foregroundColor, .blue)
        XCTAssertEqual(
            drawing.vectorBatches[1].paths.map(\.boundingRect),
            [CGRect(x: 9, y: 0, width: 6, height: 10),
             CGRect(x: 17, y: 0, width: 6, height: 10)]
        )
    }
}

private final class VectorTextTestTypeface: Typeface {
    func glyph(for c: UnicodeScalar) -> TypefaceGlyph? {
        .vector(VectorTypeface.GlyphData(
            metrics: VVD.Font.GlyphMetrics(
                index: c.value,
                advance: CGSize(width: 8, height: 10),
                bearing: CGPoint(x: 1, y: 8),
                size: CGSize(width: 6, height: 10),
                ascender: 8,
                descender: -2
            ),
            path: Path(CGRect(x: 1, y: -8, width: 6, height: 10))
        ))
    }

    func kernAdvance(
        left: UnicodeScalar,
        right: UnicodeScalar
    ) -> CGPoint {
        .zero
    }

    func hasGlyph(for: UnicodeScalar) -> Bool { true }
    var lineHeight: CGFloat { 10 }
    var ascender: CGFloat { 8 }
    var descender: CGFloat { -2 }
    var identifier: String { "vector-text-test" }

    func isEqual(to other: any Typeface) -> Bool {
        self === (other as AnyObject)
    }

    func hashIdentity(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
