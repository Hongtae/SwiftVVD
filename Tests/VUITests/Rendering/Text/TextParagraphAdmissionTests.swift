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

    // ASSERTIONS textParagraphLineBreak27Observed
    func testHangulWordBoundaryPreservesTheTrailingSpaceRange() throws {
        for avoids in [true, false] {
            for scale: CGFloat in [1, 2] {
                let source = try resolve("한국어 한글", scale: scale, avoidsOrphans: avoids, cjk: true)
                let layout = source.makeGlyphLayout(maxWidth: Int(90 * scale), maximumHeight: 400 * scale)
                XCTAssertEqual(layout.lines.map {
                    $0.glyphs.first!.sourceRange!.lowerBound..<$0.glyphs.last!.sourceRange!.upperBound
                }, [0..<4, 4..<6])
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
