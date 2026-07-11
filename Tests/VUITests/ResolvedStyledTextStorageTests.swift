import Foundation
import XCTest
@testable import VUI

final class ResolvedStyledTextStorageTests: XCTestCase {
    func testResolvedRunsProduceCrossPlatformAttributedStorage() throws {
        let face = ResolvedStorageTestTypeface()
        let image = GraphicsContext.ResolvedImage(
            baseline: 0,
            shading: nil,
            texture: nil,
            textureTransform: .identity,
            scaleFactor: 1
        )
        let resolved = GraphicsContext.ResolvedText(
            runs: [
                .text([face], "A "),
                .attachment([face], image),
                .text([face], " B")
            ],
            scaleFactor: 2
        )

        let storage = resolved.attributedStorage
        XCTAssertEqual(storage.string, "A \u{fffc} B")
        XCTAssertTrue(resolved.hasAttachments)
        XCTAssertEqual(resolved.resolvedFeatures, [.attachments])

        var attachmentRanges: [NSRange] = []
        storage.enumerateAttribute(
            .resolvedTextAttachment,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            if value as? Bool == true {
                attachmentRanges.append(range)
            }
        }
        XCTAssertEqual(attachmentRanges.count, 1)
        XCTAssertEqual(
            storage.attributedSubstring(from: try XCTUnwrap(attachmentRanges.first)).string,
            "\u{fffc}"
        )

        let archive = _ResolvedAttributedStringArchive(storage)
        let encoded = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(_ResolvedAttributedStringArchive.self, from: encoded)
        XCTAssertEqual(decoded, archive)
        XCTAssertEqual(decoded.attributedString, storage)
    }

