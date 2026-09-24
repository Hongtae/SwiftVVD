import Foundation
import Synchronization
import XCTest
import VVD
@testable import VUI

final class TextParagraphAdmissionTests: XCTestCase {
    private var previousContext: (any AppContext)?
    private var scene = SceneResources()

    override func setUp() {
        previousContext = appContext
        appContext = ParagraphAdmissionAppContext()
        scene = SceneResources()
    }

    override func tearDown() {
        appContext = previousContext
        previousContext = nil
    }

    private func resolve(_ string: String, size: CGFloat = 23, scale: CGFloat = 1,
                         spacing: CGFloat = 0, avoidsOrphans: Bool = true, cjk: Bool = false) throws -> ResolvedTextSource {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let font = VUI.Font.file(root.appendingPathComponent(
            cjk ? "Sources/VUI/Resources/Fonts/NotoSansKR/NotoSansKR-VariableFont_wght.ttf"
                : "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: size,
            weight: cjk ? .thin : .regular)
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        environment.displayScale = 2
        environment._contentScaleFactor = scale
        environment.lineSpacing = spacing
        environment.avoidsOrphans = avoidsOrphans
        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        return try XCTUnwrap(Text(verbatim: string).font(font)._resolve(context:
            GraphTextResolutionContext(environment: environment, sceneResources: scene),
            referenceDate: Date(timeIntervalSince1970: 0)))
    }

    private func publishedGlyphs(_ line: ResolvedTextSource.LineGlyphs) -> [ResolvedTextSource.Glyph] {
        line.glyphs.enumerated().compactMap { index, glyph in
            glyph.glyphIndex != 65535 || index == 0 ? glyph : nil
        }
    }

    private func forEachPublishedGlyph(in lines: [ResolvedTextSource.LineGlyphs],
        callback: (ResolvedTextSource.Glyph, CGPoint) -> Void) {
        for line in lines {
            var index = 0
            ResolvedTextSource.forEachGlyph(in: [line]) { glyph, point in
                if glyph.glyphIndex != 65535 || index == 0 { callback(glyph, point) }
                index += 1
            }
        }
    }

    // ASSERTIONS textAttributedCharacterOwner27Observed fontResourceIdentity27Observed
    func testCanonicalCandidateUsesBaseFontAcrossOriginalFontRuns() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let regular = VUI.Font.file(url, size: 23)
        let large = VUI.Font.file(url, size: 46)
        let cases: [(String, Int, [UInt32])] = [
            ("e\u{301}", 1, [703, 65535]),
            ("e\u{301}\u{323}", 2, [1107, 65535, 65535]),
            ("e\u{323}\u{301}", 2, [1107, 65535, 65535]),
            ("e\u{301}\u{323}", 1, [1107, 65535, 169]),
        ]
        for scale: CGFloat in [1, 2] {
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            environment._contentScaleFactor = scale
            for (string, changed, expected) in cases {
                var text = Text(verbatim: "")
                for (index, scalar) in string.unicodeScalars.enumerated() {
                    text = text + Text(verbatim: String(scalar)).font(index == changed ? large : regular)
                }
                let source = try XCTUnwrap(text._resolve(context:
                    GraphTextResolutionContext(environment: environment, sceneResources: scene),
                    referenceDate: Date(timeIntervalSince1970: 0)))
                let raw = try XCTUnwrap(source.makeGlyphLayout(maxWidth: 500, maximumHeight: 500).lines.first)
                let label = "\(Array(string.unicodeScalars)) changed=\(changed) scale=\(scale)"
                XCTAssertEqual(raw.glyphs.map(\.glyphIndex), expected, label)
                XCTAssertEqual(raw.glyphs.map(\.characterIndex), Array(expected.indices), label)
                XCTAssertEqual(raw.ascender / scale, 43, accuracy: 1e-8, label)
                XCTAssertEqual(raw.descender / scale, -11, accuracy: 1e-8, label)
                for glyph in raw.glyphs where glyph.glyphIndex == 65535 {
                    XCTAssertEqual(glyph.advance, .zero, label)
                    XCTAssertEqual(glyph.positionOffset, .zero, label)
                }
                let layout = source.makeLayout(in: .init(width: 250, height: 250), layoutDirection: .leftToRight)
                XCTAssertEqual(Set(layout.glyphAtoms().flatMap { Array($0.sourceRange) }),
                               Set(expected.indices), label)
            }
        }
    }

