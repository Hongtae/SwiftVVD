import Foundation
import XCTest
import VVD
@testable import VUI

final class TextLineBreakDrawingTests: XCTestCase {
    // ASSERTIONS textParagraphLineBreakDrawing27Observed
    func testMountedCJKLineBreaksPreserveGlyphSlicesAndRecordedPixels() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let cases: [(String, CGFloat, Bool, [CGFloat], [CGFloat], [[CGFloat]])] = [
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

    private func testFont() -> VUI.Font {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return .file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/NotoSansKR/NotoSansKR-VariableFont_wght.ttf"), size: 23, weight: .thin)
    }

    private func render(_ list: DisplayList, device: GraphicsDeviceContext, resources: SceneResources,
                        environment: EnvironmentValues, replay: Bool) throws -> [UInt8] {
        let scale = environment._contentScaleFactor
        let size = CGSize(width: 320, height: 160)
        let extent = size * scale
        let commands = try XCTUnwrap(device.renderQueue()?.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(sceneResources: resources, environment: environment,
            viewport: CGRect(origin: .zero, size: extent), contentOffset: .zero,
            contentScaleFactor: scale, resolution: extent, commandBuffer: commands))
        context.clear(with: .clear)
        if replay {
            let recording = context.recordingContext(size: size)
            list.draw(in: recording)
            try XCTUnwrap(recording.recording).draw(in: context)
        } else { list.draw(in: context) }
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
    var measures: [[CGFloat]] = []
    var widths: [[CGFloat]] = []
    var slices: [[[CGFloat]]] = []
    func draw(_ layout: Text.Layout, in context: inout GraphicsContext) {
        widths.append(layout.map { $0.typographicBounds.width })
        slices.append(layout.map { line in
            line.flatMap { run in run.flatMap { [$0.typographicBounds.rect.minX, $0.typographicBounds.width] } }
        })
        for line in layout { context.draw(line) }
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