    func testResolvedStyledTextReusesExistingFontMetricsAndRunStorage() throws {
        XCTAssertEqual(MemoryLayout<ResolvedFontMetrics>.size, 64)
        XCTAssertEqual(MemoryLayout<ResolvedFontMetrics>.stride, 64)

        let face = ResolvedStorageTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "metrics")],
            scaleFactor: 2
        )
        var properties = TextLayoutProperties()
        properties.lineLimit = 3

        let styled = ResolvedStyledText(
            layoutProperties: properties,
            archiveOptions: .isArchived,
            resolvedText: resolved,
            version: 7
        )

        XCTAssertEqual(try XCTUnwrap(styled.storage).string, "metrics")
        XCTAssertEqual(styled.layoutProperties.lineLimit, 3)
        XCTAssertTrue(styled.archiveOptions.isArchived)
        XCTAssertFalse(styled.isCollapsible)
        XCTAssertTrue(styled.features.isEmpty)
        XCTAssertTrue(styled.styles.isEmpty)
        XCTAssertTrue(styled.transitions.isEmpty)
        XCTAssertEqual(styled.links, Text.ResolvedProperties.Links())
        let metrics = try XCTUnwrap(styled.maxFontMetrics)
        XCTAssertEqual(metrics.capHeight, 4)
        XCTAssertEqual(metrics.ascender, 4)
        XCTAssertEqual(metrics.descender, -1)
        XCTAssertEqual(metrics.leading, 0)
        XCTAssertEqual(metrics.outsets, EdgeInsets())
    }

    func testResolvedPropertiesFeatureBitsMatchObservedSurface() {
        XCTAssertEqual(Text.ResolvedProperties.Features.keyColor.rawValue, 0x001)
        XCTAssertEqual(Text.ResolvedProperties.Features.attachments.rawValue, 0x002)
        XCTAssertEqual(Text.ResolvedProperties.Features.sensitive.rawValue, 0x004)
        XCTAssertEqual(Text.ResolvedProperties.Features.customRenderer.rawValue, 0x008)
        XCTAssertEqual(Text.ResolvedProperties.Features.useTextLayoutManager.rawValue, 0x010)
        XCTAssertEqual(Text.ResolvedProperties.Features.useTextSuffix.rawValue, 0x020)
        XCTAssertEqual(Text.ResolvedProperties.Features.produceTextLayout.rawValue, 0x040)
        XCTAssertEqual(Text.ResolvedProperties.Features.checkInterpolationStrategy.rawValue, 0x080)
        XCTAssertEqual(Text.ResolvedProperties.Features.isUniqueSizeVariant.rawValue, 0x100)
        XCTAssertEqual(Text.ResolvedProperties.Features.isStandaloneSizeVariant.rawValue, 0x200)
    }

    func testResolvedPropertiesSupplementalCarrierDefaultsAndAttachmentRegistration() throws {
        var properties = Text.ResolvedProperties()

        XCTAssertTrue(properties.features.isEmpty)
        XCTAssertEqual(properties.insets, EdgeInsets())
        XCTAssertTrue(properties.styles.isEmpty)
        XCTAssertTrue(properties.transitions.isEmpty)
        XCTAssertEqual(properties.suffix, .none)
        XCTAssertTrue(properties.customAttachments.isEmpty)
        XCTAssertTrue(properties.paragraph.languageIdentifiers.isEmpty)
        XCTAssertEqual(properties.paragraph.startIndex, 0)
        XCTAssertNil(properties.multilineTextAlignment)
        XCTAssertEqual(MemoryLayout<Text.ResolvedProperties.Links>.size, 0)

        properties.registerCustomAttachment(at: 3)
        properties.registerCustomAttachment(at: 3)
        properties.registerCustomAttachment(at: 8)

        XCTAssertEqual(properties.customAttachments.characterIndices, [3, 3, 8])
        XCTAssertFalse(properties.customAttachments.isEmpty)

        let transition = Text.ResolvedProperties.Transition(transition: .opacity)
        properties.transitions.append(transition)
        XCTAssertEqual(properties.transitions, [transition])
        XCTAssertEqual(properties.links, Text.ResolvedProperties.Links())

        properties.paragraph.languageIdentifiers = ["en", "ar"]
        properties.paragraph.markParagraphBoundary(at: 11)
        XCTAssertTrue(properties.paragraph.languageIdentifiers.isEmpty)
        XCTAssertEqual(properties.paragraph.startIndex, 11)

        let paragraphData = try JSONEncoder().encode(properties.paragraph)
        let decodedParagraph = try JSONDecoder().decode(
            Text.ResolvedProperties.Paragraph.self,
            from: paragraphData
        )
        XCTAssertEqual(decodedParagraph, properties.paragraph)
    }

    func testResolvedSuffixAndShapeStyleDefaultsMatchObservedSurface() throws {
        let face = ResolvedStorageTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "suffix")],
            scaleFactor: 1
        )
        var glyph = GraphicsContext.ResolvedText.Glyph(
            scalar: UnicodeScalar("s"),
            face: face
        )
        glyph.advance = CGSize(width: 8, height: 10)
        glyph.ascender = 8
        glyph.descender = -2
        let line = try XCTUnwrap(
            resolved.makeLayout(
                lineGlyphs: [
                    GraphicsContext.ResolvedText.LineGlyphs(
                        glyphs: [glyph],
                        ascender: 8,
                        descender: -2,
                        width: 8
                    )
                ],
                layoutDirection: .leftToRight
            ).first
        )
        let color = Color.Resolved(red: 0.25, green: 0.5, blue: 0.75)
        let style = _ShapeStyle_Pack.Style(.color(color))

        XCTAssertEqual(style.fill, .color(color))
        XCTAssertEqual(style.opacity, 1)
        XCTAssertNil(style.blendMode)
        XCTAssertTrue(style.effects.isEmpty)

        let truncated = ResolvedTextSuffix.truncated(line, [style])
        XCTAssertEqual(truncated.line, line)
        XCTAssertEqual(truncated.styles, [style])

        let alwaysVisible = ResolvedTextSuffix.alwaysVisible(line, [style])
        XCTAssertEqual(alwaysVisible.line, line)
        XCTAssertEqual(alwaysVisible.styles, [style])

        XCTAssertNil(ResolvedTextSuffix.none.line)
        XCTAssertTrue(ResolvedTextSuffix.none.styles.isEmpty)
    }
}

private final class ResolvedStorageTestTypeface: Typeface {
    func glyph(for c: UnicodeScalar) -> TypefaceGlyph? { nil }
    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint { .zero }
    func hasGlyph(for: UnicodeScalar) -> Bool { true }
    var lineHeight: CGFloat { 10 }
    var ascender: CGFloat { 8 }
    var descender: CGFloat { -2 }
    var identifier: String { "resolved-storage-test" }
    func isEqual(to other: any Typeface) -> Bool { self === (other as AnyObject) }
    func hashIdentity(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
