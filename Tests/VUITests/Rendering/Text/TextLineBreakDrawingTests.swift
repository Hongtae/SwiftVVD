import Foundation
import XCTest
import VVD
@testable import VUI

final class TextLineBreakDrawingTests: XCTestCase {
    // ASSERTIONS textCombiningGeometry27Observed textCombiningDrawing27Observed
    func testMountedCombiningMarksPreserveSlicesClippingAndRecordedPixels() throws {
        try verifyCombiningDrawing(["q\u{301}x", "q\u{301}\u{300}", "q\u{300}\u{301}",
                                    "가\u{301}\u{300} 나", "a\u{20dd}", "f\u{301}fi"], font: testFont())
    }

    // ASSERTIONS textCanonicalMarks27Observed
    func testMountedCanonicalMarksPreserveSlicesClippingAndRecordedPixels() throws {
        try verifyCombiningDrawing(["x\u{301}\u{323}", "e\u{301}\u{323}", "\u{e9}\u{323}",
                                    "q\u{323}\u{301}", "e\u{301}\u{323}\u{300}", "x e\u{301}\u{323} z"],
                                   font: testFont(cjk: false))
    }

    // ASSERTIONS textDefaultIgnorableEncoding27Observed
    func testMountedIgnorableGlyphsPreserveSlicesClippingAndRecordedPixels() throws {
        try verifyCombiningDrawing(["a\u{34f}\u{301}", "q\u{34f}\u{301}", "f\u{34f}i",
                                    "\u{34f}a", "\u{34f}", "\u{34f}\u{34f}a", "a\u{200b}\u{301}",
                                    "q\u{fe0e}\u{301}", "a\u{e0100}\u{301}", "\u{feff}a"],
                                   font: testFont(cjk: false), emptyCases: [4])
    }

    private func verifyCombiningDrawing(_ cases: [String], font: VUI.Font,
                                        emptyCases: Set<Int> = []) throws {
        try verifyDrawing(cases.map { Text(verbatim: $0).font(font) }, emptyCases: emptyCases)
    }

    // ASSERTIONS textAttributedShapingContext27Observed
    func testMountedPaintIntervalsPreserveSlicesClippingAndRecordedPixels() throws {
        let font = testFont(cjk: false)
        let cases = ["a\u{34f}\u{301}", "e\u{301}", "fi", "AV", "x\u{301}\u{323}", "\u{34f}\u{34f}a"]
        let texts = cases.map { string -> Text in
            var text = Text(verbatim: "")
            for (index, scalar) in string.unicodeScalars.enumerated() {
                var part = Text(verbatim: String(scalar)).font(font)
                if index == 1 { part = part.foregroundColor(.red) }
                text = text + part
            }
            return text
        }
        try verifyDrawing(texts)
    }

