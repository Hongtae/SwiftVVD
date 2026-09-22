import Foundation
import XCTest
import VVD
@testable import VUI

final class TextWordBoundaryDrawingTests: XCTestCase {
    // ASSERTIONS textParagraphWordBoundaryDrawing27Observed
    func testMountedWordBoundariesPreserveSourceFragmentsAndRecordedPixels() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let cases: [(String, CGFloat, Bool, [CGFloat], [CGFloat], [[CGFloat]])] = [
            ("A A A A don't", 90, true, [70, 54, 21, 48], [62.126953125, 69.8759765625], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125], [0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 12.97119140625, 33.68017578125, 13.1171875, 46.79736328125, 11.53369140625, 58.3310546875, 4.0205078125, 62.3515625, 7.5244140625]]),
            ("A A A A don't", 90, false, [83, 54, 21, 48], [82.8359375, 49.1669921875], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125, 62.126953125, 15.00390625, 77.130859375, 5.705078125], [0, 12.97119140625, 12.97119140625, 13.1171875, 26.08837890625, 11.53369140625, 37.6220703125, 4.0205078125, 41.642578125, 7.5244140625]]),
            ("A A A A don't", 110, true, [70, 54, 21, 48], [62.126953125, 69.8759765625], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125], [0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 12.97119140625, 33.68017578125, 13.1171875, 46.79736328125, 11.53369140625, 58.3310546875, 4.0205078125, 62.3515625, 7.5244140625]]),
            ("A A A A don't", 110, false, [83, 54, 21, 48], [82.8359375, 49.1669921875], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125, 62.126953125, 15.00390625, 77.130859375, 5.705078125], [0, 12.97119140625, 12.97119140625, 13.1171875, 26.08837890625, 11.53369140625, 37.6220703125, 4.0205078125, 41.642578125, 7.5244140625]]),
            ("A A A A don’t", 90, true, [71, 54, 21, 48], [62.126953125, 70.7294921875], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125], [0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 12.97119140625, 33.68017578125, 13.1171875, 46.79736328125, 11.80322265625, 58.6005859375, 4.6044921875, 63.205078125, 7.5244140625]]),
            ("A A A A don’t", 90, false, [83, 54, 21, 48], [82.8359375, 50.0205078125], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125, 62.126953125, 15.00390625, 77.130859375, 5.705078125], [0, 12.97119140625, 12.97119140625, 13.1171875, 26.08837890625, 11.80322265625, 37.8916015625, 4.6044921875, 42.49609375, 7.5244140625]]),
            ("A A A A don’t", 110, true, [71, 54, 21, 48], [62.126953125, 70.7294921875], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125], [0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 12.97119140625, 33.68017578125, 13.1171875, 46.79736328125, 11.80322265625, 58.6005859375, 4.6044921875, 63.205078125, 7.5244140625]]),
            ("A A A A don’t", 110, false, [83, 54, 21, 48], [82.8359375, 50.0205078125], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125, 62.126953125, 15.00390625, 77.130859375, 5.705078125], [0, 12.97119140625, 12.97119140625, 13.1171875, 26.08837890625, 11.80322265625, 37.8916015625, 4.6044921875, 42.49609375, 7.5244140625]]),
            ("A A A A BB-BB", 90, true, [83, 54, 21, 48], [82.8359375, 63.6767578125], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125, 62.126953125, 15.00390625, 77.130859375, 5.705078125], [0, 14.330078125, 14.330078125, 14.330078125, 28.66015625, 6.3564453125, 35.0166015625, 14.330078125, 49.3466796875, 14.330078125]]),
            ("A A A A BB-BB", 90, false, [83, 54, 21, 48], [82.8359375, 63.6767578125], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125, 62.126953125, 15.00390625, 77.130859375, 5.705078125], [0, 14.330078125, 14.330078125, 14.330078125, 28.66015625, 6.3564453125, 35.0166015625, 14.330078125, 49.3466796875, 14.330078125]]),
            ("A A A A BB-BB", 110, true, [83, 54, 21, 48], [82.8359375, 63.6767578125], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125, 62.126953125, 15.00390625, 77.130859375, 5.705078125], [0, 14.330078125, 14.330078125, 14.330078125, 28.66015625, 6.3564453125, 35.0166015625, 14.330078125, 49.3466796875, 14.330078125]]),
            ("A A A A BB-BB", 110, false, [83, 54, 21, 48], [82.8359375, 63.6767578125], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125, 62.126953125, 15.00390625, 77.130859375, 5.705078125], [0, 14.330078125, 14.330078125, 14.330078125, 28.66015625, 6.3564453125, 35.0166015625, 14.330078125, 49.3466796875, 14.330078125]]),
            ("A A A A e\u{0301}lan", 90, true, [64, 54, 21, 48], [62.126953125, 63.71044921875], [[4.5, 15.00390625, 19.50390625, 5.705078125, 25.208984375, 15.00390625, 40.212890625, 5.705078125, 45.91796875, 15.00390625, 60.921875, 5.705078125], [4.5, 15.00390625, 19.50390625, 5.705078125, 25.208984375, 12.1962890625, 37.4052734375, 5.5927734375, 42.998046875, 12.5107421875, 55.5087890625, 12.70166015625]]),
            ("A A A A e\u{0301}lan", 90, false, [83, 54, 21, 48], [82.8359375, 43.00146484375], [[4.5, 15.00390625, 19.50390625, 5.705078125, 25.208984375, 15.00390625, 40.212890625, 5.705078125, 45.91796875, 15.00390625, 60.921875, 5.705078125, 66.626953125, 15.00390625, 81.630859375, 5.705078125], [4.5, 12.1962890625, 16.6962890625, 5.5927734375, 22.2890625, 12.5107421875, 34.7998046875, 12.70166015625]]),
            ("A A A A e\u{0301}lan", 110, true, [64, 54, 21, 48], [62.126953125, 63.71044921875], [[4.5, 15.00390625, 19.50390625, 5.705078125, 25.208984375, 15.00390625, 40.212890625, 5.705078125, 45.91796875, 15.00390625, 60.921875, 5.705078125], [4.5, 15.00390625, 19.50390625, 5.705078125, 25.208984375, 12.1962890625, 37.4052734375, 5.5927734375, 42.998046875, 12.5107421875, 55.5087890625, 12.70166015625]]),
            ("A A A A e\u{0301}lan", 110, false, [83, 54, 21, 48], [82.8359375, 43.00146484375], [[4.5, 15.00390625, 19.50390625, 5.705078125, 25.208984375, 15.00390625, 40.212890625, 5.705078125, 45.91796875, 15.00390625, 60.921875, 5.705078125, 66.626953125, 15.00390625, 81.630859375, 5.705078125], [4.5, 12.1962890625, 16.6962890625, 5.5927734375, 22.2890625, 12.5107421875, 34.7998046875, 12.70166015625]]),
            ("A A A A café", 90, true, [65.5, 54, 21, 48], [62.126953125, 65.181640625], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125], [0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 12.0390625, 32.748046875, 12.5107421875, 45.2587890625, 7.7265625, 52.9853515625, 12.1962890625]]),
            ("A A A A café", 90, false, [83, 54, 21, 48], [82.8359375, 44.47265625], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125, 62.126953125, 15.00390625, 77.130859375, 5.705078125], [0, 12.0390625, 12.0390625, 12.5107421875, 24.5498046875, 7.7265625, 32.2763671875, 12.1962890625]]),
            ("A A A A café", 110, true, [65.5, 54, 21, 48], [62.126953125, 65.181640625], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125], [0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 12.0390625, 32.748046875, 12.5107421875, 45.2587890625, 7.7265625, 52.9853515625, 12.1962890625]]),
            ("A A A A café", 110, false, [83, 54, 21, 48], [82.8359375, 44.47265625], [[0, 15.00390625, 15.00390625, 5.705078125, 20.708984375, 15.00390625, 35.712890625, 5.705078125, 41.41796875, 15.00390625, 56.421875, 5.705078125, 62.126953125, 15.00390625, 77.130859375, 5.705078125], [0, 12.0390625, 12.0390625, 12.5107421875, 24.5498046875, 7.7265625, 32.2763671875, 12.1962890625]]),
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
                        let capture = WordBoundaryDrawingCapture()
                        let text = Text(verbatim: string).font(testFont()).foregroundColor(.blue)
                        let child = mode == "ordinary" ? AnyView(text) : mode == "default"
                            ? AnyView(text.textRenderer(WordBoundaryDrawingDefaultRenderer(capture: capture)))
                            : AnyView(text.textRenderer(WordBoundaryDrawingMeasuredRenderer(capture: capture)))
                        let value = WordBoundaryDrawingMeasure(proposal: .init(width: width, height: 400), capture: capture) {
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
                            for actual in capture.widths { XCTAssertEqual(actual, widths, label) }
                            for actual in capture.slices { XCTAssertEqual(actual, slices, label) }
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
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 23)
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
        let done = expectation(description: "Word boundary drawing readback")
        commands.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [done], timeout: 15)
        let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(staging.contents()), count: Int(extent.width * extent.height) * 4))
    }
}

// The fixture measures and draws synchronously on its test thread.
private final class WordBoundaryDrawingCapture: @unchecked Sendable {
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

private struct WordBoundaryDrawingDefaultRenderer: TextRenderer {
    let capture: WordBoundaryDrawingCapture
    func draw(layout: Text.Layout, in context: inout GraphicsContext) { capture.draw(layout, in: &context) }
}

private struct WordBoundaryDrawingMeasuredRenderer: TextRenderer {
    let capture: WordBoundaryDrawingCapture
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize { text.sizeThatFits(proposal) }
    func draw(layout: Text.Layout, in context: inout GraphicsContext) { capture.draw(layout, in: &context) }
}

private struct WordBoundaryDrawingMeasure: Layout {
    let proposal: ProposedViewSize
    let capture: WordBoundaryDrawingCapture
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
