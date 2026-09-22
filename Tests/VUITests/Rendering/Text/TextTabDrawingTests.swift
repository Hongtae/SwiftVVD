import Foundation
import XCTest
import VVD
@testable import VUI

final class TextTabDrawingTests: XCTestCase {
    // ASSERTIONS textTabStops27Observed textTabReflow27Observed
    func testMountedTabFragmentsPreserveGlyphPositionsAndRecordedPixels() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let a: CGFloat = 15.00390625
        let cases: [(String, CGFloat, Int?, Bool, [CGFloat], [CGFloat], [[CGFloat]], Bool)] = [
            ("A\tA", 8, nil, false, [8,81,21,75], [8,8,8], [[0,a],[0,28],[0,a]], false),
            ("A\tA", 8, 2, false, [8,54,21,48], [8,8], [[0,a],[0,28,28,a]], false),
            ("A\tA", 30, nil, false, [28,54,21,48], [28,a], [[0,a,a,28-a],[0,a]], true),
            ("A\tA", 70, nil, false, [43.5,27,21,21], [28+a], [[0,a,a,28-a,28,a]], true),
            ("\tA", 8, nil, false, [8,54,21,48], [8,8], [[0,28],[0,a]], false),
            ("A\tA\tA", 30, 2, false, [28,54,21,48], [28,15.3857421875], [[0,a,a,28-a],[0,15.3857421875]], true),
            ("A\tA\tA", 70, nil, false, [43.5,54,21,48], [28+a,28+a], [[0,a,a,28-a,28,a],[0,28,28,a]], true),
            ("A\tA\tA", 8, 2, true, [8,54,21,48], [8,8,15.3857421875,58.76904296875],
                [[0,a],[0,28],[-20,15.3857421875],[-4.6142578125,5.705078125,1.0908203125,20.169921875,
                  21.2607421875,13.1171875,34.3779296875,7.58056640625,41.95849609375,12.1962890625]], true),
            ("A\tA\tA", 70, nil, true, [59,81,21,75], [56,a,58.76904296875],
                [[0,a,a,28-a,28,a,28+a,28-a],[0,a],[0,58.76904296875]], true),
            ("AA\tA", 70, nil, false, [43.5,54,21,48], [2*a,28+a], [[0,a,a,a],[0,28,28,a]], true),
        ]
        for (backend, rendering) in [("bitmap", VUI.Font.DefaultRenderingMode.bitmap()),
                                     ("vector", VUI.Font.DefaultRenderingMode.vector())] {
            for scale: CGFloat in [1, 2] {
                var environment = EnvironmentValues()
                environment.defaultFontRenderingMode = rendering
                environment.displayScale = 2
                environment._contentScaleFactor = scale
                for (index, input) in cases.enumerated() {
                    let (string, width, limit, suffix, metrics, widths, slices, ordinaryEqual) = input
                    var images: [String: [UInt8]] = [:]
                    for mode in ["ordinary", "default", "measured"] {
                        let capture = TabDrawingCapture()
                        let text = Text(verbatim: string).font(testFont()).foregroundColor(.blue)
                        var child = mode == "ordinary" ? AnyView(text) : mode == "default"
                            ? AnyView(text.textRenderer(TabDrawingDefaultRenderer(capture: capture)))
                            : AnyView(text.textRenderer(TabDrawingMeasuredRenderer(capture: capture)))
                        if suffix {
                            child = AnyView(child.textSuffix(.alwaysVisible(Text(verbatim: " more")
                                .font(testFont()).foregroundColor(.green))))
                        }
                        let value = TabDrawingMeasure(proposal: .init(width: width, height: 120), capture: capture) {
                            child.lineLimit(limit)
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
                    if ordinaryEqual {
                        XCTAssertTrue(images["ordinary"]! == images["measured"]!, "ordinary/custom " + label)
                    }
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
        let done = expectation(description: "Tab drawing readback")
        commands.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [done], timeout: 15)
        let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(staging.contents()), count: Int(extent.width * extent.height) * 4))
    }
}

// The fixture measures and draws synchronously on its test thread.
private final class TabDrawingCapture: @unchecked Sendable {
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

private struct TabDrawingDefaultRenderer: TextRenderer {
    let capture: TabDrawingCapture
    func draw(layout: Text.Layout, in context: inout GraphicsContext) { capture.draw(layout, in: &context) }
}

private struct TabDrawingMeasuredRenderer: TextRenderer {
    let capture: TabDrawingCapture
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize { text.sizeThatFits(proposal) }
    func draw(layout: Text.Layout, in context: inout GraphicsContext) { capture.draw(layout, in: &context) }
}

private struct TabDrawingMeasure: Layout {
    let proposal: ProposedViewSize
    let capture: TabDrawingCapture
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