    // ASSERTIONS fontFeatureNormalization27Observed textAttributedCharacterOwner27Observed
    func testCanonicalTailComparesSelectedFeaturesInsteadOfRawRequests() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        let provider = VUI.Font.file(url, size: 23).platformFont(in: environment.fontResolutionContext).provider
        for (tag, a, b, equal): (String, UInt32, UInt32, Bool) in [
            ("tnum", 1, 2, true), ("ss01", 1, 2, true), ("smcp", 1, 2, true),
            ("numr", 1, 2, false), ("dnom", 1, 2, false), ("tnum", 1, 0, false),
        ] {
            let base = VUI.Font(typefaceProvider: provider, features: [TypefaceShapingFeature(tag: tag, value: a)!])
            let tail = VUI.Font(typefaceProvider: provider, features: [TypefaceShapingFeature(tag: tag, value: b)!])
            let text = Text(verbatim: "e\u{301}").font(base) + Text(verbatim: "\u{323}").font(tail)
            let source = try XCTUnwrap(text._resolve(context:
                GraphTextResolutionContext(environment: environment, sceneResources: scene),
                referenceDate: Date(timeIntervalSince1970: 0)))
            let raw = try XCTUnwrap(source.makeGlyphLayout(maxWidth: 500, maximumHeight: 500).lines.first)
            XCTAssertEqual(raw.glyphs.map(\.glyphIndex), [1107, 65535, equal ? 169 : 65535], tag)
            XCTAssertEqual(raw.glyphs.map(\.characterIndex), [0, 1, 2], tag)
        }
    }

    // ASSERTIONS fontLanguageConstruction27Observed fontStructureInputs27Observed textAttributedCharacterOwner27Observed
    func testCanonicalTailKeepsOriginalLanguageOnReorderedPrimary() throws {
        for locale in ["en", "ko"] {
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            environment.locale = Locale(identifier: locale)
            func font(_ language: String?) -> VUI.Font {
                let context = environment.fontResolutionContext
                let descriptor = VUI.Font.system(size: 23).resolveDescriptor(in: context)
                    .withTypesetting(language: language)
                let resource = FontResource(descriptor: descriptor, in: context)
                return VUI.Font(provider: FontBox(VUI.Font.PlatformFontProvider(font: resource)))
            }
            for language in [nil, "", "en", "en-US"] as [String?] {
                let text = Text(verbatim: "e\u{301}").font(font(nil)) +
                    Text(verbatim: "\u{323}").font(font(language))
                let source = try XCTUnwrap(text._resolve(context:
                    GraphTextResolutionContext(environment: environment, sceneResources: scene),
                    referenceDate: Date(timeIntervalSince1970: 0)))
                let raw = try XCTUnwrap(source.makeGlyphLayout(maxWidth: 500, maximumHeight: 500).lines.first)
                XCTAssertEqual(raw.glyphs.map(\.glyphIndex), [1107, 65535, language == nil ? 169 : 65535],
                               "\(locale): \(language ?? "absent")")
                XCTAssertEqual(raw.glyphs.map(\.characterIndex), [0, 1, 2])
            }
        }
    }

    // ASSERTIONS fontResourceIdentity27Observed textAttributedCharacterOwner27Observed
    func testCanonicalTailPreservesMemoryResourceOwner() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let bytes = try Data(contentsOf: url)
        let first = VUI.Font.data(bytes, size: 23)
        let independent = VUI.Font.data(bytes, size: 23)
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        for (tail, equal) in [(first, true), (independent, false)] {
            let text = Text(verbatim: "e\u{301}").font(first) + Text(verbatim: "\u{323}").font(tail)
            let source = try XCTUnwrap(text._resolve(context:
                GraphTextResolutionContext(environment: environment, sceneResources: scene),
                referenceDate: Date(timeIntervalSince1970: 0)))
            let raw = try XCTUnwrap(source.makeGlyphLayout(maxWidth: 500, maximumHeight: 500).lines.first)
            XCTAssertEqual(raw.glyphs.map(\.glyphIndex), [1107, 65535, equal ? 169 : 65535])
            XCTAssertEqual(raw.glyphs.map(\.characterIndex), [0, 1, 2])
        }
    }

    // ASSERTIONS textAttributedShapingContext27Observed
    func testPaintIntervalsPreserveShapingContextAndOriginalPublicRuns() throws {
        let cases: [(String, [UInt32], [[Int]], [CGFloat], [(CGFloat, CGFloat)])] = [
            ("a\u{34f}\u{301}", [695], [[0]], [12.5107421875], [(0, 0)]),
            ("e\u{301}", [703], [[0]], [12.1962890625], [(0, 0)]),
            ("fi", [74, 77], [[0], [1]], [7.99609375, 5.5927734375], [(0, 0), (7.99609375, 0)]),
            ("AV", [37, 58], [[0], [1]], [14.02685546875, 14.64453125], [(0, 0), (14.02685546875, 0)]),
            ("x\u{301}\u{323}", [92, 169, 173], [[0], [1], [2]], [11.41015625, 0, 0],
                [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)]),
            ("\u{34f}\u{34f}a", [65535, 69], [[0], [2]], [0, 12.5107421875], [(0, 0), (0, 0)]),
        ]
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let font = VUI.Font.file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 23, weight: .regular)
        for scale: CGFloat in [1, 2] {
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            environment.displayScale = 2
            environment._contentScaleFactor = scale
            for (string, glyphs, runs, widths, positions) in cases {
                var text = Text(verbatim: "")
                for (index, scalar) in string.unicodeScalars.enumerated() {
                    let part = Text(verbatim: String(scalar)).font(font)
                        .foregroundColor(index == 1 ? .red : .blue)
                    text = text + part
                }
                let source = try XCTUnwrap(text._resolve(context:
                    GraphTextResolutionContext(environment: environment, sceneResources: scene),
                    referenceDate: Date(timeIntervalSince1970: 0)))
                let layout = source.makeLayout(in: .init(width: 200, height: 100), layoutDirection: .leftToRight)
                let line = try XCTUnwrap(layout.first)
                let first = try XCTUnwrap(line.first?.characterIndices.first)
                XCTAssertEqual(line.map { $0.characterIndices.map { first.distance(to: $0) } }, runs, string)
                let slices = line.flatMap { Array($0) }
                XCTAssertEqual(slices.count, widths.count, string)
                for (slice, width) in zip(slices, widths) { XCTAssertEqual(slice.typographicBounds.width, width, accuracy: 1e-8, string) }
                let shaped = source.makeGlyphLayout(maxWidth: Int(200 * scale), maximumHeight: 100 * scale).lines
                let raw = try XCTUnwrap(shaped.first)
                XCTAssertEqual(publishedGlyphs(raw).map(\.glyphIndex), glyphs, string)
                var drawn: [CGPoint] = []
                forEachPublishedGlyph(in: shaped) { _, position in drawn.append(position) }
                XCTAssertEqual(drawn.count, positions.count, string)
                for (position, expected) in zip(drawn, positions) {
                    XCTAssertEqual((position.x - raw.originX) / scale, expected.0, accuracy: 1e-8, string)
                    XCTAssertEqual((raw.ascender + raw.originY - position.y) / scale, expected.1, accuracy: 1e-8, string)
                }
                for glyph in raw.glyphs {
                    let color: VUI.Color = glyph.characterIndex == 1 ? .red : .blue
                    XCTAssertEqual(glyph.foregroundColor, VUI.Color(color.resolveHDR(in: environment)), string)
                }
                XCTAssertEqual(Set(layout.glyphAtoms().flatMap { Array($0.sourceRange) }), Set(0..<string.unicodeScalars.count), string)
            }
        }
    }

    // ASSERTIONS textAttributedShapingContext27Observed
    func testRequiredSubstitutionRetainsConsumedPaintRunSlot() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let font = VUI.Font.file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 23, weight: .regular)
        for scale: CGFloat in [1, 2] {
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            environment._contentScaleFactor = scale
            let text = Text(verbatim: "a").font(font).foregroundColor(.blue) +
                Text(verbatim: "\u{34f}").font(font).foregroundColor(.red) +
                Text(verbatim: "\u{301}").font(font).foregroundColor(.blue)
            let source = try XCTUnwrap(text._resolve(context:
                GraphTextResolutionContext(environment: environment, sceneResources: scene),
                referenceDate: Date(timeIntervalSince1970: 0)))
            let raw = try XCTUnwrap(source.makeGlyphLayout(maxWidth: Int(200 * scale),
                maximumHeight: 100 * scale).lines.first)
            XCTAssertEqual(raw.glyphs.map(\.glyphIndex), [695, 65535, 65535])
            XCTAssertEqual(raw.glyphs.map(\.characterIndex), [0, 1, 2])
            XCTAssertEqual(raw.glyphs.map(\.sourceRunIndex), [0, 1, 2])
            for glyph in raw.glyphs.dropFirst() {
                XCTAssertEqual(glyph.advance, .zero)
                XCTAssertEqual(glyph.positionOffset, .zero)
            }
            XCTAssertEqual(publishedGlyphs(raw).map(\.glyphIndex), [695])
            XCTAssertEqual(raw.width / scale, 12.5107421875, accuracy: 1e-8)
        }
    }

    // ASSERTIONS textAttributedShapingContext27Observed
    func testExplicitZeroKernSplitsPositioningWithoutSplittingSourceContext() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let font = VUI.Font.file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 23, weight: .regular)
        for scale: CGFloat in [1, 2] {
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            environment._contentScaleFactor = scale
            let text = Text(verbatim: "x").font(font) +
                Text(verbatim: "\u{301}").font(font).kerning(0) +
                Text(verbatim: "\u{323}").font(font)
            let source = try XCTUnwrap(text._resolve(context:
                GraphTextResolutionContext(environment: environment, sceneResources: scene),
                referenceDate: Date(timeIntervalSince1970: 0)))
            let shaped = source.makeGlyphLayout(maxWidth: Int(200 * scale), maximumHeight: 100 * scale).lines
            let raw = try XCTUnwrap(shaped.first)
            XCTAssertEqual(raw.glyphs.map(\.glyphIndex), [92, 169, 173])
            XCTAssertEqual(raw.glyphs.map(\.characterIndex), [0, 1, 2])
            XCTAssertEqual(raw.glyphs.map { $0.advance.width / scale }, [12.471435546875, 0, 0])
            XCTAssertEqual(raw.width / scale, 12.471435546875, accuracy: 1e-8)
            var positions: [CGPoint] = []
            forEachPublishedGlyph(in: shaped) { _, position in positions.append(position) }
            let expected: [(CGFloat, CGFloat)] = [
                (0, 0), (10.753173828125, 0.6333984375), (12.471435546875, -0.48291015625)
            ]
            XCTAssertEqual(positions.count, expected.count)
            for (position, expected) in zip(positions, expected) {
                XCTAssertEqual((position.x - raw.originX) / scale, expected.0, accuracy: 1e-8)
                XCTAssertEqual((raw.ascender + raw.originY - position.y) / scale, expected.1, accuracy: 1e-8)
            }

            let spacingCases: [(Text, [CGFloat])] = [
                (Text(verbatim: "A").font(font) + Text(verbatim: "V").font(font).kerning(0),
                 [15.00390625, 14.64453125]),
                (Text(verbatim: "A").font(font) + Text(verbatim: "V").font(font).kerning(2),
                 [14.02685546875, 16.64453125]),
                (Text(verbatim: "A").font(font) + Text(verbatim: "V").font(font).tracking(0),
                 [14.02685546875, 14.64453125]),
                (Text(verbatim: "A").font(font) + Text(verbatim: "V").font(font).tracking(2),
                 [14.02685546875, 16.64453125]),
            ]
            for (text, advances) in spacingCases {
                let source = try XCTUnwrap(text._resolve(context:
                    GraphTextResolutionContext(environment: environment, sceneResources: scene),
                    referenceDate: Date(timeIntervalSince1970: 0)))
                let line = try XCTUnwrap(source.makeGlyphLayout(maxWidth: Int(200 * scale),
                    maximumHeight: 100 * scale).lines.first)
                XCTAssertEqual(line.glyphs.map(\.glyphIndex), [37, 58])
                XCTAssertEqual(line.glyphs.map(\.characterIndex), [0, 1])
                XCTAssertEqual(line.glyphs.map { $0.advance.width / scale }, advances)
                XCTAssertEqual(line.width / scale, advances.reduce(0, +), accuracy: 1e-8)
            }
        }
    }

    // ASSERTIONS textAttributedShapingContext27Observed
    func testCrossFontMarksUseEveryOriginalFaceForGeometry() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let regular = VUI.Font.file(url, size: 23, weight: .regular)
        let large = VUI.Font.file(url, size: 46, weight: .regular)
        for scale: CGFloat in [1, 2] {
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            environment._contentScaleFactor = scale
            let text = Text(verbatim: "x").font(regular) +
                Text(verbatim: "\u{301}").font(large) +
                Text(verbatim: "\u{323}").font(regular)
            let source = try XCTUnwrap(text._resolve(context:
                GraphTextResolutionContext(environment: environment, sceneResources: scene),
                referenceDate: Date(timeIntervalSince1970: 0)))
            let lines = source.makeGlyphLayout(
                maxWidth: Int(200 * scale), maximumHeight: 100 * scale
            ).lines
            let raw = try XCTUnwrap(lines.first)
            XCTAssertEqual(raw.glyphs.map(\.glyphIndex), [92, 169, 173])
            XCTAssertEqual(raw.glyphs.map(\.characterIndex), [0, 1, 2])
            XCTAssertEqual(raw.glyphs.map { $0.advance.width / scale },
                           [15.80126953125, 0, 0])
            XCTAssertEqual(raw.width / scale, 15.80126953125, accuracy: 1e-8)
            var positions: [CGPoint] = []
            forEachPublishedGlyph(in: lines) { _, position in positions.append(position) }
            let expected: [(CGFloat, CGFloat)] = [
                (0, 0),
                (15.80126953125, -10.8845703125),
                (12.471435546875, -0.48291015625),
            ]
            XCTAssertEqual(positions.count, expected.count)
            for (position, expected) in zip(positions, expected) {
                XCTAssertEqual((position.x - raw.originX) / scale, expected.0, accuracy: 1e-8)
                XCTAssertEqual((raw.ascender + raw.originY - position.y) / scale,
                               expected.1, accuracy: 1e-8)
            }
        }
    }

    // ASSERTIONS textLinePublication27Observed
    func testLinePublicationPreservesFontMetricsAndOriginalRunBoundaries() throws {
        let cases: [(String, Range<Int>, Bool, [[Int]], CGFloat)] = [
            ("x\u{34f}a", 1..<2, true, [[0], [2]], 23.9208984375),
            ("x\u{34f}a", 1..<3, true, [[0], [2]], 36.431640625),
            ("\u{34f}a", 0..<1, true, [[0], [1]], 12.5107421875),
            ("x\u{34f}", 1..<2, true, [[0]], 11.41015625),
            ("\u{34f}\u{34f}", 1..<2, true, [[0]], 0),
            ("\u{34f}\u{34f}a", 1..<2, true, [[0], [2]], 12.5107421875),
            ("a\u{34f}\u{301}", 1..<2, true, [[0], [2]], 12.5107421875),
            ("x \u{34f}a", 2..<3, true, [[0, 1], [3]], 29.6259765625),
            ("x\u{34f}a", 1..<3, false, [[0], [2]], 23.9208984375),
            ("x\u{34f}a", 1..<2, false, [[0], [2]], 23.9208984375),
            ("\u{34f}\u{34f}a", 1..<3, false, [[0], [2]], 12.5107421875),
            ("\u{34f}\u{34f}a", 0..<1, false, [[0], [2]], 12.5107421875),
        ]
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let regular = VUI.Font.file(url, size: 23, weight: .regular)
        let large = VUI.Font.file(url, size: 46, weight: .regular)
        for scale: CGFloat in [1, 2] {
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            environment.displayScale = 2
            environment._contentScaleFactor = scale
            for (string, selected, changesFont, expectedRuns, width) in cases {
                let scalars = Array(string.unicodeScalars)
                let boundaries = Set([0, selected.lowerBound, selected.upperBound, scalars.count]).sorted()
                var text = Text(verbatim: "")
                for (start, end) in zip(boundaries, boundaries.dropFirst()) {
                    var part = Text(verbatim: String(String.UnicodeScalarView(scalars[start..<end])))
                        .font(changesFont && selected.contains(start) ? large : regular)
                    if !changesFont && selected.contains(start) { part = part.foregroundColor(.red) }
                    text = text + part
                }
                let source = try XCTUnwrap(text._resolve(context:
                    GraphTextResolutionContext(environment: environment, sceneResources: scene),
                    referenceDate: Date(timeIntervalSince1970: 0)))
                let layout = source.makeLayout(in: CGSize(width: 200, height: 100), layoutDirection: .leftToRight)
                let line = try XCTUnwrap(layout.first)
                let first = try XCTUnwrap(line.first?.characterIndices.first)
                let label = "\(string.unicodeScalars.map(\.value)) font=\(changesFont) range=\(selected) scale=\(scale)"
                XCTAssertEqual(layout.count, 1, label)
                XCTAssertEqual(line.map { $0.characterIndices.map { first.distance(to: $0) } }, expectedRuns, label)
                XCTAssertEqual(line.typographicBounds.width, width, accuracy: 1e-8, label)
                XCTAssertEqual(line.typographicBounds.ascent, changesFont ? 43 : 21, accuracy: 1e-8, label)
                XCTAssertEqual(line.typographicBounds.descent, changesFont ? 11 : 6, accuracy: 1e-8, label)
                for (run, expected) in zip(line, expectedRuns) {
                    for (index, slice) in run.enumerated() {
                        XCTAssertEqual(slice.characterIndices.map { first.distance(to: $0) }, [expected[index]], label)
                    }
                }
                let raw = try XCTUnwrap(source.makeGlyphLayout(maxWidth: Int(200 * scale),
                    maximumHeight: 100 * scale).lines.first)
                XCTAssertEqual(raw.glyphs.map(\.characterIndex), Array(scalars.indices), label)
                for glyph in raw.glyphs where glyph.glyphIndex == 65535 {
                    XCTAssertEqual(glyph.advance, .zero, label)
                    XCTAssertEqual(glyph.positionOffset, .zero, label)
                }
                // Public glyph projection must not remove source slots from
                // the independent hit-testing and selection representation.
                let atoms = layout.glyphAtoms()
                XCTAssertEqual(Set(atoms.flatMap { Array($0.sourceRange) }), Set(scalars.indices), label)
                XCTAssertEqual(atoms.map(\.sourceRange), source.glyphAtoms(in:
                    CGSize(width: 200, height: 100)).map(\.sourceRange), label)
            }
        }
    }

    // ASSERTIONS textLinePublication27Observed
    func testRawSlotReflowAndCopiedTokenPreservePublicationState() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"
        )
        let regular = VUI.Font.file(url, size: 23, weight: .regular)
        let large = VUI.Font.file(url, size: 46, weight: .regular)

        func part(_ value: String, font: VUI.Font) -> Text {
            Text(verbatim: value).font(font)
        }

        for scale: CGFloat in [1, 2] {
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            environment.displayScale = 2
            environment._contentScaleFactor = scale

            let colorOnly = part("x ", font: regular) +
                part("\u{34f}", font: regular).foregroundColor(.red) +
                part("a", font: regular)
            let colorSource = try XCTUnwrap(colorOnly._resolve(context:
                GraphTextResolutionContext(environment: environment, sceneResources: scene),
                referenceDate: Date(timeIntervalSince1970: 0)))
            let colorLayout = colorSource.makeLayout(
                in: CGSize(width: 15, height: 100), layoutDirection: .leftToRight
            )
            let colorStart = try XCTUnwrap(colorLayout.first?.first?.characterIndices.first)
            XCTAssertEqual(colorLayout.map { line in
                line.map { run in run.characterIndices.map { colorStart.distance(to: $0) } }
            }, [[[0, 1]], [[2]], [[3]]])
            XCTAssertEqual(colorLayout.map(\.typographicBounds.width),
                           [15, 0, 12.5107421875])
            XCTAssertEqual(colorLayout.map(\.origin.x), [0, 0, 0])
            XCTAssertEqual(zip(colorLayout, colorLayout.dropFirst()).map {
                $1.origin.y - $0.origin.y
            }, [27, 27])
            let colorRaw = colorSource.makeGlyphLayout(
                maxWidth: Int(15 * scale), maximumHeight: 100 * scale
            ).lines
            XCTAssertEqual(colorRaw.map { $0.glyphs.map(\.glyphIndex) },
                           [[92, 4], [65535], [69]])
            XCTAssertEqual(colorRaw.map { $0.glyphs.map(\.characterIndex) },
                           [[0, 1], [2], [3]])

            let copied = part("x ", font: regular) +
                part("\u{34f}", font: large) +
                part("a", font: regular)
            let copiedSource = try XCTUnwrap(copied._resolve(context:
                GraphTextResolutionContext(environment: environment, sceneResources: scene),
                referenceDate: Date(timeIntervalSince1970: 0)))
            let copiedLayout = copiedSource.makeLayout(
                in: CGSize(width: 15, height: 100), layoutDirection: .leftToRight
            )
            let copiedStart = try XCTUnwrap(copiedLayout.first?.first?.characterIndices.first)
            XCTAssertEqual(copiedLayout.map { line in
                line.map { run in run.characterIndices.map { copiedStart.distance(to: $0) } }
            }, [[[0, 1]], [[], [3], [4]]])
            XCTAssertEqual(copiedLayout.map(\.typographicBounds.width), [15, 15])
            XCTAssertEqual(copiedLayout.map(\.origin.x), [0, 0])
            XCTAssertEqual(copiedLayout[1].origin.y - copiedLayout[0].origin.y, 49)
            let copiedRaw = copiedSource.makeGlyphLayout(
                maxWidth: Int(15 * scale), maximumHeight: 100 * scale
            ).lines
            XCTAssertEqual(copiedRaw.map { $0.glyphs.map(\.glyphIndex) },
                           [[92, 4], [65535, 69, 400]])
            XCTAssertEqual(copiedRaw.map { $0.glyphs.map(\.characterIndex) },
                           [[0, 1], [2, 3, 4]])
        }
    }

    // ASSERTIONS textAttributedShapingContext27Observed textLinePublication27Observed
    func testDeletedRawSlotsDoNotAcquireTrackingOrKernAdvance() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let font = VUI.Font.file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 23, weight: .regular)
        for scale: CGFloat in [1, 2] {
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            environment._contentScaleFactor = scale
            for tracking in [false, true] {
                for amount: CGFloat in [0, 2] {
                    let hidden = Text(verbatim: "\u{34f}").font(font)
                    let middle = tracking ? hidden.tracking(amount) : hidden.kerning(amount)
                    let text = hidden + middle + Text(verbatim: "a").font(font)
                    let source = try XCTUnwrap(text._resolve(context:
                        GraphTextResolutionContext(environment: environment, sceneResources: scene),
                        referenceDate: Date(timeIntervalSince1970: 0)))
                    let line = try XCTUnwrap(source.makeGlyphLayout(maxWidth: Int(200 * scale),
                        maximumHeight: 100 * scale).lines.first)
                    XCTAssertEqual(line.glyphs.map(\.glyphIndex), [65535, 65535, 69])
                    XCTAssertEqual(line.glyphs.map(\.characterIndex), [0, 1, 2])
                    XCTAssertEqual(line.glyphs[0].advance, .zero)
                    XCTAssertEqual(line.glyphs[1].advance, .zero)
                    XCTAssertEqual(line.width / scale, 12.5107421875, accuracy: 1e-8)
                    let layout = source.makeLayout(in: .init(width: 200, height: 100), layoutDirection: .leftToRight)
                    let published = try XCTUnwrap(layout.first)
                    let first = try XCTUnwrap(published.first?.characterIndices.first)
                    XCTAssertEqual(published.map { $0.characterIndices.map { first.distance(to: $0) } }, [[0], [2]])
                    XCTAssertEqual(published.typographicBounds.width, 12.5107421875, accuracy: 1e-8)
                }
            }
        }
    }

    // ASSERTIONS textDefaultIgnorableEncoding27Observed
    func testDefaultIgnorableGlyphSourcesAndPositionsReachPublicSlices() throws {
        let cases: [(String, [UInt32], [Int], [CGFloat], [(CGFloat, CGFloat)])] = [
            ("a\u{34f}\u{301}", [695], [0], [12.5107421875], [(0, 0)]),
            ("q\u{34f}\u{301}", [85, 169], [0, 2], [13.072265625, 0], [(0, 0), (12.38720703125, 0)]),
            ("f\u{34f}i", [471], [0], [12.74658203125], [(0, 0)]),
            ("\u{34f}a", [65535, 69], [0, 1], [0, 12.5107421875], [(0, 0), (0, 0)]),
            ("a\u{34f}", [69], [0], [12.5107421875], [(0, 0)]),
            ("\u{34f}", [65535], [0], [0], [(0, 0)]),
            ("x\u{34f}\u{301}\u{323}", [92, 169, 173], [0, 2, 3], [11.41015625, 0, 0], [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)]),
            ("a\u{301}\u{34f}\u{323}", [695, 173], [0, 3], [12.5107421875, 0], [(0, 0), (12.34228515625, 0)]),
            ("a\u{200b}\u{301}", [695], [0], [12.5107421875], [(0, 0)]),
            ("q\u{200b}\u{301}", [85, 169], [0, 2], [13.072265625, 0], [(0, 0), (12.38720703125, 0)]),
            ("f\u{200b}i", [471], [0], [12.74658203125], [(0, 0)]),
            ("\u{200b}a", [65535, 69], [0, 1], [0, 12.5107421875], [(0, 0), (0, 0)]),
            ("a\u{200b}", [69], [0], [12.5107421875], [(0, 0)]),
            ("\u{200b}", [65535], [0], [0], [(0, 0)]),
            ("x\u{200b}\u{301}\u{323}", [92, 169, 173], [0, 2, 3], [11.41015625, 0, 0], [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)]),
            ("a\u{301}\u{200b}\u{323}", [695, 173], [0, 3], [12.5107421875, 0], [(0, 0), (12.34228515625, 0)]),
            ("a\u{2060}\u{301}", [695], [0], [12.5107421875], [(0, 0)]),
            ("q\u{2060}\u{301}", [85, 169], [0, 2], [13.072265625, 0], [(0, 0), (12.38720703125, 0)]),
            ("f\u{2060}i", [471], [0], [12.74658203125], [(0, 0)]),
            ("\u{2060}a", [65535, 69], [0, 1], [0, 12.5107421875], [(0, 0), (0, 0)]),
            ("a\u{2060}", [69], [0], [12.5107421875], [(0, 0)]),
            ("\u{2060}", [65535], [0], [0], [(0, 0)]),
            ("x\u{2060}\u{301}\u{323}", [92, 169, 173], [0, 2, 3], [11.41015625, 0, 0], [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)]),
            ("a\u{301}\u{2060}\u{323}", [695, 173], [0, 3], [12.5107421875, 0], [(0, 0), (12.34228515625, 0)]),
            ("a\u{feff}\u{301}", [695], [0], [12.5107421875], [(0, 0)]),
            ("q\u{feff}\u{301}", [85, 169], [0, 2], [13.072265625, 0], [(0, 0), (12.38720703125, 0)]),
            ("f\u{feff}i", [471], [0], [12.74658203125], [(0, 0)]),
            ("\u{feff}a", [65535, 69], [0, 1], [0, 12.5107421875], [(0, 0), (0, 0)]),
            ("a\u{feff}", [69], [0], [12.5107421875], [(0, 0)]),
            ("\u{feff}", [65535], [0], [0], [(0, 0)]),
            ("x\u{feff}\u{301}\u{323}", [92, 169, 173], [0, 2, 3], [11.41015625, 0, 0], [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)]),
            ("a\u{301}\u{feff}\u{323}", [695, 173], [0, 3], [12.5107421875, 0], [(0, 0), (12.34228515625, 0)]),
            ("a\u{fe0e}\u{301}", [695], [0], [12.5107421875], [(0, 0)]),
            ("q\u{fe0e}\u{301}", [85, 169], [0, 2], [13.072265625, 0], [(0, 0), (12.38720703125, 0)]),
            ("f\u{fe0e}i", [471], [0], [12.74658203125], [(0, 0)]),
            ("\u{fe0e}a", [65535, 69], [0, 1], [0, 12.5107421875], [(0, 0), (0, 0)]),
            ("a\u{fe0e}", [69], [0], [12.5107421875], [(0, 0)]),
            ("\u{fe0e}", [65535], [0], [0], [(0, 0)]),
            ("x\u{fe0e}\u{301}\u{323}", [92, 169, 173], [0, 2, 3], [11.41015625, 0, 0], [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)]),
            ("a\u{301}\u{fe0e}\u{323}", [695, 173], [0, 3], [12.5107421875, 0], [(0, 0), (12.34228515625, 0)]),
            ("a\u{e0100}\u{301}", [695], [0], [12.5107421875], [(0, 0)]),
            ("q\u{e0100}\u{301}", [85, 169], [0, 2], [13.072265625, 0], [(0, 0), (12.38720703125, 0)]),
            ("f\u{e0100}i", [471], [0], [12.74658203125], [(0, 0)]),
            ("\u{e0100}a", [65535, 69], [0, 1], [0, 12.5107421875], [(0, 0), (0, 0)]),
            ("a\u{e0100}", [69], [0], [12.5107421875], [(0, 0)]),
            ("\u{e0100}", [65535], [0], [0], [(0, 0)]),
            ("x\u{e0100}\u{301}\u{323}", [92, 169, 173], [0, 2, 3], [11.41015625, 0, 0], [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)]),
            ("a\u{301}\u{e0100}\u{323}", [695, 173], [0, 3], [12.5107421875, 0], [(0, 0), (12.34228515625, 0)]),
            ("a\u{ad}\u{301}", [695], [0], [12.5107421875], [(0, 0)]),
            ("q\u{ad}\u{301}", [85, 169], [0, 2], [13.072265625, 0], [(0, 0), (12.38720703125, 0)]),
            ("f\u{ad}i", [471], [0], [12.74658203125], [(0, 0)]),
            ("\u{ad}a", [65535, 69], [0, 1], [0, 12.5107421875], [(0, 0), (0, 0)]),
            ("a\u{ad}", [69], [0], [12.5107421875], [(0, 0)]),
            ("\u{ad}", [65535], [0], [0], [(0, 0)]),
            ("x\u{ad}\u{301}\u{323}", [92, 169, 173], [0, 2, 3], [11.41015625, 0, 0], [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)]),
            ("a\u{301}\u{ad}\u{323}", [695, 173], [0, 3], [12.5107421875, 0], [(0, 0), (12.34228515625, 0)]),
            ("a\u{2061}\u{301}", [695], [0], [12.5107421875], [(0, 0)]),
            ("q\u{2061}\u{301}", [85, 169], [0, 2], [13.072265625, 0], [(0, 0), (12.38720703125, 0)]),
            ("f\u{2061}i", [471], [0], [12.74658203125], [(0, 0)]),
            ("\u{2061}a", [65535, 69], [0, 1], [0, 12.5107421875], [(0, 0), (0, 0)]),
            ("a\u{2061}", [69], [0], [12.5107421875], [(0, 0)]),
            ("\u{2061}", [65535], [0], [0], [(0, 0)]),
            ("x\u{2061}\u{301}\u{323}", [92, 169, 173], [0, 2, 3], [11.41015625, 0, 0], [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)]),
            ("a\u{301}\u{2061}\u{323}", [695, 173], [0, 3], [12.5107421875, 0], [(0, 0), (12.34228515625, 0)]),
        ]
        for scale: CGFloat in [1, 2] {
            for (text, glyphs, indices, advances, expected) in cases {
                let utf16Offsets = text.unicodeScalars.reduce(into: [0]) {
                    $0.append($0.last! + $1.utf16.count)
                }
                let publicIndices = indices.map { utf16Offsets[$0] }
                let source = try resolve(text, scale: scale)
                let layout = source.makeLayout(in: CGSize(width: 200, height: 100), layoutDirection: .leftToRight)
                let publicLine = try XCTUnwrap(layout.first)
                XCTAssertEqual(publicLine.count, 1, text)
                let run = try XCTUnwrap(publicLine.first)
                let first = try XCTUnwrap(run.characterIndices.first)
                XCTAssertEqual(run.characterIndices.map { first.distance(to: $0) }, publicIndices, text)
                XCTAssertEqual(run.count, glyphs.count, text)
                for (index, slice) in run.enumerated() {
                    XCTAssertEqual(slice.characterIndices.map { first.distance(to: $0) }, [publicIndices[index]], text)
                    XCTAssertEqual(slice.typographicBounds.width, advances[index], accuracy: 1e-8, text)
                }
                let lines = source.makeGlyphLayout(maxWidth: Int(200 * scale), maximumHeight: 100 * scale).lines
                let line = try XCTUnwrap(lines.first)
                XCTAssertEqual(publishedGlyphs(line).map(\.glyphIndex), glyphs, text)
                var positions: [CGPoint] = []
                forEachPublishedGlyph(in: lines) { _, position in positions.append(position) }
                XCTAssertEqual(positions.count, expected.count, text)
                for (position, value) in zip(positions, expected) {
                    XCTAssertEqual((position.x - line.originX) / scale, value.0, accuracy: 1e-8, text)
                    XCTAssertEqual((line.ascender + line.originY - position.y) / scale, value.1, accuracy: 1e-8, text)
                }
            }
        }
    }

    // ASSERTIONS textDefaultIgnorableEncoding27Observed
    func testUncombinedRangeGeometryReachesPublicSlices() throws {
        typealias Expected = (
            text: String,
            rawGlyphs: [UInt32],
            rawIndices: [Int],
            rawAdvances: [CGFloat],
            publicGlyphs: [UInt32],
            publicIndices: [Int],
            publicAdvances: [CGFloat],
            positions: [(CGFloat, CGFloat)]
        )
        let cases: [Expected] = [
            ("a\u{200c}\u{301}", [69, 4, 169], [0, 1, 2],
             [12.5107421875, 7.900634765625, 0], [69, 4, 169], [0, 1, 2],
             [12.5107421875, 7.900634765625, 0],
             [(0, 0), (12.5107421875, 0), (20.411376953125, 0)]),
            ("q\u{200c}\u{301}", [85, 4, 169], [0, 1, 2],
             [13.072265625, 7.900634765625, 0], [85, 4, 169], [0, 1, 2],
             [13.072265625, 7.900634765625, 0],
             [(0, 0), (13.072265625, 0), (20.972900390625, 0)]),
            ("x\u{200c}\u{301}\u{323}", [92, 4, 169, 173], [0, 1, 2, 3],
             [11.41015625, 9.618896484375, 0, 0], [92, 4, 169, 173], [0, 1, 2, 3],
             [11.41015625, 9.618896484375, 0, 0],
             [(0, 0), (11.41015625, 0), (19.310791015625, 0),
              (21.029052734375, -0.48291015625)]),
            ("a\u{200d}\u{301}", [69, 4, 169], [0, 1, 2],
             [12.5107421875, 5.705078125, 0], [69, 4, 169], [0, 1, 2],
             [12.5107421875, 5.705078125, 0],
             [(0, 0), (12.5107421875, 0), (18.2158203125, 0)]),
            ("a\u{301}\u{200c}\u{323}", [695, 65535, 4, 173], [0, 1, 2, 3],
             [12.5107421875, 0, 5.705078125, 0], [695, 4, 173], [0, 2, 3],
             [12.5107421875, 5.705078125, 0],
             [(0, 0), (12.5107421875, 0), (18.2158203125, 0)]),
        ]
        let fontData = try Self.mappedSpaceFontData()
        for scale: CGFloat in [1, 2] {
            let backend = try XCTUnwrap(VVD.Font(data: fontData))
            backend.setPointSize(23, dpi: (UInt32(72 * scale), UInt32(72 * scale)))
            let font = VUI.Font(vector: backend)
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            environment._contentScaleFactor = scale
            for value in cases {
                let text = value.text
                let source = try XCTUnwrap(Text(verbatim: text).font(font)._resolve(context:
                    GraphTextResolutionContext(environment: environment, sceneResources: scene),
                    referenceDate: Date(timeIntervalSince1970: 0)))
                let rawLines = source.makeGlyphLayout(maxWidth: Int(200 * scale),
                                                      maximumHeight: 100 * scale).lines
                let raw = try XCTUnwrap(rawLines.first)
                XCTAssertEqual(raw.glyphs.map(\.glyphIndex), value.rawGlyphs, text)
                XCTAssertEqual(raw.glyphs.map(\.characterIndex), value.rawIndices, text)
                XCTAssertEqual(raw.glyphs.map { $0.advance.width / scale }, value.rawAdvances, text)

                let layout = source.makeLayout(in: CGSize(width: 200, height: 100),
                                               layoutDirection: .leftToRight)
                let line = try XCTUnwrap(layout.first)
                let run = try XCTUnwrap(line.first)
                let first = try XCTUnwrap(run.characterIndices.first)
                XCTAssertEqual(run.characterIndices.map { first.distance(to: $0) },
                               value.publicIndices, text)
                XCTAssertEqual(run.count, value.publicGlyphs.count, text)
                for (index, slice) in run.enumerated() {
                    XCTAssertEqual(slice.typographicBounds.width, value.publicAdvances[index],
                                   accuracy: 1e-8, text)
                }

                var positions: [CGPoint] = []
                forEachPublishedGlyph(in: rawLines) { _, position in positions.append(position) }
                XCTAssertEqual(publishedGlyphs(raw).map(\.glyphIndex), value.publicGlyphs, text)
                XCTAssertEqual(positions.count, value.positions.count, text)
                for (position, expected) in zip(positions, value.positions) {
                    XCTAssertEqual((position.x - raw.originX) / scale, expected.0,
                                   accuracy: 1e-8, text)
                    XCTAssertEqual((raw.ascender + raw.originY - position.y) / scale, expected.1,
                                   accuracy: 1e-8, text)
                }
            }
        }
    }

    // ASSERTIONS textCanonicalMarks27Observed
    func testLeadingMarkAdvancesReachPublicSlices() throws {
        typealias Expected = (
            text: String,
            rawGlyphs: [UInt32],
            rawIndices: [Int],
            rawAdvances: [CGFloat],
            publicGlyphs: [UInt32],
            publicIndices: [Int],
            publicAdvances: [CGFloat],
            positions: [(CGFloat, CGFloat)]
        )
        let cases: [Expected] = [
            ("\u{301}", [169], [0], [7.3896484375],
             [169], [0], [7.3896484375], [(7.3896484375, 0)]),
            ("\u{301}\u{300}", [169, 168], [0, 1], [7.3896484375, 0],
             [169, 168], [0, 1], [7.3896484375, 0],
             [(7.3896484375, 0), (6.9853515625, 3.94189453125)]),
            ("\u{301}a", [169, 69], [0, 1], [7.3896484375, 12.5107421875],
             [169, 69], [0, 1], [7.3896484375, 12.5107421875],
             [(7.3896484375, 0), (7.3896484375, 0)]),
            ("\u{301}\u{323}", [169, 173], [0, 1], [10.461181640625, 0],
             [169, 173], [0, 1], [10.461181640625, 0],
             [(7.3896484375, 0), (10.461181640625, 13.46533203125)]),
            ("\u{301}\u{323}e\u{301}\u{323}", [169, 173, 1107, 65535, 169],
             [0, 1, 2, 3, 4], [7.3896484375, 0, 12.1962890625, 0, 0],
             [169, 173, 1107, 169], [0, 1, 2, 4],
             [7.3896484375, 0, 12.1962890625, 0],
             [(7.3896484375, 0), (10.461181640625, 13.46533203125),
              (7.3896484375, 0), (20.09130859375, 0)]),
        ]
        for scale: CGFloat in [1, 2] {
            for value in cases {
                let text = value.text
                let source = try resolve(text, scale: scale)
                let lines = source.makeGlyphLayout(maxWidth: Int(200 * scale),
                                                   maximumHeight: 100 * scale).lines
                let raw = try XCTUnwrap(lines.first)
                XCTAssertEqual(raw.glyphs.map(\.glyphIndex), value.rawGlyphs, text)
                XCTAssertEqual(raw.glyphs.map(\.characterIndex), value.rawIndices, text)
                XCTAssertEqual(raw.glyphs.map { $0.advance.width / scale }, value.rawAdvances, text)
                XCTAssertEqual(raw.width / scale, value.rawAdvances.reduce(0, +),
                               accuracy: 1e-8, text)

                let layout = source.makeLayout(in: CGSize(width: 200, height: 100),
                                               layoutDirection: .leftToRight)
                let line = try XCTUnwrap(layout.first)
                let run = try XCTUnwrap(line.first)
                let first = try XCTUnwrap(run.characterIndices.first)
                XCTAssertEqual(run.characterIndices.map { first.distance(to: $0) },
                               value.publicIndices, text)
                XCTAssertEqual(run.count, value.publicGlyphs.count, text)
                for (index, slice) in run.enumerated() {
                    XCTAssertEqual(slice.typographicBounds.width, value.publicAdvances[index],
                                   accuracy: 1e-8, text)
                }

                var positions: [CGPoint] = []
                forEachPublishedGlyph(in: lines) { _, position in positions.append(position) }
                XCTAssertEqual(publishedGlyphs(raw).map(\.glyphIndex), value.publicGlyphs, text)
                XCTAssertEqual(positions.count, value.positions.count, text)
                for (position, expected) in zip(positions, value.positions) {
                    XCTAssertEqual((position.x - raw.originX) / scale, expected.0,
                                   accuracy: 1e-8, text)
                    XCTAssertEqual((raw.ascender + raw.originY - position.y) / scale, expected.1,
                                   accuracy: 1e-8, text)
                }
            }
        }
    }

    // ASSERTIONS textCanonicalMarks27Observed
    func testCanonicalGlyphSourcesAndPositionsReachPublicSlices() throws {
        let cases: [(String, [UInt32], [Int], [CGFloat], [(CGFloat, CGFloat)])] = [
            ("x\u{301}\u{323}", [92, 169, 173], [0, 1, 2],
             [11.41015625, 0, 0], [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)]),
            ("e\u{301}\u{323}", [1107, 169], [0, 2],
             [12.1962890625, 0], [(0, 0), (12.70166015625, 0)]),
            ("\u{e9}\u{323}", [703, 173], [0, 1],
             [12.1962890625, 0], [(0, 0), (13.08349609375, 0)]),
            ("q\u{323}\u{301}", [85, 173, 169], [0, 1, 2],
             [13.072265625, 0, 0], [(0, 0), (16.99169921875, -4.57080078125), (12.38720703125, 0)]),
            ("e\u{301}\u{323}\u{300}", [1107, 169, 168], [0, 2, 3],
             [12.1962890625, 0, 0], [(0, 0), (12.70166015625, 0), (12.29736328125, 3.94189453125)]),
            ("x e\u{301}\u{323} z", [92, 4, 1107, 169, 4, 94], [0, 1, 2, 4, 5, 6],
             [11.41015625, 5.705078125, 12.1962890625, 0, 5.705078125, 11.41015625], [(0, 0), (11.41015625, 0), (17.115234375, 0), (29.81689453125, 0), (29.3115234375, 0), (35.0166015625, 0)]),
        ]
        for scale: CGFloat in [1, 2] {
            for (text, glyphs, indices, advances, expected) in cases {
                let source = try resolve(text, scale: scale)
                let layout = source.makeLayout(in: CGSize(width: 200, height: 100), layoutDirection: .leftToRight)
                let publicLine = try XCTUnwrap(layout.first)
                XCTAssertEqual(publicLine.count, 1, text)
                let run = try XCTUnwrap(publicLine.first)
                let first = try XCTUnwrap(run.characterIndices.first)
                XCTAssertEqual(run.characterIndices.map { first.distance(to: $0) }, indices, text)
                XCTAssertEqual(run.count, glyphs.count, text)
                for (index, slice) in run.enumerated() {
                    XCTAssertEqual(slice.characterIndices.map { first.distance(to: $0) }, [indices[index]], text)
                    XCTAssertEqual(slice.typographicBounds.width, advances[index], accuracy: 1e-8, text)
                }
                let lines = source.makeGlyphLayout(maxWidth: Int(200 * scale), maximumHeight: 100 * scale).lines
                let line = try XCTUnwrap(lines.first)
                XCTAssertEqual(publishedGlyphs(line).map(\.glyphIndex), glyphs, text)
                var positions: [CGPoint] = []
                forEachPublishedGlyph(in: lines) { _, position in positions.append(position) }
                XCTAssertEqual(positions.count, expected.count, text)
                for (position, value) in zip(positions, expected) {
                    XCTAssertEqual((position.x - line.originX) / scale, value.0, accuracy: 1e-8, text)
                    XCTAssertEqual((line.ascender + line.originY - position.y) / scale, value.1, accuracy: 1e-8, text)
                }
            }
        }
    }

    // ASSERTIONS textCombiningGeometry27Observed
    func testCombiningGlyphPositionsReachResolvedDrawingCoordinates() throws {
        let cases: [(String, [(CGFloat, CGFloat)])] = [
            ("q\u{301}x", [(0, 0), (-0.0575, 4.8438), (13.685, 0)]),
            ("가\u{301}\u{300} 나", [(0, 0), (3.68, 10.801375), (3.68, 20.72875), (21.16, 0), (26.22, 0)]),
            ("a\u{20dd}", [(4.692, 0), (22.08, -2.6795)]),
        ]
        for scale: CGFloat in [1, 2] {
            for (text, expected) in cases {
                let source = try resolve(text, scale: scale, cjk: true)
                let lines = source.makeGlyphLayout(maxWidth: Int(200 * scale), maximumHeight: 100 * scale).lines
                XCTAssertEqual(lines.count, 1)
                let line = try XCTUnwrap(lines.first)
                var positions: [CGPoint] = []
                ResolvedTextSource.forEachGlyph(in: lines) { _, position in positions.append(position) }
                XCTAssertEqual(positions.count, expected.count)
                for (position, value) in zip(positions, expected) {
                    XCTAssertEqual((position.x - line.originX) / scale, value.0, accuracy: 1e-8)
                    XCTAssertEqual((line.ascender + line.originY - position.y) / scale, value.1, accuracy: 1e-8)
                }
            }
        }
    }

    // ASSERTIONS textParagraphLineBreak27Observed textLineBoundaryBackend27Observed
    func testCJKLineBreakCandidatesRetainPunctuationAndWordArbitration() throws {
        let cases: [(String, CGFloat, Bool, [Int], [CGFloat])] = [
            ("A A A A 漢字", 45, true, [4, 4, 1, 1], [36.524, 36.524, 23, 23]),
            ("A A A A 漢字", 45, false, [4, 4, 1, 1], [36.524, 36.524, 23, 23]),
            ("A A A A 漢字", 90, true, [6, 4], [54.786, 64.262]),
            ("A A A A 漢字", 90, false, [8, 2], [73.048, 46]),
            ("A A A A 漢字", 110, true, [8, 2], [73.048, 46]),
            ("A A A A 漢字", 110, false, [9, 1], [96.048, 23]),
            ("A A A A 日本語", 45, true, [4, 4, 1, 1, 1], [36.524, 36.524, 23, 23, 23]),
            ("A A A A 日本語", 45, false, [4, 4, 1, 1, 1], [36.524, 36.524, 23, 23, 23]),
            ("A A A A 日本語", 90, true, [8, 3], [73.048, 69]),
            ("A A A A 日本語", 90, false, [8, 3], [73.048, 69]),
            ("A A A A 日本語", 110, true, [9, 2], [96.048, 46]),
            ("A A A A 日本語", 110, false, [9, 2], [96.048, 46]),
            ("漢字漢字", 45, true, [1, 1, 1, 1], [23, 23, 23, 23]),
            ("漢字漢字", 45, false, [1, 1, 1, 1], [23, 23, 23, 23]),
            ("漢字漢字", 90, true, [2, 2], [46, 46]),
            ("漢字漢字", 90, false, [3, 1], [69, 23]),
            ("漢字漢字", 110, true, [4], [92]),
            ("漢字漢字", 110, false, [4], [92]),
            ("日本語日本語", 45, true, [1, 1, 1, 1, 1, 1], [23, 23, 23, 23, 23, 23]),
            ("日本語日本語", 45, false, [1, 1, 1, 1, 1, 1], [23, 23, 23, 23, 23, 23]),
            ("日本語日本語", 90, true, [3, 3], [69, 69]),
            ("日本語日本語", 90, false, [3, 3], [69, 69]),
            ("日本語日本語", 110, true, [4, 2], [92, 46]),
            ("日本語日本語", 110, false, [4, 2], [92, 46]),
            ("漢字。漢字", 45, true, [1, 1, 1, 1, 1], [23, 23, 23, 23, 23]),
            ("漢字。漢字", 45, false, [1, 1, 1, 1, 1], [23, 23, 23, 23, 23]),
            ("漢字。漢字", 90, true, [3, 2], [69, 46]),
            ("漢字。漢字", 90, false, [3, 2], [69, 46]),
            ("漢字。漢字", 110, true, [3, 2], [69, 46]),
            ("漢字。漢字", 110, false, [4, 1], [92, 23]),
            ("（漢字）漢字", 45, true, [1, 1, 1, 1, 1, 1], [23, 23, 23, 23, 23, 23]),
            ("（漢字）漢字", 45, false, [1, 1, 1, 1, 1, 1], [23, 23, 23, 23, 23, 23]),
            ("（漢字）漢字", 90, true, [2, 3, 1], [46, 69, 23]),
            ("（漢字）漢字", 90, false, [2, 3, 1], [46, 69, 23]),
            ("（漢字）漢字", 110, true, [4, 2], [92, 46]),
            ("（漢字）漢字", 110, false, [4, 2], [92, 46]),
            ("漢字 漢字", 45, true, [1, 2, 1, 1], [23, 28.06, 23, 23]),
            ("漢字 漢字", 45, false, [1, 2, 1, 1], [23, 28.06, 23, 23]),
            ("漢字 漢字", 90, true, [3, 2], [51.06, 46]),
            ("漢字 漢字", 90, false, [4, 1], [74.06, 23]),
            ("漢字 漢字", 110, true, [5], [97.06]),
            ("漢字 漢字", 110, false, [5], [97.06]),
            ("A漢字B", 45, true, [2, 2], [36.202, 37.536]),
            ("A漢字B", 45, false, [2, 2], [36.202, 37.536]),
            ("A漢字B", 90, true, [4], [73.738]),
            ("A漢字B", 90, false, [4], [73.738]),
            ("A漢字B", 110, true, [4], [73.738]),
            ("A漢字B", 110, false, [4], [73.738]),
            (String(repeating: "漢字", count: 256), 10000, true, [434, 78], [9982, 1794]),
            (String(repeating: "漢字", count: 256), 10000, false, [434, 78], [9982, 1794]),
            (String(repeating: "漢字", count: 256) + "字", 10000, true, [434, 79], [9982, 1817]),
            (String(repeating: "漢字", count: 256) + "字", 10000, false, [434, 79], [9982, 1817]),
            ("한국어한글", 70, true, [3, 2], [63.48, 42.32]),
            ("한국어한글", 70, false, [3, 2], [63.48, 42.32]),
            ("가나", 45, true, [4], [42.32]),
            ("가나", 45, false, [4], [42.32]),
            ("漢字。漢字", 46, true, [1, 2, 2], [23, 46, 46]),
            ("漢字。漢字", 46, false, [1, 2, 2], [23, 46, 46]),
            ("（漢字）漢字", 69, true, [2, 3, 1], [46, 69, 23]),
            ("（漢字）漢字", 69, false, [2, 3, 1], [46, 69, 23]),
            ("A漢字B", 37, true, [2, 1, 1], [36.202, 23, 14.536]),
            ("A漢字B", 37, false, [2, 1, 1], [36.202, 23, 14.536]),
        ]
        for (string, width, avoids, lengths, widths) in cases {
            for scale: CGFloat in [1, 2] {
                let label = "\(string) width=\(width) avoids=\(avoids) scale=\(scale)"
                let source = try resolve(string, scale: scale, avoidsOrphans: avoids, cjk: true)
                let layout = source.makeGlyphLayout(maxWidth: Int(width * scale), maximumHeight: 400 * scale)
                var start = 0
                let ranges = lengths.map { length in
                    defer { start += length }
                    return start..<(start + length)
                }
                XCTAssertEqual(layout.lines.map {
                    $0.glyphs.first!.sourceRange!.lowerBound..<$0.glyphs.last!.sourceRange!.upperBound
                }, ranges, label)
                XCTAssertEqual(layout.lines.count, widths.count, label)
                for (actual, expected) in zip(layout.lines, widths) {
                    XCTAssertEqual((actual.fragmentWidth ?? actual.width) / scale, expected, accuracy: 0.000_001, label)
                }
                let expectedSize = CGSize(width: ceil(widths.max()! * 2) / 2, height: CGFloat(lengths.count * 34))
                let manager = ResolvedStyledText.TextLayoutManager(resolvedText: source)
                let metrics = manager.metrics(in: CGSize(width: width, height: 400), layoutMargins: nil)
                XCTAssertEqual(metrics.size, expectedSize, label)
                XCTAssertEqual(metrics.firstBaseline, 27, label)
                XCTAssertEqual(metrics.lastBaseline, expectedSize.height - 7, label)
                let ordinary = ResolvedStyledText.StringDrawing(resolvedText: source)
                XCTAssertEqual(ordinary.metrics(in: CGSize(width: width, height: 400), layoutMargins: nil).size, expectedSize, label)
            }
        }
    }

    // ASSERTIONS textParagraphLineBreak27Observed textHangulShapingPolicy27Observed textShapingScriptSpans27Observed
    func testHangulWordBoundaryPreservesSpaceAdvancesAndPublishedMetrics() throws {
        for avoids in [true, false] {
            for scale: CGFloat in [1, 2] {
                let source = try resolve("한국어 한글", scale: scale, avoidsOrphans: avoids, cjk: true)
                let layout = source.makeGlyphLayout(maxWidth: Int(90 * scale), maximumHeight: 400 * scale)
                XCTAssertEqual(layout.lines.map {
                    $0.glyphs.first!.sourceRange!.lowerBound..<$0.glyphs.last!.sourceRange!.upperBound
                }, [0..<4, 4..<6])
                let widths: [CGFloat] = [68.54, 42.32]
                let advances: [[CGFloat]] = [[21.16, 21.16, 21.16, 5.06], [21.16, 21.16]]
                for (index, line) in layout.lines.enumerated() {
                    XCTAssertEqual((line.fragmentWidth ?? line.width) / scale, widths[index], accuracy: 0.000_001)
                    XCTAssertEqual(line.glyphs.count, advances[index].count)
                    for (glyph, advance) in zip(line.glyphs, advances[index]) {
                        XCTAssertEqual(glyph.advance.width / scale, advance, accuracy: 0.000_001)
                    }
                }
                let size = CGSize(width: 90, height: 400)
                let manager = ResolvedStyledText.TextLayoutManager(resolvedText: source)
                let metrics = manager.metrics(in: size, layoutMargins: nil)
                XCTAssertEqual(metrics.size, CGSize(width: 69, height: 68))
                XCTAssertEqual(metrics.firstBaseline, 27)
                XCTAssertEqual(metrics.lastBaseline, 61)
                let ordinary = ResolvedStyledText.StringDrawing(resolvedText: source)
                let ordinaryMetrics = ordinary.metrics(in: size, layoutMargins: nil)
                XCTAssertEqual(ordinaryMetrics.size, metrics.size)
                XCTAssertEqual(ordinaryMetrics.firstBaseline, 27)
                XCTAssertEqual(ordinaryMetrics.lastBaseline, 61)
            }
        }
    }

    // ASSERTIONS textCombiningRunSlices27Observed
    func testCombiningGlyphsKeepSeparateSlicesAndCharacterIndices() throws {
        let cases: [(String, [Int], [CGFloat])] = [
            ("가\u{301} 나", [0, 1, 2, 3], [21.16, 0, 5.06, 21.16]),
            ("가\u{301} 나", [0, 2, 3, 4], [21.16, 0, 5.06, 21.16]),
            ("가\u{301}\u{300} 나", [0, 1, 2, 3, 4], [21.16, 0, 0, 5.06, 21.16]),
            ("q\u{301}x", [0, 1, 2], [13.685, 0, 9.982]),
            ("e\u{301}x", [0, 2], [12.121, 9.982]),
        ]
        for (text, indices, widths) in cases {
            for scale: CGFloat in [1, 2] {
                let source = try resolve(text, scale: scale, cjk: true)
                let layout = source.makeLayout(in: CGSize(width: 200, height: 400), layoutDirection: .leftToRight)
                let line = try XCTUnwrap(layout.first)
                XCTAssertEqual(line.count, 1, text)
                let run = try XCTUnwrap(line.first)
                XCTAssertEqual(run.count, widths.count, text)
                let first = try XCTUnwrap(run.characterIndices.first)
                XCTAssertEqual(run.characterIndices.map { first.distance(to: $0) }, indices, text)
                for (index, slice) in run.enumerated() {
                    let width = widths[index]
                    XCTAssertEqual(slice.typographicBounds.width, width, accuracy: 0.000_001, text)
                    XCTAssertEqual(slice.characterIndices.map { first.distance(to: $0) }, [indices[index]], text)
                }
                XCTAssertTrue(run[run.endIndex..<run.endIndex].isEmpty)
                XCTAssertEqual(run[1..<run.endIndex].characterIndices.map { first.distance(to: $0) },
                               Array(indices.dropFirst()), text)
            }
        }
    }

    // ASSERTIONS textCombiningRunSlices27Observed
    func testSameFontScriptRunsRemainSeparateInPublicLayout() throws {
        let expectedIndices = [[0], [0, 1, 2, 3]]
        let expectedWidths: [[CGFloat]] = [[13.202], [21.16, 0, 5.06, 21.16]]
        for scale: CGFloat in [1, 2] {
            let source = try resolve("A가\u{301} 나", scale: scale, cjk: true)
            let layout = source.makeLayout(in: CGSize(width: 200, height: 400),
                                           layoutDirection: .leftToRight)
            let line = try XCTUnwrap(layout.first)
            XCTAssertEqual(line.count, 2)
            guard line.count == expectedIndices.count else { continue }
            for (runIndex, run) in line.enumerated() {
                let first = try XCTUnwrap(run.characterIndices.first)
                XCTAssertEqual(run.characterIndices.map { first.distance(to: $0) },
                               expectedIndices[runIndex])
                XCTAssertEqual(run.count, expectedWidths[runIndex].count)
                for (sliceIndex, slice) in run.enumerated() {
                    XCTAssertEqual(slice.characterIndices.map { first.distance(to: $0) },
                                   [expectedIndices[runIndex][sliceIndex]])
                    XCTAssertEqual(slice.typographicBounds.width,
                                   expectedWidths[runIndex][sliceIndex], accuracy: 0.000_001)
                }
            }
        }
    }

    // ASSERTIONS textParagraphUnicodeOrphan27Observed textParagraphWordBoundary27Observed
    func testOrphanEligibilityUsesAnchoredCharacterSearchAndUTF16Length() throws {
        let words = [String(repeating: "𐐀", count: 5), String(repeating: "𐐀", count: 6),
                     "z" + String(repeating: "𐐀", count: 4), "z" + String(repeating: "𐐀", count: 5)]
        for (index, word) in words.enumerated() {
            for avoids in [true, false] {
                for scale: CGFloat in [1, 2] {
                    let prefix = try resolve("A A A A ", scale: scale, avoidsOrphans: avoids)
                    let remainder = try resolve(word, size: 5, scale: scale, avoidsOrphans: avoids)
                    // Request replacement advances for the bundled-font fixture;
                    // the guard compares source ranges, not fallback-font metrics.
                    let source = ResolvedTextSource(runs: prefix.runs + remainder.runs,
                        scaleFactor: scale, displayScale: 2, drawMissingGlyphs: true)
                    let layout = source.makeGlyphLayout(maxWidth: Int(90 * scale), maximumHeight: 400 * scale)
                    let firstCount = index == 2 && avoids ? 6 : 8
                    XCTAssertEqual(layout.lines.map {
                        $0.glyphs.first!.sourceRange!.lowerBound..<$0.glyphs.last!.sourceRange!.upperBound
                    }, [0..<firstCount, firstCount..<(8 + word.unicodeScalars.count)],
                        "\(word) avoids=\(avoids) scale=\(scale)")
                }
            }
        }
    }

    // ASSERTIONS textParagraphUnicodeOrphan27Observed
    func testOrphanArbitrationUsesWordBoundariesForApostrophesAndCombiningMarks() throws {
        let cases: [(String, CGFloat, CGFloat, Int)] = [
            ("don't", 69.8759765625, 49.1669921875, 5),
            ("don’t", 70.7294921875, 50.0205078125, 5),
            ("BB-BB", 82.8359375, 63.6767578125, 5),
            ("e\u{0301}lan", 63.71044921875, 43.00146484375, 5),
            ("café", 65.181640625, 44.47265625, 4),
        ]
        for (word, movedWidth, wordWidth, length) in cases {
            for width: CGFloat in [90, 110] {
                for avoids in [true, false] {
                    let moved = avoids && word != "BB-BB"
                    let expectedWidths: [CGFloat] = moved
                        ? [62.126953125, movedWidth] : [82.8359375, wordWidth]
                    let size = CGSize(width: ceil(expectedWidths.max()! * 2) / 2, height: 54)
                    let ranges = moved ? [0..<6, 6..<(8 + length)] : [0..<8, 8..<(8 + length)]
                    for scale: CGFloat in [1, 2] {
                        let label = "\(word) width=\(width) avoids=\(avoids) scale=\(scale)"
                        let source = try resolve("A A A A " + word, scale: scale, avoidsOrphans: avoids)
                        let layout = source.makeGlyphLayout(maxWidth: Int(width * scale), maximumHeight: 400 * scale)
                        XCTAssertEqual(layout.lines.map { ($0.fragmentWidth ?? $0.width) / scale }, expectedWidths, label)
                        XCTAssertEqual(layout.lines.map {
                            $0.glyphs.first!.sourceRange!.lowerBound..<$0.glyphs.last!.sourceRange!.upperBound
                        }, ranges, label)
                        let manager = ResolvedStyledText.TextLayoutManager(resolvedText: source)
                        let metrics = manager.metrics(in: CGSize(width: width, height: 400), layoutMargins: nil)
                        XCTAssertEqual(metrics.size, size, label)
                        XCTAssertEqual(metrics.firstBaseline, 21, label)
                        XCTAssertEqual(metrics.lastBaseline, 48, label)
                        let ordinary = ResolvedStyledText.StringDrawing(resolvedText: source)
                        XCTAssertEqual(ordinary.metrics(in: CGSize(width: width, height: 400), layoutMargins: nil).size, size, label)
                    }
                }
            }
        }
    }

    // ASSERTIONS textTabStops27Observed textTabReflow27Observed
    func testTabsUseParagraphStopsAndRecomputeTheirAdvanceAfterWrapping() throws {
        let a: CGFloat = 15.00390625
        let tabAfterA: CGFloat = 12.99609375
        let cases: [(String, CGFloat, Int?, CGSize, [CGFloat], [[CGFloat]])] = [
            ("A\tA", 8, nil, .init(width: 8, height: 81), [8, 8, 8], [[a], [28], [a]]),
            ("A\tA", 8, 2, .init(width: 8, height: 54), [8, 8], [[a], [28, a]]),
            ("A\tA", 30, nil, .init(width: 28, height: 54), [28, a], [[a, tabAfterA], [a]]),
            ("A\tA", 30, 2, .init(width: 28, height: 54), [28, a], [[a, tabAfterA], [a]]),
            ("A\tA", 70, nil, .init(width: 43.5, height: 27), [28 + a], [[a, tabAfterA, a]]),
            ("A\tA", 70, 2, .init(width: 43.5, height: 27), [28 + a], [[a, tabAfterA, a]]),
            ("\tA", 8, nil, .init(width: 8, height: 54), [8, 8], [[28], [a]]),
            ("\tA", 8, 2, .init(width: 8, height: 54), [8, 8], [[28], [a]]),
            ("\tA", 30, nil, .init(width: 28, height: 54), [28, a], [[28], [a]]),
            ("\tA", 30, 2, .init(width: 28, height: 54), [28, a], [[28], [a]]),
            ("\tA", 70, nil, .init(width: 43.5, height: 27), [28 + a], [[28, a]]),
            ("\tA", 70, 2, .init(width: 43.5, height: 27), [28 + a], [[28, a]]),
            ("A\t", 8, nil, .init(width: 8, height: 54), [8, 8], [[a], [28]]),
            ("A\t", 8, 2, .init(width: 8, height: 54), [8, 8], [[a], [28]]),
            ("A\t", 30, nil, .init(width: 28, height: 27), [28], [[a, tabAfterA]]),
            ("A\t", 30, 2, .init(width: 28, height: 27), [28], [[a, tabAfterA]]),
            ("A\t", 70, nil, .init(width: 28, height: 27), [28], [[a, tabAfterA]]),
            ("A\t", 70, 2, .init(width: 28, height: 27), [28], [[a, tabAfterA]]),
            ("A\tA\tA", 8, nil, .init(width: 8, height: 108), [8, 8, 8, 8], [[a], [28], [a], [28, a]]),
            ("A\tA\tA", 8, 2, .init(width: 8, height: 54), [8, 8], [[a], [28, a, tabAfterA, a]]),
            ("A\tA\tA", 30, nil, .init(width: 28, height: 81), [28, 28, a], [[a, tabAfterA], [a, tabAfterA], [a]]),
            ("A\tA\tA", 30, 2, .init(width: 28, height: 54), [28, 15.3857421875], [[a, tabAfterA], [15.3857421875]]),
            ("A\tA\tA", 70, nil, .init(width: 43.5, height: 54), [28 + a, 28 + a], [[a, tabAfterA, a], [28, a]]),
            ("A\tA\tA", 70, 2, .init(width: 43.5, height: 54), [28 + a, 28 + a], [[a, tabAfterA, a], [28, a]]),
        ]
        for (string, width, limit, size, widths, advances) in cases {
            for scale: CGFloat in [1, 2] {
                let label = "\(string.debugDescription) width=\(width) limit=\(String(describing: limit)) scale=\(scale)"
                let source = try resolve(string, scale: scale)
                let layout = source.makeGlyphLayout(maxWidth: Int(width * scale),
                    maximumHeight: 120 * scale, lineLimit: limit)
                let manager = ResolvedStyledText.TextLayoutManager(resolvedText: source)
                manager.layoutProperties.lineLimit = limit
                let metrics = manager.computeMetrics(scale: 1,
                    requestedSize: .init(CGSize(width: width, height: 120), majorAxis: .vertical),
                    minorAxisIsFlexible: false).base
                XCTAssertEqual(metrics.size, size, label)
                XCTAssertEqual(metrics.firstBaseline, 21, label)
                XCTAssertEqual(metrics.lastBaseline, size.height - 6, label)
                XCTAssertEqual(layout.lines.map { ($0.fragmentWidth ?? $0.width) / scale }, widths, label)
                XCTAssertEqual(layout.lines.map { $0.glyphs.map { $0.advance.width / scale } }, advances, label)
                for glyph in layout.lines.flatMap(\.glyphs) where glyph.scalar == "\t" {
                    if case .missing = glyph.content {} else {
                        XCTFail("A tab must not draw a replacement glyph: \(label)")
                    }
                }
            }
        }
    }

    // ASSERTIONS textTabStops27Observed textTabReflow27Observed textParagraphOrphanArbitration27Observed
    func testTabExhaustionAndOrphanRetriesKeepTheirSeparateBoundaries() throws {
        let a: CGFloat = 15.00390625
        let cases: [(String, CGFloat, Bool, CGSize, [CGFloat], [[CGFloat]])] = [
            ("A\tA\tA", 70, false, .init(width: 56, height: 54), [56, a], [[a, 28 - a, a, 28 - a], [a]]),
            ("A\tA", 30, false, .init(width: 28, height: 54), [28, a], [[a, 28 - a], [a]]),
            (String(repeating: "A", count: 22) + "\tA", 400, true, .init(width: 351.5, height: 27), [336 + a],
                [Array(repeating: a, count: 22) + [336 - 22 * a, a]]),
            (String(repeating: "A", count: 23) + "\tA", 400, true, .init(width: 345.5, height: 54), [23 * a, 28 + a],
                [Array(repeating: a, count: 23), [28, a]]),
            (String(repeating: "\t", count: 13) + "A", 800, true, .init(width: 336, height: 54), [336, 28 + a],
                [Array(repeating: 28, count: 12), [28, a]]),
            ("AA\tA", 28, true, .init(width: 28, height: 81), [a, 28, a], [[a], [a, 28 - a], [a]]),
            ("AA\tA", 30, true, .init(width: 28, height: 81), [a, 28, a], [[a], [a, 28 - a], [a]]),
            ("AA\tA", 70, true, .init(width: 43.5, height: 54), [2 * a, 28 + a], [[a, a], [28, a]]),
            (" \tA", 70, true, .init(width: 43.5, height: 27), [28 + a], [[5.705078125, 22.294921875, a]]),
            ("A\t\tA", 70, true, .init(width: 43.5, height: 54), [28, 28 + a], [[a, 28 - a], [28, a]]),
        ]
        for (string, width, avoids, size, widths, advances) in cases {
            for scale: CGFloat in [1, 2] {
                let label = "\(string.debugDescription) width=\(width) avoids=\(avoids) scale=\(scale)"
                let source = try resolve(string, scale: scale, avoidsOrphans: avoids)
                let layout = source.makeGlyphLayout(maxWidth: Int(width * scale), maximumHeight: 400 * scale)
                let manager = ResolvedStyledText.TextLayoutManager(resolvedText: source)
                let metrics = manager.computeMetrics(scale: 1,
                    requestedSize: .init(CGSize(width: width, height: 400), majorAxis: .vertical),
                    minorAxisIsFlexible: false).base
                XCTAssertEqual(metrics.size, size, label)
                XCTAssertEqual(metrics.firstBaseline, 21, label)
                XCTAssertEqual(metrics.lastBaseline, size.height - 6, label)
                XCTAssertEqual(layout.lines.map { ($0.fragmentWidth ?? $0.width) / scale }, widths, label)
                XCTAssertEqual(layout.lines.map { $0.glyphs.map { $0.advance.width / scale } }, advances, label)
            }
        }
    }

    // ASSERTIONS textTabFitting27Observed textTabStops27Observed
    func testTabStopsRemainInParagraphPointsThroughOwnerSpecificFontFitting() throws {
        let cases: [(String, CGFloat, CGFloat, Int?, CGFloat, CGSize, CGSize, CGFloat, CGFloat, CGFloat)] = [
            ("A\tA",8,120,1,1,.init(width:8,height:27),.init(width:8,height:27),21,21,1),
            ("A\tA",30,120,1,1,.init(width:15.5,height:27),.init(width:15.5,height:27),21,21,1),
            ("A\tA",70,120,1,1,.init(width:43.5,height:27),.init(width:43.5,height:27),21,21,1),
            ("A\tA",30,120,1,0.5,.init(width:15.5,height:14),.init(width:15.5,height:14),11,11,0.5),
            ("A\tA",70,120,1,0.5,.init(width:43.5,height:27),.init(width:43.5,height:27),21,21,1),
            ("A\tA",30,120,2,0.5,.init(width:28,height:54),.init(width:28,height:54),21,48,1),
            ("A\tA",8,120,2,0.5,.init(width:8,height:54),.init(width:8,height:28),21,48,1),
            ("AA\tA",30,120,nil,0.5,.init(width:28,height:81),.init(width:28,height:81),21,75,1),
            ("AA\tA",30,120,1,0.5,.init(width:23,height:14),.init(width:23,height:14),11,11,0.5),
            ("AA\tA",30,120,2,0.5,.init(width:28,height:42),.init(width:28,height:42),17,38,0.796875),
            (String(repeating:"\t",count:13)+"A",800,120,1,1,.init(width:351.5,height:27),.init(width:351.5,height:27),21,21,1),
            (String(repeating:"A",count:23)+"\tA",400,120,1,1,.init(width:360.5,height:27),.init(width:360.5,height:27),21,21,1),
            (String(repeating:"\t",count:13)+"A",800,120,2,0.5,.init(width:336,height:54),.init(width:336,height:54),21,48,1),
            ("A\tA",8,24,nil,0.5,.init(width:8,height:14),.init(width:8,height:14),11,11,0.5),
        ]
        for (string, width, height, limit, minimum, expected, ordinaryExpected, first, last, factor) in cases {
            for scale: CGFloat in [1, 2] {
                let source = try resolve(string, scale: scale)
                let size = CGSize(width: width, height: height)
                let label = "\(string.debugDescription) size=\(size) limit=\(String(describing: limit)) minimum=\(minimum) scale=\(scale)"
                let manager = ResolvedStyledText.TextLayoutManager(resolvedText: source)
                manager.layoutProperties.lineLimit = limit
                manager.layoutProperties.minScaleFactor = minimum
                let metrics = manager.metrics(in: size, layoutMargins: nil)
                XCTAssertEqual(metrics.size, expected, label)
                XCTAssertEqual(metrics.firstBaseline, first, label)
                XCTAssertEqual(metrics.lastBaseline, last, label)
                XCTAssertEqual(metrics.scale, factor, label)
                let ordinary = ResolvedStyledText.StringDrawing(resolvedText: source)
                ordinary.layoutProperties = manager.layoutProperties
                let measured = ordinary.metrics(in: size, layoutMargins: nil)
                XCTAssertEqual(measured.size, ordinaryExpected, "ordinary " + label)
            }
        }
    }

    // ASSERTIONS textParagraphOrphanArbitration27Observed textNarrowWordWrap27Observed
    func testWordWrappingConsumesParagraphStrategyAndRetainsOversizedTrailingSpaces() throws {
        let cases: [(String, CGFloat, Int?, [(CGSize, [CGFloat], [Int])])] = [
            ("A A A A A A A A", 8, 2, [(.init(width: 8, height: 54), [8, 8], [2, 13]), (.init(width: 8, height: 54), [8, 8], [2, 13])]),
            ("A A A A A A A A", 150, 2, [(.init(width: 124.5, height: 54), [124.25390625, 35.712890625], [12, 3]), (.init(width: 145, height: 54), [144.962890625, 15.00390625], [14, 1])]),
            ("A A", 18, nil, [(.init(width: 18, height: 54), [18, 15.00390625], [2, 1]), (.init(width: 18, height: 54), [18, 15.00390625], [2, 1])]),
            ("A A A", 38, nil, [(.init(width: 38, height: 54), [38, 15.00390625], [4, 1]), (.init(width: 38, height: 54), [38, 15.00390625], [4, 1])]),
            ("A A A A A A A A", 100, nil, [(.init(width: 100, height: 54), [100, 56.421875], [10, 5]), (.init(width: 100, height: 54), [100, 56.421875], [10, 5])]),
            ("A A A A WWWWWWWWWW", 95, nil, [(.init(width: 83, height: 108), [82.8359375, 81.623046875, 81.623046875, 40.8115234375], [8, 4, 4, 2]), (.init(width: 83, height: 108), [82.8359375, 81.623046875, 81.623046875, 40.8115234375], [8, 4, 4, 2])]),
            ("A A A A WWWWWWWWWWW", 95, nil, [(.init(width: 83, height: 108), [82.8359375, 81.623046875, 81.623046875, 61.21728515625], [8, 4, 4, 3]), (.init(width: 83, height: 108), [82.8359375, 81.623046875, 81.623046875, 61.21728515625], [8, 4, 4, 3])]),
            ("A A A A word", 90, nil, [(.init(width: 72, height: 54), [62.126953125, 71.66162109375], [6, 6]), (.init(width: 83, height: 54), [82.8359375, 50.95263671875], [8, 4])]),
            ("A A A A word  ", 90, nil, [(.init(width: 83.5, height: 54), [62.126953125, 83.07177734375], [6, 8]), (.init(width: 83, height: 54), [82.8359375, 62.36279296875], [8, 6])]),
            ("A A A A BB-BB", 90, nil, [(.init(width: 83, height: 54), [82.8359375, 63.6767578125], [8, 5]), (.init(width: 83, height: 54), [82.8359375, 63.6767578125], [8, 5])]),
            ("A A A A .", 90, nil, [(.init(width: 89, height: 27), [88.900390625], [9]), (.init(width: 89, height: 27), [88.900390625], [9])]),
            ("A  A", 8, nil, [(.init(width: 8, height: 54), [8, 8], [3, 1]), (.init(width: 8, height: 54), [8, 8], [3, 1])]),
            ("A\u{00a0}A", 8, nil, [(.init(width: 8, height: 54), [8, 8], [2, 1]), (.init(width: 8, height: 54), [8, 8], [2, 1])]),
            ("A\u{2003}A", 8, nil, [(.init(width: 8, height: 54), [8, 8], [2, 1]), (.init(width: 8, height: 54), [8, 8], [2, 1])]),
            ("AA A", 8, nil, [(.init(width: 8, height: 81), [8, 8, 8], [1, 2, 1]), (.init(width: 8, height: 81), [8, 8, 8], [1, 2, 1])]),
            ("A A A\nA A A", 40, nil, [(.init(width: 40, height: 108), [40, 15.00390625, 40, 15.00390625], [4, 2, 4, 1]), (.init(width: 40, height: 108), [40, 15.00390625, 40, 15.00390625], [4, 2, 4, 1])]),
        ]
        for (string, width, limit, expectations) in cases {
            for (index, avoids) in [true, false].enumerated() {
                for scale: CGFloat in [1, 2] {
                    let label = "\(string.debugDescription) width=\(width) avoids=\(avoids) scale=\(scale)"
                    let source = try resolve(string, scale: scale, avoidsOrphans: avoids)
                    let layout = source.makeGlyphLayout(maxWidth: Int(width * scale),
                        maximumHeight: 400 * scale, lineLimit: limit)
                    let expected = expectations[index]
                    let manager = ResolvedStyledText.TextLayoutManager(resolvedText: source)
                    manager.layoutProperties.lineLimit = limit
                    let metrics = manager.computeMetrics(scale: 1,
                        requestedSize: .init(CGSize(width: width, height: 400), majorAxis: .vertical),
                        minorAxisIsFlexible: false).base
                    XCTAssertEqual(metrics.size, expected.0, label)
                    XCTAssertEqual(metrics.firstBaseline, 21, label)
                    XCTAssertEqual(metrics.lastBaseline, 21 + CGFloat(expected.1.count - 1) * 27, label)
                    XCTAssertEqual(layout.lines.map { ($0.fragmentWidth ?? $0.width) / scale }, expected.1, label)
                    XCTAssertEqual(layout.lines.map { line in
                        let start = line.glyphs.first?.sourceRange?.lowerBound ?? 0
                        let end = line.trailingBoundary?.sourceRange?.upperBound ?? line.glyphs.last?.sourceRange?.upperBound ?? start
                        return end - start
                    }, expected.2, label)
                }
            }
        }
    }

    func testTextMeasurementFitsTheStackRemainingAfterHostLayout() throws {
        // Keep a bounded text budget inside the larger window-update stack.
        let sources = Mutex(StackMeasurementSources(settings: try resolve("Settings"),
                             paragraph: try resolve("Alpha beta gamma delta\nNext line")))
        let completed = DispatchSemaphore(value: 0)
        let results = Mutex((spacingCount: 0, layouts: [ResolvedTextSource.GlyphLayout](), stackSize: 0))
        let thread = Thread {
            sources.withLock { sources in
                let owner = ResolvedStyledText.StringDrawing(resolvedText: sources.settings)
                let spacing = owner.spacing()
                var layouts: [ResolvedTextSource.GlyphLayout] = []
                for mode: Text.TruncationMode in [.head, .middle, .tail] {
                    layouts.append(sources.paragraph.makeGlyphLayout(
                        maxWidth: 80, maximumHeight: 27, lineLimit: 1, truncationMode: mode))
                }
                results.withLock {
                    $0.spacingCount = spacing.minima.count
                    $0.layouts = layouts
#if canImport(Darwin)
                    $0.stackSize = pthread_get_stacksize_np(pthread_self())
#endif
                }
            }
            completed.signal()
        }
#if canImport(Darwin)
        thread.stackSize = 192 * 1024
#endif
        thread.start()
        guard completed.wait(timeout: .now() + 10) == .success else {
            return XCTFail("Text measurement did not finish on the bounded worker stack")
        }
        sources.withLock { sources in
            results.withLock { results in
                XCTAssertEqual(results.spacingCount, 6)
                XCTAssertEqual(results.layouts.count, 3)
#if canImport(Darwin)
                XCTAssertGreaterThanOrEqual(results.stackSize, 192 * 1024)
                XCTAssertLessThan(results.stackSize, 224 * 1024)
#endif
                for (mode, actual) in zip([Text.TruncationMode.head, .middle, .tail], results.layouts) {
                    let expected = sources.paragraph.makeGlyphLayout(
                        maxWidth: 80, maximumHeight: 27, lineLimit: 1, truncationMode: mode)
                    XCTAssertEqual(actual.lines.map(\.glyphs).map { $0.map(\.scalar) },
                                   expected.lines.map(\.glyphs).map { $0.map(\.scalar) })
                    XCTAssertEqual(actual.lines.map(\.originY), expected.lines.map(\.originY))
                    XCTAssertEqual(actual.lines.map(\.baseline), expected.lines.map(\.baseline))
                    XCTAssertEqual(actual.lines.map(\.width), expected.lines.map(\.width))
                    XCTAssertEqual(actual.lineCount, expected.lineCount)
                    XCTAssertEqual(actual.truncatedRanges, expected.truncatedRanges)
                    XCTAssertEqual(actual.hasUnlaidText, expected.hasUnlaidText)
                }
            }
        }
    }

    // ASSERTIONS textParagraphAdmissionBudgetObserved
    func testCandidateBudgetIsDistinctFromPublishedLineCount() throws {
        let controls: [(String, Int?, Int, CGFloat)] = [
            ("A\n\n", nil, 3, 55), ("A\n\n", 1, 1, 27), ("A\n\n", 2, 3, 55),
            ("\r\n\r\n", nil, 2, 54), ("\r\n\r\n", 1, 0, 0), ("\r\n\r\n", 2, 1, 27)
        ]
        for scale: CGFloat in [1, 2] {
            for (string, limit, count, height) in controls {
                let source = try resolve(string, scale: scale)
                var properties = TextLayoutProperties()
                properties.lineLimit = limit
                let size = CGSize(width: 300, height: 56)
                let metrics = source.layoutMetrics(in: size, layoutProperties: properties)
                let layout = source.makeLayout(in: size, layoutDirection: .leftToRight, layoutProperties: properties)
                XCTAssertEqual(metrics.size.height, height)
                XCTAssertEqual(layout.count, count)
                XCTAssertFalse(layout.isTruncated)
                if string.hasPrefix("A"), limit == 1 {
                    XCTAssertEqual(source.makeGlyphs(maxHeight: Int(56 * scale), lineLimit: limit)
                        .flatMap(\.glyphs).map(\.scalar), Array("A…".unicodeScalars))
                }
            }
        }
    }

    // ASSERTIONS textParagraphAdmissionBudgetObserved
    func testUncommittedSeparatorParagraphPublishesNoLine() throws {
        let empty = try resolve("\r\n\r\n")
        let text = try resolve("A\n\n")
        let size = CGSize(width: 300, height: 42)
        XCTAssertEqual(empty.measure(in: size), .zero)
        XCTAssertTrue(empty.makeDrawing(in: size).isEmpty)
        XCTAssertEqual(text.measure(in: size).height, 27)
        XCTAssertEqual(text.makeGlyphs(maxHeight: 42).flatMap(\.glyphs).map(\.scalar), Array("A…".unicodeScalars))
    }

    // ASSERTIONS textFinalExtraFragmentOverlapObserved
    func testFailedFinalExtraPreservesThePendingRectangle() throws {
        for scale: CGFloat in [1, 2] {
            let source = try resolve("A\n", scale: scale)
            for height: CGFloat in [14, 27, 42] {
                let size = CGSize(width: 300, height: height)
                let layout = source.makeLayout(in: size, layoutDirection: .leftToRight)
                XCTAssertEqual(layout.count, 2)
                guard layout.count == 2 else { continue }
                XCTAssertEqual(layout[layout.startIndex].origin, layout[layout.index(after: layout.startIndex)].origin)
                XCTAssertTrue(layout[layout.startIndex].isEmpty)
                XCTAssertEqual(layout[layout.index(after: layout.startIndex)].count, 1)
                XCTAssertEqual(source.measure(in: size).height, 27)
                XCTAssertEqual(source.firstBaseline(in: size), 21)
                XCTAssertEqual(source.lastBaseline(in: size), 21)
                XCTAssertEqual(source.glyphAtoms(in: size).count, 1)
            }
        }
    }

    // ASSERTIONS textParagraphAdmissionBudgetObserved
    func testSpacingAffectsPublicationSeparatelyFromAdmissionAndFinalization() throws {
        let simple = try resolve("\n\n", spacing: 7)
        let source = try resolve("A\n\r\n", spacing: 7)
        let soft = try resolve("A\u{2028}\u{2028}", spacing: 7)
        let size = CGSize(width: 300, height: 54)
        XCTAssertEqual(simple.measure(in: size).height, 61)
        XCTAssertEqual(simple.makeGlyphs(maxHeight: 54).map(\.baseline), [21, 48, 52])
        XCTAssertEqual(source.makeGlyphs(maxHeight: 54).flatMap(\.glyphs).map(\.scalar), Array("A".unicodeScalars))
        XCTAssertEqual(soft.makeGlyphs(maxHeight: 54).flatMap(\.glyphs).map(\.scalar), Array("A…".unicodeScalars))
    }

    // ASSERTIONS textParagraphAdmissionBudgetObserved
    func testCompleteFinalLineUsesItsParagraphOriginGate() throws {
        let source = try resolve("A\n\nB", size: 13, spacing: 7)
        XCTAssertEqual(source.makeGlyphs(maxHeight: 42).map(\.baseline), [12, 27, 56])
        XCTAssertEqual(source.measure(in: CGSize(width: 300, height: 42)).height, 59)
        XCTAssertEqual(source.makeGlyphs(maxHeight: 37).map(\.baseline), [12, 27])
    }

    // ASSERTIONS textParagraphAdmissionBudgetObserved
    func testHeightToleranceUsesTheParagraphLocalRemainder() throws {
        for scale: CGFloat in [1, 2] {
            let source = try resolve("\r\n\r\n", scale: scale)
            for (height, count): (CGFloat, Int) in [(53.998, 0), (53.9995, 2), (80.999, 2), (80.9995, 3)] {
                XCTAssertEqual(source.makeGlyphs(maximumHeight: height * scale).count, count)
            }
        }
    }

    // ASSERTIONS textParagraphAdmissionBudgetObserved
    func testZeroHeightProposalUsesOneCandidate() throws {
        let source = try resolve("A\n")
        for limit in [nil, 1, 2, 3] {
            let lines = source.makeGlyphs(maxHeight: 0, lineLimit: limit)
            XCTAssertEqual(lines.count, 1)
            XCTAssertEqual(lines.flatMap(\.glyphs).map(\.scalar), Array("A…".unicodeScalars))
        }
        let size = CGSize(width: 300, height: 0)
        XCTAssertEqual(source.measure(in: size).height, 27)
        XCTAssertEqual(TextProxy(ResolvedStyledText.TextLayoutManager(resolvedText: source)).sizeThatFits(.init(size)), source.measure(in: size))
    }

    private static func mappedSpaceFontData() throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        var data = try Data(contentsOf: root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"))
        let characterMap: [UInt32: UInt32] = [
            0x20: 4, 0x61: 69, 0x71: 85, 0x78: 92, 0x301: 169,
            0x323: 173, 0xe1: 695, 0x200c: 4, 0x200d: 4,
        ]
        func read(_ offset: Int, _ count: Int) -> Int {
            data[offset..<(offset + count)].reduce(0) { ($0 << 8) | Int($1) }
        }
        func write(_ value: UInt32, _ offset: Int) {
            for index in 0..<4 {
                data[offset + index] = UInt8(truncatingIfNeeded: value >> ((3 - index) * 8))
            }
        }
        let records = stride(from: 12, to: 12 + read(4, 2) * 16, by: 16)
        let tables = Dictionary(uniqueKeysWithValues: records.map { record in
            (String(decoding: data[record..<(record + 4)], as: UTF8.self), record)
        })
        let cmapRecord = try XCTUnwrap(tables["cmap"])
        let cmap = read(cmapRecord + 8, 4)
        let cmapLength = read(cmapRecord + 12, 4)
        XCTAssertGreaterThanOrEqual(cmapLength, 28 + characterMap.count * 12)
        data.replaceSubrange(cmap..<(cmap + cmapLength),
                             with: repeatElement(UInt8(0), count: cmapLength))
        write(1, cmap)
        write(0x0003_000a, cmap + 4)
        write(12, cmap + 8)
        write(0x000c_0000, cmap + 12)
        write(UInt32(16 + characterMap.count * 12), cmap + 16)
        write(UInt32(characterMap.count), cmap + 24)
        for (index, pair) in characterMap.sorted(by: { $0.key < $1.key }).enumerated() {
            let entry = cmap + 28 + index * 12
            write(pair.key, entry)
            write(pair.key, entry + 4)
            write(pair.value, entry + 8)
        }

        let head = read(try XCTUnwrap(tables["head"]) + 8, 4)
        write(0, head + 8)
        func checksum(_ offset: Int, _ count: Int) -> UInt32 {
            var result: UInt32 = 0
            for start in stride(from: 0, to: count, by: 4) {
                var word: UInt32 = 0
                for byte in 0..<4 {
                    word = (word << 8) |
                        (start + byte < count ? UInt32(data[offset + start + byte]) : 0)
                }
                result &+= word
            }
            return result
        }
        for record in records {
            write(checksum(read(record + 8, 4), read(record + 12, 4)), record + 4)
        }
        write(0xb1b0_afba &- checksum(0, data.count), head + 8)
        return data
    }
}

// Access transfers to the worker under a mutex and returns after its completion signal.
private struct StackMeasurementSources: @unchecked Sendable {
    let settings: ResolvedTextSource
    let paragraph: ResolvedTextSource
}

private final class ParagraphAdmissionAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }
    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}
