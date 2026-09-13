import Foundation
import XCTest
import VVD
@testable import VUI

final class TextEmptyFragmentTests: XCTestCase {
    private var previousContext: (any AppContext)?
    private var scene = SceneResources()

    override func setUp() {
        previousContext = appContext
        appContext = EmptyTextAppContext()
        scene = SceneResources()
    }

    override func tearDown() {
        appContext = previousContext
        previousContext = nil
    }

    private func font(_ size: CGFloat) -> VUI.Font {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return .file(root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: size)
    }

    private func resolve(_ text: Text, scale: CGFloat = 1, spacing: CGFloat = 0) throws -> GraphicsContext.ResolvedText {
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        environment.displayScale = 2
        environment._contentScaleFactor = scale
        environment.lineSpacing = spacing
        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        return try XCTUnwrap(text._resolve(context: GraphTextResolutionContext(environment: environment,
            sceneResources: scene), referenceDate: Date(timeIntervalSince1970: 0)))
    }

    // ASSERTIONS textEmptyFragmentDefaultFontObserved
    // ASSERTIONS textEmptyFragmentConsumerBoundariesObserved
    func testEmptyTextMeasuresConfiguredDefaultWithoutPublishingRendererLines() throws {
        for scale: CGFloat in [1, 1.5, 2] {
            for selected in [font(13), font(23), .body.leading(.loose), .title.bold()] {
                let source = try resolve(Text(verbatim: "").font(selected).baselineOffset(8), scale: scale, spacing: 7)
                let input = try XCTUnwrap(source.defaultLineMetrics)
                let fixed = try resolve(Text(verbatim: "A").font(.system(size: 12)), scale: scale)
                let ordinary = try XCTUnwrap(fixed.makeGlyphs().first)
                XCTAssertEqual(input.ascent, ordinary.ascender)
                XCTAssertEqual(input.height, ordinary.height)
                for height: CGFloat in [0, 10, 100, .infinity] {
                    let size = CGSize(width: 300, height: height)
                    let metrics = source.layoutMetrics(in: size)
                    XCTAssertEqual(metrics.size, CGSize(width: 0, height: ceil(input.height / scale * 2) / 2))
                    XCTAssertEqual(metrics.firstBaseline, input.ascent / scale)
                    XCTAssertEqual(metrics.lastBaseline, input.ascent / scale)
                    XCTAssertEqual(TextProxy(ResolvedStyledText(resolvedText: source)).sizeThatFits(.init(width: 300, height: height)), metrics.size)
                    XCTAssertTrue(source.makeLayout(in: size, layoutDirection: .leftToRight).isEmpty)
                    XCTAssertTrue(source.makeDrawing(in: size).isEmpty)
                }
            }
        }
    }

    // ASSERTIONS textEmptyFragmentDefaultFontObserved
    // ASSERTIONS textSeparatorOnlyExtraFragmentAttributesObserved
    func testMissingExtraUsesItsOwnHeightAndUnionBounds() throws {
        for scale: CGFloat in [1, 1.5, 2] {
            for spacing: CGFloat in [0, 7] {
                for (string, expected): (String, [CGFloat]) in [
                    ("\n", [21, 25]), ("\n\n", [21, 48, 52]), ("A\n\n", [21, 48, 52])
                ] {
                    let source = try resolve(Text(verbatim: string).font(font(23)), scale: scale, spacing: spacing)
                    let lines = source.makeGlyphs()
                    XCTAssertEqual(lines.count, expected.count)
                    XCTAssertEqual(lines.map { $0.baseline / scale }, expected)
                    let last = try XCTUnwrap(lines.last)
                    XCTAssertTrue(last.glyphs.isEmpty)
                    XCTAssertEqual(last.ascender / scale, 11)
                    XCTAssertEqual(last.height / scale, 14)
                    XCTAssertEqual(last.originY - lines[lines.count - 2].originY, last.height)
                    let measured = source.measure()
                    let union = try XCTUnwrap(lines.map(\.maxY).max()) / scale
                    XCTAssertEqual(measured.height, ceil(union * 2) / 2)
                    XCTAssertEqual(source.measure(in: measured), measured)
                    let layout = source.makeLayout(in: measured, layoutDirection: .leftToRight)
                    XCTAssertEqual(layout.count, lines.count)
                    XCTAssertEqual(layout.map(\.origin.y), expected)
                    XCTAssertTrue(try XCTUnwrap(layout.last).isEmpty)
                }
            }
        }
        let large = try resolve(Text(verbatim: "\n").font(font(50)))
        let lines = large.makeGlyphs()
        XCTAssertGreaterThan(lines[0].maxY, lines[1].maxY)
        XCTAssertEqual(large.measure().height, lines[0].maxY)
    }

    // ASSERTIONS textEmptyFragmentMixedAttributesObserved
    func testExtraAttributesComeFromSeparatorAndIgnoreEmptyRuns() throws {
        let first = Text(verbatim: "A").font(font(13))
        let separator = Text(verbatim: "\n").font(font(23))
        for text in [first + separator, first + separator + Text(verbatim: "").font(font(50))] {
            let source = try resolve(text)
            XCTAssertNil(source.defaultLineMetrics)
            let lines = source.makeGlyphs()
            XCTAssertEqual(lines.map(\.ascender), [12, 21])
            XCTAssertEqual(lines.map(\.height), [15, 27])
            XCTAssertEqual(lines.map(\.baseline), [12, 36])
            XCTAssertEqual(source.measure().height, 42)
        }
        for offset: CGFloat in [-3, 3] {
            let source = try resolve(Text(verbatim: "\n").font(font(23)).baselineOffset(offset))
            let last = try XCTUnwrap(source.makeGlyphs().last)
            XCTAssertEqual(last.ascender, 11)
            XCTAssertEqual(last.height, 14)
        }
    }