    // ASSERTIONS textLinePublication27Observed
    func testMountedDeletedRunsPreserveFontHeightClippingAndRecordedPixels() throws {
        let regular = testFont(cjk: false)
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let large = VUI.Font.file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 46, weight: .regular)
        func text(_ value: String, _ font: VUI.Font) -> Text { Text(verbatim: value).font(font) }
        let hidden = text("\u{34f}", large)
        let cases = [
            text("x", regular) + hidden + text("a", regular),
            text("x", regular) + text("\u{34f}a", large),
            hidden + text("a", regular),
            text("x", regular) + hidden,
            text("\u{34f}", regular) + hidden,
            text("\u{34f}", regular) + hidden + text("a", regular),
            text("a", regular) + hidden + text("\u{301}", regular),
            text("x ", regular) + hidden + text("a", regular),
            text("x", regular) + text("\u{34f}a", regular).foregroundColor(.red),
            text("x", regular) + text("\u{34f}", regular).foregroundColor(.red) + text("a", regular),
            text("\u{34f}", regular) + text("\u{34f}a", regular).foregroundColor(.red),
            text("\u{34f}", regular).foregroundColor(.red) + text("\u{34f}a", regular),
        ]
        try verifyDrawing(cases, emptyCases: [4], emptyClippedCases: [0, 2, 3, 4, 5, 6, 7])
    }

    // ASSERTIONS textLinePublication27Observed
    func testMountedRawSlotReflowAndCopiedTokenPreserveRunPublication() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }

        let regular = testFont(cjk: false)
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let large = VUI.Font.file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"
        ), size: 46, weight: .regular)
        func part(_ value: String, font: VUI.Font, color: VUI.Color = .blue) -> Text {
            Text(verbatim: value).font(font).foregroundColor(color)
        }
        let cases: [(Text, [[[Int]]], [CGFloat], [CGFloat])] = [
            (
                part("x ", font: regular) + part("\u{34f}", font: regular, color: .red) +
                    part("a", font: regular),
                [[[0, 1]], [[2]], [[3]]],
                [15, 0, 12.5107421875],
                [15, 81, 21, 75]
            ),
            (
                part("x ", font: regular) + part("\u{34f}", font: large) +
                    part("a", font: regular),
                [[[0, 1]], [[], [3], [4]]],
                [15, 15],
                [15, 81, 21, 70]
            ),
        ]

        for (backend, rendering) in [("bitmap", VUI.Font.DefaultRenderingMode.bitmap()),
                                     ("vector", VUI.Font.DefaultRenderingMode.vector())] {
            for scale: CGFloat in [1, 2] {
                var environment = EnvironmentValues()
                environment.defaultFontRenderingMode = rendering
                environment.displayScale = 2
                environment._contentScaleFactor = scale
                for (index, input) in cases.enumerated() {
                    let (text, expectedRuns, expectedWidths, expectedMeasure) = input
                    for clips in [false, true] {
                        var images: [String: [UInt8]] = [:]
                        for mode in ["ordinary", "default", "measured", "slices"] {
                            let capture = LineBreakDrawingCapture()
                            capture.drawsSlices = mode == "slices"
                            let child = mode == "ordinary" ? AnyView(text) : mode == "measured"
                                ? AnyView(text.textRenderer(LineBreakDrawingMeasuredRenderer(capture: capture)))
                                : AnyView(text.textRenderer(LineBreakDrawingDefaultRenderer(capture: capture)))
                            let measured = LineBreakDrawingMeasure(
                                proposal: .init(width: 15, height: 100), capture: capture
                            ) { child }.padding(.top, 24).padding(.leading, 24)
                            let value = measured.frame(width: 320, height: 160, alignment: .topLeading)
                            let rendererHost = TestViewRendererHost()
                            let host = ViewGraph(rootViewType: AnyView.self, content: AnyView(value),
                                rendererHost: rendererHost, initialEnvironment: environment)
                            rendererHost.storage = host
                            host.setSize(CGSize(width: 320, height: 160))
                            host.updateOutputs(at: .zero)
                            let list = try host.data.withCurrent { try XCTUnwrap(host.displayList()) }
                            let label = "\(backend) scale=\(scale) case=\(index) clips=\(clips) \(mode)"
                            let clip = clips ? CGRect(x: 0, y: 0, width: 43, height: 48) : nil
                            let direct = try render(list, device: device,
                                resources: rendererHost.sceneResources, environment: environment,
                                replay: false, clip: clip)
                            let replay = try render(list, device: device,
                                resources: rendererHost.sceneResources, environment: environment,
                                replay: true, clip: clip)
                            XCTAssertEqual(direct, replay, "replay " + label)
                            images[mode] = direct
                            XCTAssertFalse(capture.measures.isEmpty, label)
                            for measure in capture.measures {
                                XCTAssertEqual(measure, expectedMeasure, label)
                            }
                            if mode != "ordinary" {
                                XCTAssertFalse(capture.runs.isEmpty, label)
                                XCTAssertFalse(capture.widths.isEmpty, label)
                                for runs in capture.runs { XCTAssertEqual(runs, expectedRuns, label) }
                                for widths in capture.widths {
                                    XCTAssertEqual(widths.count, expectedWidths.count, label)
                                    for (actual, expected) in zip(widths, expectedWidths) {
                                        XCTAssertEqual(actual, expected, accuracy: 0.000_001, label)
                                    }
                                }
                            }
                        }
                        let custom = [images["default"]!, images["measured"]!, images["slices"]!]
                        XCTAssertTrue(custom.dropFirst().allSatisfy { $0 == custom[0] },
                                      "custom owners \(backend) scale=\(scale) case=\(index) clips=\(clips)")
                    }
                }
            }
        }
    }

    private func verifyDrawing(_ cases: [Text], emptyCases: Set<Int> = [],
                               emptyClippedCases: Set<Int> = []) throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        for (backend, rendering) in [("bitmap", VUI.Font.DefaultRenderingMode.bitmap()),
                                     ("vector", VUI.Font.DefaultRenderingMode.vector())] {
            for scale: CGFloat in [1, 2] {
                var environment = EnvironmentValues()
                environment.defaultFontRenderingMode = rendering
                environment.displayScale = 2
                environment._contentScaleFactor = scale
                for (index, input) in cases.enumerated() {
                    for clips in [false, true] {
                        var images: [String: [UInt8]] = [:]
                        for mode in ["ordinary", "default", "measured", "slices"] {
                            let capture = LineBreakDrawingCapture()
                            capture.drawsSlices = mode == "slices"
                            let text = input.foregroundColor(.blue)
                            let child = mode == "ordinary" ? AnyView(text) : mode == "measured"
                                ? AnyView(text.textRenderer(LineBreakDrawingMeasuredRenderer(capture: capture)))
                                : AnyView(text.textRenderer(LineBreakDrawingDefaultRenderer(capture: capture)))
                            let measured = LineBreakDrawingMeasure(proposal: .init(width: 200, height: 100), capture: capture) {
                                child
                            }.padding(.top, 24).padding(.leading, 24)
                            let value = measured.frame(width: 320, height: 160, alignment: .topLeading)
                            let rendererHost = TestViewRendererHost()
                            let host = ViewGraph(rootViewType: AnyView.self, content: AnyView(value),
                                rendererHost: rendererHost, initialEnvironment: environment)
                            rendererHost.storage = host
                            host.setSize(CGSize(width: 320, height: 160))
                            host.updateOutputs(at: .zero)
                            let list = try host.data.withCurrent { try XCTUnwrap(host.displayList()) }
                            let label = "\(backend) scale=\(scale) case=\(index) clips=\(clips) \(mode)"
                            let direct = try render(list, device: device, resources: rendererHost.sceneResources,
                                environment: environment, replay: false,
                                clip: clips ? CGRect(x: 0, y: 0, width: 43, height: 48) : nil)
                            let replay = try render(list, device: device, resources: rendererHost.sceneResources,
                                environment: environment, replay: true,
                                clip: clips ? CGRect(x: 0, y: 0, width: 43, height: 48) : nil)
                            XCTAssertTrue(direct == replay, "replay " + label)
                            let hasInk = stride(from: 3, to: direct.count, by: 4).contains { direct[$0] != 0 }
                            XCTAssertEqual(hasInk, !emptyCases.contains(index) &&
                                !(clips && emptyClippedCases.contains(index)), label)
                            images[mode] = direct
                        }
                        let label = "\(backend) scale=\(scale) case=\(index) clips=\(clips)"
                        for mode in ["default", "measured", "slices"] {
                            XCTAssertTrue(images[mode]! == images["ordinary"]!, "owner \(mode) " + label)
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS textParagraphLineBreakDrawing27Observed textHangulShapingDrawing27Observed
    func testMountedCJKAndHangulLineBreaksPreserveGlyphSlicesAndRecordedPixels() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let cases: [(String, CGFloat, Bool, [CGFloat], [CGFloat], [[CGFloat]])] = [
            ("한국어 한글", 90, true, [69, 68, 27, 61], [68.54, 42.32], [[0, 21.16, 21.16, 21.16, 42.32, 21.16, 63.48, 5.06], [0, 21.16, 21.16, 21.16]]),
            ("한국어 한글", 90, false, [69, 68, 27, 61], [68.54, 42.32], [[0, 21.16, 21.16, 21.16, 42.32, 21.16, 63.48, 5.06], [0, 21.16, 21.16, 21.16]]),
            ("A A A A 漢字", 45, true, [37, 136, 27, 129], [36.524, 36.524, 23, 23], [[0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06], [0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06], [0, 23], [0, 23]]),
            ("A A A A 漢字", 45, false, [37, 136, 27, 129], [36.524, 36.524, 23, 23], [[0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06], [0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06], [0, 23], [0, 23]]),
            ("A A A A 漢字", 90, true, [64.5, 68, 27, 61], [54.786, 64.262], [[0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06, 36.524, 13.202, 49.726, 5.06], [0, 13.202, 13.202, 5.06, 18.262, 23, 41.262, 23]]),
            ("A A A A 漢字", 90, false, [73.5, 68, 27, 61], [73.048, 46], [[0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06, 36.524, 13.202, 49.726, 5.06, 54.786, 13.202, 67.988, 5.06], [0, 23, 23, 23]]),
            ("A A A A 漢字", 110, true, [73.5, 68, 27, 61], [73.048, 46], [[0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06, 36.524, 13.202, 49.726, 5.06, 54.786, 13.202, 67.988, 5.06], [0, 23, 23, 23]]),
            ("A A A A 漢字", 110, false, [96.5, 68, 27, 61], [96.048, 23], [[0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06, 36.524, 13.202, 49.726, 5.06, 54.786, 13.202, 67.988, 5.06, 73.048, 23], [0, 23]]),
            ("A A A A 日本語", 45, true, [37, 170, 27, 163], [36.524, 36.524, 23, 23, 23], [[0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06], [0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06], [0, 23], [0, 23], [0, 23]]),
            ("A A A A 日本語", 45, false, [37, 170, 27, 163], [36.524, 36.524, 23, 23, 23], [[0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06], [0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06], [0, 23], [0, 23], [0, 23]]),
            ("A A A A 日本語", 90, true, [73.5, 68, 27, 61], [73.048, 69], [[0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06, 36.524, 13.202, 49.726, 5.06, 54.786, 13.202, 67.988, 5.06], [0, 23, 23, 23, 46, 23]]),
            ("A A A A 日本語", 90, false, [73.5, 68, 27, 61], [73.048, 69], [[0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06, 36.524, 13.202, 49.726, 5.06, 54.786, 13.202, 67.988, 5.06], [0, 23, 23, 23, 46, 23]]),
            ("A A A A 日本語", 110, true, [96.5, 68, 27, 61], [96.048, 46], [[0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06, 36.524, 13.202, 49.726, 5.06, 54.786, 13.202, 67.988, 5.06, 73.048, 23], [0, 23, 23, 23]]),
            ("A A A A 日本語", 110, false, [96.5, 68, 27, 61], [96.048, 46], [[0, 13.202, 13.202, 5.06, 18.262, 13.202, 31.464, 5.06, 36.524, 13.202, 49.726, 5.06, 54.786, 13.202, 67.988, 5.06, 73.048, 23], [0, 23, 23, 23]]),
            ("漢字漢字", 45, true, [23, 136, 27, 129], [23, 23, 23, 23], [[0, 23], [0, 23], [0, 23], [0, 23]]),
            ("漢字漢字", 45, false, [23, 136, 27, 129], [23, 23, 23, 23], [[0, 23], [0, 23], [0, 23], [0, 23]]),
            ("漢字漢字", 90, true, [46, 68, 27, 61], [46, 46], [[0, 23, 23, 23], [0, 23, 23, 23]]),
            ("漢字漢字", 90, false, [69, 68, 27, 61], [69, 23], [[0, 23, 23, 23, 46, 23], [0, 23]]),
            ("漢字漢字", 110, true, [92, 34, 27, 27], [92], [[0, 23, 23, 23, 46, 23, 69, 23]]),
            ("漢字漢字", 110, false, [92, 34, 27, 27], [92], [[0, 23, 23, 23, 46, 23, 69, 23]]),
            ("日本語日本語", 45, true, [23, 204, 27, 197], [23, 23, 23, 23, 23, 23], [[0, 23], [0, 23], [0, 23], [0, 23], [0, 23], [0, 23]]),
            ("日本語日本語", 45, false, [23, 204, 27, 197], [23, 23, 23, 23, 23, 23], [[0, 23], [0, 23], [0, 23], [0, 23], [0, 23], [0, 23]]),
            ("日本語日本語", 90, true, [69, 68, 27, 61], [69, 69], [[0, 23, 23, 23, 46, 23], [0, 23, 23, 23, 46, 23]]),
            ("日本語日本語", 90, false, [69, 68, 27, 61], [69, 69], [[0, 23, 23, 23, 46, 23], [0, 23, 23, 23, 46, 23]]),
            ("日本語日本語", 110, true, [92, 68, 27, 61], [92, 46], [[0, 23, 23, 23, 46, 23, 69, 23], [0, 23, 23, 23]]),
            ("日本語日本語", 110, false, [92, 68, 27, 61], [92, 46], [[0, 23, 23, 23, 46, 23, 69, 23], [0, 23, 23, 23]]),
            ("漢字。漢字", 45, true, [23, 170, 27, 163], [23, 23, 23, 23, 23], [[0, 23], [0, 23], [0, 23], [0, 23], [0, 23]]),
            ("漢字。漢字", 45, false, [23, 170, 27, 163], [23, 23, 23, 23, 23], [[0, 23], [0, 23], [0, 23], [0, 23], [0, 23]]),
            ("漢字。漢字", 90, true, [69, 68, 27, 61], [69, 46], [[0, 23, 23, 23, 46, 23], [0, 23, 23, 23]]),
            ("漢字。漢字", 90, false, [69, 68, 27, 61], [69, 46], [[0, 23, 23, 23, 46, 23], [0, 23, 23, 23]]),
            ("漢字。漢字", 110, true, [69, 68, 27, 61], [69, 46], [[0, 23, 23, 23, 46, 23], [0, 23, 23, 23]]),
            ("漢字。漢字", 110, false, [92, 68, 27, 61], [92, 23], [[0, 23, 23, 23, 46, 23, 69, 23], [0, 23]]),
            ("（漢字）漢字", 45, true, [23, 204, 27, 197], [23, 23, 23, 23, 23, 23], [[0, 23], [0, 23], [0, 23], [0, 23], [0, 23], [0, 23]]),
            ("（漢字）漢字", 45, false, [23, 204, 27, 197], [23, 23, 23, 23, 23, 23], [[0, 23], [0, 23], [0, 23], [0, 23], [0, 23], [0, 23]]),
            ("（漢字）漢字", 90, true, [69, 102, 27, 95], [46, 69, 23], [[0, 23, 23, 23], [0, 23, 23, 23, 46, 23], [0, 23]]),
            ("（漢字）漢字", 90, false, [69, 102, 27, 95], [46, 69, 23], [[0, 23, 23, 23], [0, 23, 23, 23, 46, 23], [0, 23]]),
            ("（漢字）漢字", 110, true, [92, 68, 27, 61], [92, 46], [[0, 23, 23, 23, 46, 23, 69, 23], [0, 23, 23, 23]]),
            ("（漢字）漢字", 110, false, [92, 68, 27, 61], [92, 46], [[0, 23, 23, 23, 46, 23, 69, 23], [0, 23, 23, 23]]),
            ("漢字 漢字", 45, true, [28.5, 136, 27, 129], [23, 28.06, 23, 23], [[0, 23], [0, 23, 23, 5.06], [0, 23], [0, 23]]),
            ("漢字 漢字", 45, false, [28.5, 136, 27, 129], [23, 28.06, 23, 23], [[0, 23], [0, 23, 23, 5.06], [0, 23], [0, 23]]),
            ("漢字 漢字", 90, true, [51.5, 68, 27, 61], [51.06, 46], [[0, 23, 23, 23, 46, 5.06], [0, 23, 23, 23]]),
            ("漢字 漢字", 90, false, [74.5, 68, 27, 61], [74.06, 23], [[0, 23, 23, 23, 46, 5.06, 51.06, 23], [0, 23]]),
            ("漢字 漢字", 110, true, [97.5, 34, 27, 27], [97.06], [[0, 23, 23, 23, 46, 5.06, 51.06, 23, 74.06, 23]]),
            ("漢字 漢字", 110, false, [97.5, 34, 27, 27], [97.06], [[0, 23, 23, 23, 46, 5.06, 51.06, 23, 74.06, 23]]),
            ("A漢字B", 45, true, [38, 68, 27, 61], [36.202, 37.536], [[0, 13.202, 13.202, 23], [0, 23, 23, 14.536]]),
            ("A漢字B", 45, false, [38, 68, 27, 61], [36.202, 37.536], [[0, 13.202, 13.202, 23], [0, 23, 23, 14.536]]),
            ("A漢字B", 90, true, [74, 34, 27, 27], [73.738], [[0, 13.202, 13.202, 23, 36.202, 23, 59.202, 14.536]]),
            ("A漢字B", 90, false, [74, 34, 27, 27], [73.738], [[0, 13.202, 13.202, 23, 36.202, 23, 59.202, 14.536]]),
            ("A漢字B", 110, true, [74, 34, 27, 27], [73.738], [[0, 13.202, 13.202, 23, 36.202, 23, 59.202, 14.536]]),
            ("A漢字B", 110, false, [74, 34, 27, 27], [73.738], [[0, 13.202, 13.202, 23, 36.202, 23, 59.202, 14.536]]),
        ]
        for (backend, rendering) in [("bitmap", VUI.Font.DefaultRenderingMode.bitmap()),
                                     ("vector", VUI.Font.DefaultRenderingMode.vector())] {
            for scale: CGFloat in [1, 2] {
                var environment = EnvironmentValues()
                environment.defaultFontRenderingMode = rendering
                environment.displayScale = 2
                environment._contentScaleFactor = scale
                for (index, input) in cases.enumerated() {
                    let (string, width, avoids, metrics, widths, slices) = input
                    environment.avoidsOrphans = avoids
                    var images: [String: [UInt8]] = [:]
                    for mode in ["ordinary", "default", "measured"] {
                        let capture = LineBreakDrawingCapture()
                        let text = Text(verbatim: string).font(testFont()).foregroundColor(.blue)
                        let child = mode == "ordinary" ? AnyView(text) : mode == "default"
                            ? AnyView(text.textRenderer(LineBreakDrawingDefaultRenderer(capture: capture)))
                            : AnyView(text.textRenderer(LineBreakDrawingMeasuredRenderer(capture: capture)))
                        let value = LineBreakDrawingMeasure(proposal: .init(width: width, height: 400), capture: capture) {
                            child
                        }.frame(width: 320, height: 160, alignment: .topLeading)
                        let rendererHost = TestViewRendererHost()
                        let host = ViewGraph(rootViewType: AnyView.self, content: AnyView(value),
                            rendererHost: rendererHost, initialEnvironment: environment)
                        rendererHost.storage = host
                        host.setSize(CGSize(width: 320, height: 160))
                        host.updateOutputs(at: .zero)
                        let list = try host.data.withCurrent { try XCTUnwrap(host.displayList()) }
                        let label = "\(backend) scale=\(scale) case=\(index) \(mode)"
                        let direct = try render(list, device: device, resources: rendererHost.sceneResources,
                            environment: environment, replay: false)
                        let replay = try render(list, device: device, resources: rendererHost.sceneResources,
                            environment: environment, replay: true)
                        XCTAssertTrue(direct == replay, "replay " + label)
                        XCTAssertTrue(stride(from: 3, to: direct.count, by: 4).contains { direct[$0] != 0 }, label)
                        images[mode] = direct
                        XCTAssertFalse(capture.measures.isEmpty, label)
                        for actual in capture.measures { XCTAssertEqual(actual, metrics, label) }
                        if mode != "ordinary" {
                            XCTAssertFalse(capture.widths.isEmpty, label)
                            for actual in capture.widths {
                                XCTAssertEqual(actual.count, widths.count, label)
                                for (value, expected) in zip(actual, widths) {
                                    XCTAssertEqual(value, expected, accuracy: 0.000_001, label)
                                }
                            }
                            for actual in capture.slices {
                                XCTAssertEqual(actual.count, slices.count, label)
                                for (line, expected) in zip(actual, slices) {
                                    XCTAssertEqual(line.count, expected.count, label)
                                    for (value, reference) in zip(line, expected) {
                                        XCTAssertEqual(value, reference, accuracy: 0.000_001, label)
                                    }
                                }
                            }
                        }
                    }
                    let label = "\(backend) scale=\(scale) case=\(index)"
                    XCTAssertTrue(images["default"]! == images["measured"]!, "default/pass-through " + label)
                    XCTAssertTrue(images["ordinary"]! == images["measured"]!, "ordinary/custom " + label)
                }
            }
        }
    }

    private func testFont(cjk: Bool = true) -> VUI.Font {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return .file(root.appendingPathComponent(
            cjk ? "Sources/VUI/Resources/Fonts/NotoSansKR/NotoSansKR-VariableFont_wght.ttf"
                : "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"),
            size: 23, weight: cjk ? .thin : .regular)
    }

    private func render(_ list: DisplayList, device: GraphicsDeviceContext, resources: SceneResources,
                        environment: EnvironmentValues, replay: Bool, clip: CGRect? = nil) throws -> [UInt8] {
        let scale = environment._contentScaleFactor
        let size = CGSize(width: 320, height: 160)
        let extent = size * scale
        let commands = try XCTUnwrap(device.renderQueue()?.makeCommandBuffer())
        var context = try XCTUnwrap(GraphicsContext(sceneResources: resources, environment: environment,
            viewport: CGRect(origin: .zero, size: extent), contentOffset: .zero,
            contentScaleFactor: scale, resolution: extent, commandBuffer: commands))
        context.clear(with: .clear)
        if replay {
            var recording = context.recordingContext(size: size)
            if let clip { recording.clip(to: Path(clip)) }
            list.draw(in: recording)
            try XCTUnwrap(recording.recording).draw(in: context)
        } else {
            if let clip { context.clip(to: Path(clip)) }
            list.draw(in: context)
        }
        let done = expectation(description: "Line break drawing readback")
        commands.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [done], timeout: 15)
        let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(staging.contents()), count: Int(extent.width * extent.height) * 4))
    }
}

