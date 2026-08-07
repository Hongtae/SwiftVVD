import Foundation
import XCTest
@testable import VVD
@testable import VUI

// ASSERTIONS attributedTextCoreVisualRuntimeObserved
final class AttributedTextCoreVisualTests: XCTestCase {
    func testTextModifierCarrierPreservesObservedCasesAndAppendOrder() {
        XCTAssertEqual(
            Text(verbatim: "value")
                .foregroundColor(.red)
                .foregroundColor(.blue)
                .font(nil)
                .italic()
                .fontWeight(.bold)
                .kerning(2)
                .tracking(4)
                .baselineOffset(3)
                .modifiers,
            [
                .color(.red),
                .color(.blue),
                .font(nil),
                .italic,
                .weight(.bold),
                .kerning(2),
                .tracking(4),
                .baseline(3),
            ]
        )

        XCTAssertEqual(
            Text(verbatim: "value")
                .underline(pattern: .dash, color: .green)
                .underline(false)
                .strikethrough(pattern: .dot, color: .blue)
                .modifiers,
            [
                .anyTextModifier(UnderlineTextModifier(
                    lineStyle: Text.LineStyle(
                        pattern: .dash,
                        color: .green
                    )
                )),
                .anyTextModifier(UnderlineTextModifier(lineStyle: nil)),
                .anyTextModifier(StrikethroughTextModifier(
                    lineStyle: Text.LineStyle(
                        pattern: .dot,
                        color: .blue
                    )
                )),
            ]
        )
    }

    func testAttributedStringCoreAttributesReachDrawableStyledRun() throws {
        let face = CoreVisualTestTypeface()
        let underline = Text.LineStyle(pattern: .dash, color: .green)
        let strikethrough = Text.LineStyle(pattern: .dot, color: .blue)
        var value = AttributedString("AB")
        value._setCoreAttributes(_ResolvedTextRunAttributes(
            foregroundColor: VUI.Color.purple,
            backgroundColor: VUI.Color.red,
            strikethroughStyle: strikethrough,
            underlineStyle: underline,
            kern: 2,
            tracking: 3,
            baselineOffset: 4
        ))

        let resolved = _resolvedAttributedText(
            value,
            defaultTypefaces: [face],
            context: CoreVisualTextResolutionContext()
        )

        guard case let .styledText(faces, text, _, style) =
            try XCTUnwrap(resolved.runs.first) else {
            return XCTFail("expected an attributed styled run")
        }
        XCTAssertTrue(faces[0].isEqual(to: face))
        XCTAssertEqual(text, "AB")
        XCTAssertEqual(style.foregroundColor, .purple)
        XCTAssertEqual(style.backgroundColor, .red)
        XCTAssertEqual(style.underlineStyle, underline)
        XCTAssertEqual(style.strikethroughStyle, strikethrough)
        XCTAssertEqual(style.kern, 2)
        XCTAssertEqual(style.tracking, 3)
        XCTAssertEqual(style.baselineOffset, 4)

        let line = try XCTUnwrap(resolved.makeGlyphs().first)
        XCTAssertEqual(line.width, 22)
        XCTAssertEqual(line.ascender, 12)
    }

    func testResolutionVersionTracksContentScaleAndTextModifiers() {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
        var environment = EnvironmentValues()
        environment.displayScale = 1
        environment._contentScaleFactor = 1
        let text = Text(verbatim: "value")
        let base = text._resolutionVersion(
            in: environment,
            referenceDate: referenceDate
        )

        environment._contentScaleFactor = 2
        let scaled = text._resolutionVersion(
            in: environment,
            referenceDate: referenceDate
        )
        let tracked = text.tracking(3)._resolutionVersion(
            in: environment,
            referenceDate: referenceDate
        )

        XCTAssertNotEqual(base, scaled)
        XCTAssertNotEqual(scaled, tracked)
    }

