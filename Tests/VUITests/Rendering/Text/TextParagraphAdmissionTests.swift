import Foundation
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
                         spacing: CGFloat = 0) throws -> GraphicsContext.ResolvedText {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let font = VUI.Font.file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: size)
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        environment.displayScale = 2
        environment._contentScaleFactor = scale
        environment.lineSpacing = spacing
        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        return try XCTUnwrap(Text(verbatim: string).font(font)._resolve(context:
            GraphTextResolutionContext(environment: environment, sceneResources: scene),
            referenceDate: Date(timeIntervalSince1970: 0)))
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
        XCTAssertEqual(TextProxy(ResolvedStyledText(resolvedText: source)).sizeThatFits(.init(size)), source.measure(in: size))
    }
}

private final class ParagraphAdmissionAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }
    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}