    // ASSERTIONS textEmptyFragmentSeparatorRoutingObserved
    // ASSERTIONS textEmptyFragmentConsumerBoundariesObserved
    func testCRLFPreservesOneCompleteBoundaryAcrossAttributeRuns() throws {
        for scale: CGFloat in [1, 2] {
            let mixed = Text(verbatim: "\r").font(font(13)) + Text(verbatim: "\n").font(font(23))
            let source = try resolve(mixed, scale: scale)
            XCTAssertNil(source.defaultLineMetrics)
            let lines = source.makeGlyphs()
            XCTAssertEqual(lines.count, 2)
            XCTAssertEqual(lines[0].trailingBoundary?.sourceRange, 0..<2)
            XCTAssertEqual(lines[0].trailingBoundary?.characterIndex, 0)
            XCTAssertEqual(lines.map { $0.ascender / scale }, [12, 21])
            XCTAssertEqual(lines.map { $0.height / scale }, [15, 27])
            let repeated = try resolve(Text(verbatim: "\r\n\r\n").font(font(23)), scale: scale, spacing: 7)
            let repeatedLines = repeated.makeGlyphs()
            XCTAssertEqual(repeatedLines.map { $0.baseline / scale }, [21, 55, 89])
            XCTAssertEqual(repeatedLines.map { $0.height / scale }, [27, 27, 27])
            XCTAssertEqual(repeatedLines[0].trailingBoundary?.sourceRange, 0..<2)
            XCTAssertEqual(repeatedLines[1].trailingBoundary?.sourceRange, 2..<4)
        }
    }

    // ASSERTIONS textEmptyFragmentSeparatorRoutingObserved
    func testOneCharacterParagraphKeepsSpacingAboveItsBaseline() throws {
        for string in ["\nA", "\nAB"] {
            let source = try resolve(Text(verbatim: string).font(font(13)), spacing: 7)
            let lines = source.makeGlyphs()
            XCTAssertEqual(lines.map(\.baseline), [12, 34])
            XCTAssertEqual(lines.map(\.height), [15, 15])
        }
    }

    // ASSERTIONS textEmptyFragmentConsumerBoundariesObserved
    func testParagraphAndForcedBreakPairsChooseDifferentExtraAttributes() throws {
        let separators = ["\n", "\r", "\u{c}", "\u{85}", "\u{2028}", "\u{2029}", "\u{b}"]
        let paragraphBreaks: Set<String> = ["\n", "\r", "\u{2029}"]
        for first in separators {
            for second in separators {
                for prefix in ["", "A"] {
                    let string = prefix + first + second
                    let source = try resolve(Text(verbatim: string).font(font(23)))
                    let lines = source.makeGlyphs()
                    let verticalTabs = [first, second].filter { $0 == "\u{b}" }.count
                    let crlf = first == "\r" && second == "\n"
                    XCTAssertEqual(lines.count, crlf ? 2 : 3 - verticalTabs, string.debugDescription)
                    let missing = verticalTabs == 0 && !crlf && paragraphBreaks.contains(first)
                    XCTAssertEqual(source.defaultLineMetrics != nil, missing, string.debugDescription)
                    XCTAssertEqual(lines.last?.ascender, missing ? 11 : 21, string.debugDescription)
                    if verticalTabs > 0 {
                        let tabs = lines.flatMap(\.glyphs).filter { $0.scalar.value == 0xb }
                        XCTAssertEqual(tabs.count, verticalTabs)
                        XCTAssertTrue(tabs.allSatisfy { $0.advance.width == 0 })
                    }
                }
            }
        }
    }

    // ASSERTIONS textEmptyFragmentConsumerBoundariesObserved
    func testSimpleExtraIsPublishedWithItsAdmittedParagraph() throws {
        let source = try resolve(Text(verbatim: "\n").font(font(23)))
        for height: CGFloat in [0, 14, 27, 28, 56] {
            for limit in [1, 2] {
                let lines = source.makeGlyphs(maximumHeight: height, lineLimit: limit)
                XCTAssertEqual(lines.count, 2)
                XCTAssertEqual(lines.map(\.baseline), [21, 25])
            }
        }
        let two = try resolve(Text(verbatim: "\n\n").font(font(23)))
        XCTAssertEqual(two.makeGlyphs(maximumHeight: 56, lineLimit: 1).count, 1)
        XCTAssertEqual(two.makeGlyphs(maximumHeight: 56, lineLimit: 2).count, 3)
    }

    func testResourcePurgeDoesNotResurrectAnEmptyMeasurement() throws {
        let source = try resolve(Text(verbatim: ""))
        let measured = source.measure()
        let storage = try XCTUnwrap(Mirror(reflecting: source).children.first { $0.label == "storage" }?.value as? AppLifetimeResource)
        storage.purgeResources(reason: .lowMemory)
        XCTAssertEqual(source.measure(), measured)
        storage.purgeResources(reason: .appTermination)
        XCTAssertEqual(source.measure(), .zero)
        XCTAssertEqual(source.firstBaseline(in: .init(width: 300, height: 100)), 0)
        XCTAssertTrue(source.makeGlyphs().isEmpty)
    }
}

private final class EmptyTextAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }
    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}