    func testRunModifiersUseObservedFirstValueAndTrackingPriority() throws {
        let face = CoreVisualTestTypeface()
        let source = GraphicsContext.ResolvedText.Run.styledText(
            [face],
            "AB",
            _TextAttributeValues(),
            _ResolvedTextRunAttributes(kern: 2)
        )

        let modified = source.applying(textModifiers: [
            .kerning(6),
            .tracking(4),
            .tracking(9),
            .baseline(3),
            .baseline(7),
            .anyTextModifier(UnderlineTextModifier(lineStyle: nil)),
            .anyTextModifier(UnderlineTextModifier(
                lineStyle: Text.LineStyle(color: .red)
            )),
        ])
        guard case let .styledText(_, _, _, style) = modified else {
            return XCTFail("expected a styled run")
        }
        XCTAssertEqual(style.kern, 2)
        XCTAssertEqual(style.tracking, 4)
        XCTAssertEqual(style.baselineOffset, 3)
        XCTAssertNil(style.underlineStyle)

        let resolved = GraphicsContext.ResolvedText(
            runs: [modified],
            scaleFactor: 1
        )
        let line = try XCTUnwrap(resolved.makeGlyphs().first)
        XCTAssertEqual(line.glyphs.map(\.advance.width), [12, 12])
        XCTAssertEqual(line.width, 24)

        let attributedTracking = GraphicsContext.ResolvedText.Run.styledText(
            [face],
            "AB",
            _TextAttributeValues(),
            _ResolvedTextRunAttributes(tracking: 5)
        ).applying(textModifiers: [.tracking(4), .kerning(6)])
        guard case let .styledText(_, _, _, retainedStyle) =
            attributedTracking else {
            return XCTFail("expected a styled run")
        }
        XCTAssertEqual(retainedStyle.tracking, 5)
        XCTAssertNil(retainedStyle.kern)
    }

    func testSpacingAppliesToEveryGlyphAdvanceIncludingFinalGlyph() throws {
        let face = CoreVisualTestTypeface()
        let tracking = GraphicsContext.ResolvedText(
            runs: [
                .styledText(
                    [face],
                    "AB",
                    _TextAttributeValues(),
                    _ResolvedTextRunAttributes(tracking: 3)
                )
            ],
            scaleFactor: 1
        )
        let line = try XCTUnwrap(tracking.makeGlyphs().first)

        XCTAssertEqual(line.glyphs.map(\.advance.width), [11, 11])
        XCTAssertEqual(line.width, 22)

        let kern = GraphicsContext.ResolvedText(
            runs: [
                .styledText(
                    [face],
                    "AB",
                    _TextAttributeValues(),
                    _ResolvedTextRunAttributes(kern: 2)
                )
            ],
            scaleFactor: 1
        )
        XCTAssertEqual(try XCTUnwrap(kern.makeGlyphs().first).width, 20)
    }

    func testBaselineOffsetsExpandLineAndKeepAbsoluteRunBaselines() throws {
        let face = CoreVisualTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [
                .styledText(
                    [face],
                    "A",
                    _TextAttributeValues(),
                    _ResolvedTextRunAttributes(baselineOffset: 3)
                ),
                .styledText(
                    [face],
                    "B",
                    _TextAttributeValues(),
                    _ResolvedTextRunAttributes(baselineOffset: -4)
                ),
            ],
            scaleFactor: 1
        )

        let lineGlyphs = try XCTUnwrap(resolved.makeGlyphs().first)
        XCTAssertEqual(lineGlyphs.ascender, 11)
        XCTAssertEqual(lineGlyphs.descender, -6)
        XCTAssertEqual(lineGlyphs.height, 17)