// The fixture measures and draws synchronously on its test thread.
private final class LineBreakDrawingCapture: @unchecked Sendable {
    var drawsSlices = false
    var measures: [[CGFloat]] = []
    var widths: [[CGFloat]] = []
    var runs: [[[[Int]]]] = []
    var slices: [[[CGFloat]]] = []
    func draw(_ layout: Text.Layout, in context: inout GraphicsContext) {
        widths.append(layout.map { $0.typographicBounds.width })
        let start = layout.first?.first?.characterIndices.first
        runs.append(layout.map { line in
            line.map { run in
                run.characterIndices.map { start?.distance(to: $0) ?? 0 }
            }
        })
        slices.append(layout.map { line in
            line.flatMap { run in run.flatMap { [$0.typographicBounds.rect.minX, $0.typographicBounds.width] } }
        })
        for line in layout {
            if drawsSlices {
                for run in line { for slice in run { context.draw(slice) } }
            } else { context.draw(line) }
        }
    }
}

private struct LineBreakDrawingDefaultRenderer: TextRenderer {
    let capture: LineBreakDrawingCapture
    func draw(layout: Text.Layout, in context: inout GraphicsContext) { capture.draw(layout, in: &context) }
}

private struct LineBreakDrawingMeasuredRenderer: TextRenderer {
    let capture: LineBreakDrawingCapture
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize { text.sizeThatFits(proposal) }
    func draw(layout: Text.Layout, in context: inout GraphicsContext) { capture.draw(layout, in: &context) }
}

private struct LineBreakDrawingMeasure: Layout {
    let proposal: ProposedViewSize
    let capture: LineBreakDrawingCapture
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let dimensions = subviews[0].dimensions(in: self.proposal)
        capture.measures.append([dimensions.width, dimensions.height,
            dimensions[.firstTextBaseline], dimensions[.lastTextBaseline]])
        return CGSize(width: dimensions.width, height: dimensions.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: self.proposal)
    }
}
