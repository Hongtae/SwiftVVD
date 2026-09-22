import Foundation
import XCTest
import VVD
@testable import VUI

final class TextNegativeMultilineTests: XCTestCase {
    // ASSERTIONS textNegativeMultilineFitting27Observed textNegativeMultilineDrawing27Observed
    func testMountedParagraphDrawingPreservesMetricsAndRecordedPixels() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let font = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let ordinarySizes: [CGSize] = [(55.0, 94.0), (14.5, 336), (45, 40), (20, 31),
            (55, 94), (14.5, 336), (45, 40), (20, 31), (33.5, 57), (20, 97), (24, 40), (20, 33),
            (33.5, 57), (20, 97), (24, 40), (20, 33)].map { CGSize(width: $0.0, height: $0.1) }
        var managerSizes = ordinarySizes
        managerSizes[2] = CGSize(width: 52, height: 26)
        managerSizes[10] = CGSize(width: 0, height: 26)
        managerSizes[11] = CGSize(width: 0, height: 22)
        managerSizes[14] = CGSize(width: 24.5, height: 40)
        let narrowY: [CGFloat] = [25.5, 52.5, 87.5, 124.5, 161.5, 198.5, 235.5, 272.5, 296.5, 316.5, 336.5]
        let originsY: [[CGFloat]] = [[33.5, 70.5], narrowY, [18.5], [20.5], [33.5, 70.5, 94.5], narrowY,
            [25.5, 41.5], [20.5, 33.5], [33.5], [33.5, 57.5, 77.5, 97.5], [18.5], [18.5],
            [33.5, 57.5], [33.5, 57.5, 77.5, 97.5], [25.5, 41.5], [21.5, 35.5]]
        for (backend, rendering) in [("bitmap", VUI.Font.DefaultRenderingMode.bitmap()),
                                     ("vector", VUI.Font.DefaultRenderingMode.vector())] {
            for scale: CGFloat in [1, 2] {
                for kind in ["kern", "tracking"] {
                    for index in ordinarySizes.indices {
                        let spacing: CGFloat = index < 8 ? -8 : -16
                        let separator = index % 8 < 4 ? "\n" : "\u{2028}"
                        let fitting = index % 4 >= 2
                        let proposal = ProposedViewSize(width: index % 2 == 0 ? 80 : 20, height: fitting ? 40 : 500)
                        func run(_ string: String, size: CGFloat, color: VUI.Color) -> Text {
                            let value = Text(verbatim: string).font(.file(font, size: size)).foregroundColor(color)
                            return kind == "kern" ? value.kerning(spacing) : value.tracking(spacing)
                        }
                        let text = run("AAA ", size: 23, color: .red)
                            + run("BBB BBB" + separator, size: 31, color: .blue)
                            + Text(verbatim: "CCC").font(.file(font, size: 17)).foregroundColor(.green)
                        var images: [String: [UInt8]] = [:]
                        for mode in ["ordinary", "default", "measured"] {
                            let capture = NegativeMultilineCapture()
                            let child = mode == "ordinary" ? AnyView(text) : mode == "default"
                                ? AnyView(text.textRenderer(NegativeMultilineDefaultRenderer(capture: capture)))
                                : AnyView(text.textRenderer(NegativeMultilineMeasuredRenderer(capture: capture)))
                            let value = NegativeMultilineMeasure(proposal: proposal, capture: capture) {
                                child.lineLimit(fitting ? 2 : nil).minimumScaleFactor(fitting ? 0.5 : 1)
                            }.foregroundStyle(.black).frame(width: 320, height: 160, alignment: .topLeading)
                            var environment = EnvironmentValues()
                            environment.defaultFontRenderingMode = rendering
                            environment.displayScale = 2
                            environment._contentScaleFactor = scale
                            let rendererHost = TestViewRendererHost()
                            let host = ViewGraph(rootViewType: AnyView.self, content: AnyView(value),
                                rendererHost: rendererHost, initialEnvironment: environment)
                            rendererHost.storage = host
                            host.setSize(CGSize(width: 320, height: 160))
                            host.updateOutputs(at: .zero)
                            let list = try host.data.withCurrent { try XCTUnwrap(host.displayList()) }
                            let label = "\(backend) scale=\(scale) \(kind) case=\(index + 1) \(mode)"
                            let direct = try render(list, device: device, resources: rendererHost.sceneResources,
                                environment: environment, replay: false)
                            let replay = try render(list, device: device, resources: rendererHost.sceneResources,
                                environment: environment, replay: true)
                            XCTAssertTrue(direct == replay, "replay " + label)
                            images[mode] = direct
                            XCTAssertFalse(capture.sizes.isEmpty, label)
                            for size in capture.sizes {
                                XCTAssertEqual(size, mode == "ordinary" ? ordinarySizes[index] : managerSizes[index], label)
                            }
                            if mode != "ordinary" {
                                XCTAssertFalse(capture.origins.isEmpty, label)
                                let expected = originsY[index].map { CGPoint(x: separator == "\n" ? 0 : 6, y: $0) }
                                for origins in capture.origins { XCTAssertEqual(origins, expected, label) }
                                for truncated in capture.truncated { XCTAssertEqual(truncated, index == 3, label) }
                            }
                            let hasInk = stride(from: 3, to: direct.count, by: 4).contains { direct[$0] != 0 }
                            XCTAssertEqual(hasInk, mode == "ordinary" || ![10, 11].contains(index), label)
                        }
                        let label = "\(backend) scale=\(scale) \(kind) case=\(index + 1)"
                        if !(kind == "kern" && index == 0) {
                            XCTAssertTrue(images["default"]! == images["measured"]!, "default/pass-through " + label)
                        }
                        if [1, 4, 5, 9, 12, 13].contains(index) {
                            XCTAssertTrue(images["ordinary"]! == images["default"]!, "ordinary/custom " + label)
                        }
                    }
                }
            }
        }
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
        } else {
            list.draw(in: context)
        }
        let done = expectation(description: "Multiline text readback")
        commands.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [done], timeout: 15)
        let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(staging.contents()), count: Int(extent.width * extent.height) * 4))
    }
}

// The fixture measures and draws synchronously on its test thread.
private final class NegativeMultilineCapture: @unchecked Sendable {
    var sizes: [CGSize] = []
    var origins: [[CGPoint]] = []
    var truncated: [Bool] = []
    func draw(_ layout: Text.Layout, in context: inout GraphicsContext) {
        origins.append(layout.map(\.origin))
        truncated.append(layout.isTruncated)
        for line in layout { context.draw(line) }
    }
}

private struct NegativeMultilineDefaultRenderer: TextRenderer {
    let capture: NegativeMultilineCapture
    func draw(layout: Text.Layout, in context: inout GraphicsContext) { capture.draw(layout, in: &context) }
}

private struct NegativeMultilineMeasuredRenderer: TextRenderer {
    let capture: NegativeMultilineCapture
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize { text.sizeThatFits(proposal) }
    func draw(layout: Text.Layout, in context: inout GraphicsContext) { capture.draw(layout, in: &context) }
}

private struct NegativeMultilineMeasure: Layout {
    let proposal: ProposedViewSize
    let capture: NegativeMultilineCapture
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let dimensions = subviews[0].dimensions(in: self.proposal)
        let size = CGSize(width: dimensions.width, height: dimensions.height)
        capture.sizes.append(size)
        return size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: self.proposal)
    }
}