        let layout = resolved.makeLayout(
            in: CGSize(width: 100, height: 100),
            layoutDirection: .leftToRight
        )
        let line = try XCTUnwrap(layout.first)
        XCTAssertEqual(line.origin, CGPoint(x: 0, y: 11))
        XCTAssertEqual(line.typographicBounds.ascent, 11)
        XCTAssertEqual(line.typographicBounds.descent, 6)
        XCTAssertEqual(line.count, 2)
        XCTAssertEqual(line[0].typographicBounds.origin.y, 8)
        XCTAssertEqual(line[1].typographicBounds.origin.y, 15)
        XCTAssertEqual(line[0].typographicBounds.ascent, 8)
        XCTAssertEqual(line[0].typographicBounds.descent, 2)
        XCTAssertEqual(line[1].typographicBounds.ascent, 8)
        XCTAssertEqual(line[1].typographicBounds.descent, 2)
        XCTAssertEqual(line[0].typographicBounds.leading, 0)
        XCTAssertEqual(line[1].typographicBounds.leading, 0)
    }

    func testBackgroundAndDecorationsUseRunTypographicGeometry() throws {
        let face = CoreVisualTestTypeface()
        let underline = Text.LineStyle(pattern: .dash, color: .green)
        let strikethrough = Text.LineStyle(pattern: .dot)
        let resolved = GraphicsContext.ResolvedText(
            runs: [
                .styledText(
                    [face],
                    "A ",
                    _TextAttributeValues(),
                    _ResolvedTextRunAttributes(
                        foregroundColor: .blue,
                        backgroundColor: .red,
                        strikethroughStyle: strikethrough,
                        underlineStyle: underline,
                        baselineOffset: 3
                    )
                ),
                .text([face], "B"),
            ],
            scaleFactor: 1,
            displayScale: 2
        )

        let drawing = resolved.makeDrawing(
            in: CGSize(width: 100, height: 100)
        )
        let background = try XCTUnwrap(drawing.backgrounds.first)
        XCTAssertEqual(drawing.backgrounds.count, 1)
        XCTAssertEqual(
            background.frame,
            CGRect(x: 0, y: 0, width: 16, height: 10)
        )
        XCTAssertEqual(background.color, .red)

        XCTAssertEqual(drawing.decorations.count, 2)
        let underlineGeometry = try XCTUnwrap(
            drawing.decorations.first { $0.lineStyle == underline }
        )
        XCTAssertEqual(underlineGeometry.start, CGPoint(x: 0, y: 9.5))
        XCTAssertEqual(underlineGeometry.end, CGPoint(x: 16, y: 9.5))
        XCTAssertEqual(underlineGeometry.lineWidth, 1.5)
        XCTAssertEqual(underlineGeometry.foregroundColor, .green)

        let strikeGeometry = try XCTUnwrap(
            drawing.decorations.first { $0.lineStyle == strikethrough }
        )
        XCTAssertEqual(strikeGeometry.start, CGPoint(x: 0, y: 6))
        XCTAssertEqual(strikeGeometry.end, CGPoint(x: 16, y: 6))
        XCTAssertEqual(strikeGeometry.lineWidth, 1.5)
        XCTAssertEqual(strikeGeometry.foregroundColor, .blue)
    }

    func testDecorationDashPatternsUseObservedThicknessRatios() {
        func pattern(_ pattern: Text.LineStyle.Pattern) -> [CGFloat] {
            GraphicsContext.ResolvedText.Drawing.Decoration(
                start: .zero,
                end: CGPoint(x: 10, y: 0),
                lineWidth: 2,
                lineStyle: Text.LineStyle(pattern: pattern),
                foregroundColor: nil
            ).dashPattern(lineWidth: 2)
        }

        XCTAssertEqual(pattern(.solid), [])
        XCTAssertEqual(pattern(.dot), [6, 6])
        XCTAssertEqual(pattern(.dash), [20, 10])
        XCTAssertEqual(pattern(.dashDot), [20, 6, 6, 6])
        XCTAssertEqual(pattern(.dashDotDot), [20, 6, 6, 6, 6, 6])
    }

    func testHeadMiddleAndTailTruncationPreserveObservedCharacterIndices()
        throws {
        let face = CoreVisualTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "ABCDEFGHIJKLMN")],
            scaleFactor: 1
        )

        var properties = TextLayoutProperties()
        properties.lineLimit = 1

        properties.truncationMode = .tail
        let tail = resolved.makeLayout(
            in: CGSize(width: 24, height: 100),
            layoutDirection: .leftToRight,
            layoutProperties: properties
        )
        XCTAssertTrue(tail.isTruncated)
        XCTAssertEqual(try characterIndices(tail), [0, 1, 2])
        XCTAssertEqual(
            glyphScalars(resolved, width: 24, properties: properties),
            ["A", "B", "…"]
        )
        XCTAssertEqual(try XCTUnwrap(tail.first).count, 2)

        properties.truncationMode = .head
        let head = resolved.makeLayout(
            in: CGSize(width: 24, height: 100),
            layoutDirection: .leftToRight,
            layoutProperties: properties
        )
        XCTAssertTrue(head.isTruncated)
        XCTAssertEqual(try characterIndices(head), [0, 12, 13])
        XCTAssertEqual(
            glyphScalars(resolved, width: 24, properties: properties),
            ["…", "M", "N"]
        )
        XCTAssertEqual(try XCTUnwrap(head.first).count, 2)

        properties.truncationMode = .middle
        let middle = resolved.makeLayout(
            in: CGSize(width: 32, height: 100),
            layoutDirection: .leftToRight,
            layoutProperties: properties
        )
        XCTAssertTrue(middle.isTruncated)
        XCTAssertEqual(try characterIndices(middle), [0, 1, 12, 13])
        XCTAssertEqual(
            glyphScalars(resolved, width: 32, properties: properties),
            ["A", "…", "M", "N"]
        )
        XCTAssertEqual(try XCTUnwrap(middle.first).count, 3)
    }

    func testTruncationTokenInheritsObservedOmittedSourceStyle() throws {
        let face = CoreVisualTestTypeface()
        let red = _ResolvedTextRunAttributes(foregroundColor: .red)
        let blue = _ResolvedTextRunAttributes(foregroundColor: .blue)
        let green = _ResolvedTextRunAttributes(foregroundColor: .green)

        var properties = TextLayoutProperties()
        properties.lineLimit = 1

        properties.truncationMode = .tail
        let tail = GraphicsContext.ResolvedText(
            runs: [
                .styledText([face], "AB", _TextAttributeValues(), blue),
                .styledText(
                    [face],
                    "CDEFGHIJKLMN",
                    _TextAttributeValues(),
                    red
                ),
            ],
            scaleFactor: 1
        ).makeGlyphs(
            maxWidth: 24,
            maxHeight: 100,
            lineLimit: properties.lineLimit,
            truncationMode: properties.truncationMode
        )
        XCTAssertEqual(
            try XCTUnwrap(tail.first).glyphs.last?.foregroundColor,
            .red
        )

        properties.truncationMode = .head
        let head = GraphicsContext.ResolvedText(
            runs: [
                .styledText([face], "A", _TextAttributeValues(), red),
                .styledText(
                    [face],
                    "BCDEFGHIJKLMN",
                    _TextAttributeValues(),
                    blue
                ),
            ],
            scaleFactor: 1
        ).makeGlyphs(
            maxWidth: 24,
            maxHeight: 100,
            lineLimit: properties.lineLimit,
            truncationMode: properties.truncationMode
        )
        XCTAssertEqual(
            try XCTUnwrap(head.first).glyphs.first?.foregroundColor,
            .red
        )

        properties.truncationMode = .middle
        let middle = GraphicsContext.ResolvedText(
            runs: [
                .styledText([face], "A", _TextAttributeValues(), green),
                .styledText([face], "B", _TextAttributeValues(), red),
                .styledText(
                    [face],
                    "CDEFGHIJKLMN",
                    _TextAttributeValues(),
                    blue
                ),
            ],
            scaleFactor: 1
        ).makeGlyphs(
            maxWidth: 32,
            maxHeight: 100,
            lineLimit: properties.lineLimit,
            truncationMode: properties.truncationMode
        )
        XCTAssertEqual(
            try XCTUnwrap(middle.first).glyphs[1].foregroundColor,
            .red
        )

        properties.truncationMode = .tail
        let newline = GraphicsContext.ResolvedText(
            runs: [
                .styledText([face], "AB", _TextAttributeValues(), red),
                .styledText([face], "\nCD", _TextAttributeValues(), blue),
            ],
            scaleFactor: 1
        ).makeGlyphs(
            maxWidth: 100,
            maxHeight: 100,
            lineLimit: properties.lineLimit,
            truncationMode: properties.truncationMode
        )
        XCTAssertEqual(
            try XCTUnwrap(newline.first).glyphs.last?.foregroundColor,
            .red
        )
    }

    func testLineLimitTruncatesRemainingParagraphOnLastVisibleLine() throws {
        let face = CoreVisualTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "ABCDEFGHIJKLMN")],
            scaleFactor: 1
        )
        var properties = TextLayoutProperties()
        properties.lineLimit = 2
        properties.truncationMode = .tail

        let layout = resolved.makeLayout(
            in: CGSize(width: 40, height: 100),
            layoutDirection: .leftToRight,
            layoutProperties: properties
        )

        XCTAssertTrue(layout.isTruncated)
        XCTAssertEqual(layout.count, 2)
        XCTAssertEqual(
            layout[0].flatMap(\.characterIndices).map(\.value),
            [0, 1, 2, 3, 4]
        )
        XCTAssertEqual(
            layout[1].flatMap(\.characterIndices).map(\.value),
            [5, 6, 7, 8, 9]
        )
        XCTAssertEqual(
            resolved.makeGlyphs(
                maxWidth: 40,
                maxHeight: 100,
                lineLimit: 2,
                truncationMode: .tail
            )[1].glyphs.map { String($0.scalar) },
            ["F", "G", "H", "I", "…"]
        )
    }

    func testExplicitNewlineUsesTailOnlySuffixAndDoesNotSetTruncatedFlag()
        throws {
        let face = CoreVisualTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "AB\nCD")],
            scaleFactor: 1
        )
        var properties = TextLayoutProperties()
        properties.lineLimit = 1

        properties.truncationMode = .tail
        let tail = resolved.makeLayout(
            in: CGSize(width: 100, height: 100),
            layoutDirection: .leftToRight,
            layoutProperties: properties
        )
        XCTAssertFalse(tail.isTruncated)
        XCTAssertEqual(try characterIndices(tail), [0, 1, 2])
        XCTAssertEqual(
            glyphScalars(resolved, width: 100, properties: properties),
            ["A", "B", "…"]
        )

        for mode: Text.TruncationMode in [.head, .middle] {
            properties.truncationMode = mode
            let layout = resolved.makeLayout(
                in: CGSize(width: 100, height: 100),
                layoutDirection: .leftToRight,
                layoutProperties: properties
            )
            XCTAssertFalse(layout.isTruncated)
            XCTAssertEqual(try characterIndices(layout), [0, 1])
            XCTAssertEqual(
                glyphScalars(resolved, width: 100, properties: properties),
                ["A", "B"]
            )
        }
    }

    func testTooNarrowTruncationKeepsSourceGlyphsAndClampsLineWidth()
        throws {
        let face = CoreVisualTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "ABCDEFGHIJKLMN")],
            scaleFactor: 1
        )
        var properties = TextLayoutProperties()
        properties.lineLimit = 1
        properties.truncationMode = .tail

        let layout = resolved.makeLayout(
            in: CGSize(width: 1, height: 100),
            layoutDirection: .leftToRight,
            layoutProperties: properties
        )

        XCTAssertFalse(layout.isTruncated)
        XCTAssertEqual(try characterIndices(layout), Array(0..<14))
        XCTAssertEqual(try XCTUnwrap(layout.first).typographicBounds.width, 1)
    }

    func testGlyphAtomsApplyPairKerningBeforeFollowingGlyph() throws {
        let face = CoreVisualTestTypeface(pairKerning: 2)
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "AB")],
            scaleFactor: 1
        )

        let atoms = resolved.glyphAtoms(
            in: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(atoms.count, 2)
        XCTAssertEqual(atoms[0].bounds.origin.x, 0)
        XCTAssertEqual(atoms[1].bounds.origin.x, 10)
        XCTAssertEqual(atoms[1].bounds.maxX, 18)
    }

    func testBundledFontDecorationMetricsMatchObservedCoreTextValues()
        throws {
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let cases: [(
            path: String,
            xHeight: CGFloat,
            underlinePosition: CGFloat,
            underlineThickness: CGFloat
        )] = [
            (
                "Roboto/Roboto-Regular.ttf",
                21.1328,
                -2.9297,
                1.9531
            ),
            (
                "NanumSquareNeo/NanumSquareNeo-bRg.ttf",
                21,
                -8,
                2
            ),
            (
                "NanumGothic/NanumGothic.ttf",
                20,
                -10.4,
                2.32
            ),
        ]

        for item in cases {
            let fontURL = sourceDirectory
                .appendingPathComponent(
                    "../../../../Sources/VUI/Resources/Fonts/" + item.path
                )
                .standardizedFileURL
            let font = try XCTUnwrap(VVD.Font(path: fontURL.path), item.path)
            font.pointSize = 40

            let metrics = try XCTUnwrap(
                typefaceDecorationMetrics(for: font),
                item.path
            )
            XCTAssertEqual(
                metrics.xHeight ?? 0,
                item.xHeight,
                accuracy: 0.02,
                item.path
            )
            XCTAssertEqual(
                metrics.underlinePosition,
                item.underlinePosition,
                accuracy: 0.02,
                item.path
            )
            XCTAssertEqual(
                metrics.underlineThickness,
                item.underlineThickness,
                accuracy: 0.02,
                item.path
            )
        }
    }

    private func characterIndices(
        _ layout: Text.Layout
    ) throws -> [Int] {
        try XCTUnwrap(layout.first)
            .flatMap(\.characterIndices)
            .map(\.value)
    }

    private func glyphScalars(
        _ resolved: GraphicsContext.ResolvedText,
        width: Int,
        properties: TextLayoutProperties
    ) -> [String] {
        resolved.makeGlyphs(
            maxWidth: width,
            maxHeight: 100,
            lineLimit: properties.lineLimit,
            truncationMode: properties.truncationMode
        ).first?.glyphs.map { String($0.scalar) } ?? []
    }
}

private struct CoreVisualTextResolutionContext: TextResolutionContext {
    var environment = EnvironmentValues()
    let sceneResources = SceneResources()

    func resolveTextAttachment(
        _ image: VUI.Image
    ) -> GraphicsContext.ResolvedImage? {
        nil
    }
}

private final class CoreVisualTestTypeface: Typeface {
    let pairKerning: CGFloat

    init(pairKerning: CGFloat = 0) {
        self.pairKerning = pairKerning
    }

    func glyph(for c: UnicodeScalar) -> TypefaceGlyph? {
        .texture(TextureFont.GlyphData(
            texture: nil,
            offset: CGPoint(x: 0, y: 8),
            advance: CGSize(width: 8, height: 10),
            frame: CGRect(x: 0, y: 0, width: 8, height: 10),
            ascender: 8,
            descender: -2
        ))
    }

    func kernAdvance(
        left: UnicodeScalar,
        right: UnicodeScalar
    ) -> CGPoint {
        left == UnicodeScalar("A") && right == UnicodeScalar("B")
            ? CGPoint(x: pairKerning, y: 0)
            : .zero
    }

    func hasGlyph(for: UnicodeScalar) -> Bool { true }
    var lineHeight: CGFloat { 10 }
    var ascender: CGFloat { 8 }
    var descender: CGFloat { -2 }
    var decorationMetrics: TypefaceDecorationMetrics? {
        TypefaceDecorationMetrics(
            xHeight: 4,
            underlinePosition: -1.5,
            underlineThickness: 1.25
        )
    }
    var identifier: String { "attributed-core-visual-test" }
    func isEqual(to other: any Typeface) -> Bool {
        self === (other as AnyObject)
    }
    func hashIdentity(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
