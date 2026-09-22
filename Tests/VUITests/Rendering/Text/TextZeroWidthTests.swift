import Foundation
import XCTest
import VVD
@testable import VUI

final class TextZeroWidthTests: XCTestCase {
    // ASSERTIONS textZeroWidthSubmission27Observed textRendererPaddedLayout27Observed
    // ASSERTIONS textZeroWidthCanvas27Observed
    func testMountedZeroWidthTextKeepsRendererLayoutBeforeDisplayAdmission() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        for rendering: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            for scale: CGFloat in [1, 2] {
                for sample in ["all", "prefix", "token", "positive"] {
                    var images: [String: [UInt8]] = [:]
                    for mode in ["text", "canvas-rect", "canvas-zero", "canvas-point", "line", "run", "slice",
                                 "line-pad1", "line-pad32", "line-force1", "line-force32",
                                 "line-leading1", "line-top1", "marker", "marker-pad1"] {
                        let capture = ZeroWidthCapture()
                        let width: CGFloat = sample == "prefix" || sample == "token" ? 1 : 80
                        let spacing: CGFloat = sample == "all" ? -24 : -16
                        let text = Text(verbatim: sample == "token" ? "WWW " : "AAA ")
                            .font(.file(file, size: 23)).foregroundColor(.red).kerning(spacing)
                            + Text(verbatim: sample == "token" ? "WWW WWW" : "BBB BBB")
                            .font(.file(file, size: 31)).foregroundColor(.blue).kerning(spacing)
                        let content: AnyView
                        if mode.hasPrefix("canvas") {
                            content = AnyView(Canvas { context, _ in
                                let resolved = context.resolve(text)
                                let size = resolved.measure(in: CGSize(width: width, height: 60))
                                capture.measures.append(size)
                                if mode == "canvas-point" {
                                    context.draw(resolved, at: CGPoint(x: 16, y: 16), anchor: .topLeading)
                                } else {
                                    context.draw(resolved, in: CGRect(x: 16, y: 16,
                                        width: mode == "canvas-zero" ? 0 : width, height: 60))
                                }
                            }.lineLimit(1).minimumScaleFactor(1).frame(width: 128, height: 128))
                        } else {
                            let value = mode == "text" ? AnyView(text)
                                : AnyView(text.textRenderer(ZeroWidthRenderer(capture: capture, mode: mode)))
                            content = AnyView(ZeroWidthMeasure(width: width, capture: capture) {
                                value.lineLimit(1).minimumScaleFactor(1)
                            }.padding(.top, 16).padding(.leading, 16)
                                .frame(width: 128, height: 128, alignment: .topLeading))
                        }
                        var environment = EnvironmentValues()
                        environment.defaultFontRenderingMode = rendering
                        environment.displayScale = 2
                        environment._contentScaleFactor = scale
                        let rendererHost = TestViewRendererHost()
                        let host = ViewGraph(rootViewType: AnyView.self, content: content,
                            rendererHost: rendererHost, initialEnvironment: environment)
                        rendererHost.storage = host
                        host.setSize(CGSize(width: 128, height: 128))
                        host.updateOutputs(at: .zero)
                        let label = "\(sample) \(mode) \(rendering) scale=\(scale)"
                        let custom = mode != "text" && !mode.hasPrefix("canvas")
                        if custom { XCTAssertFalse(capture.layouts.isEmpty, "before submission: " + label) }
                        let recordedCount = capture.layouts.count
                        let pixels = try host.data.withCurrent {
                            let list = try XCTUnwrap(host.displayList())
                            return try render(device: device, environment: environment) { list.draw(in: $0) }
                        }
                        XCTAssertEqual(capture.layouts.count, recordedCount, "replay uses retained commands: " + label)
                        images[mode] = pixels
                        let visible = mode.hasPrefix("canvas") || sample == "positive"
                            || mode.contains("pad") || mode.contains("force") || mode == "line-leading1"
                        XCTAssertEqual(pixels.contains { $0 != 0 }, visible, label)
                        if custom {
                            XCTAssertFalse(capture.layouts.isEmpty, label)
                            let expectedWidth: CGFloat = sample == "all" ? 0
                                : mode == "line-force1" ? 0
                                : sample == "positive" || mode == "line-pad32" || mode == "line-force32"
                                    ? (sample == "token" ? 29.4580078125 : 19.88671875) : 0
                            for layout in capture.layouts {
                                XCTAssertEqual(layout.count, 1, label)
                                XCTAssertEqual(layout[0].typographicBounds.width, expectedWidth, accuracy: 0.000001, label)
                                let expectedGlyphs = sample == "all" || expectedWidth == 19.88671875 ? 11
                                    : expectedWidth > 0 ? 6 : sample == "token" ? 1 : 3
                                XCTAssertEqual(layout[0].reduce(0) { $0 + $1.count }, expectedGlyphs, label)
                            }
                        }
                    }
                    let same: [[String]] = [
                        ["canvas-rect", "canvas-zero", "line-pad1", "line-leading1",
                         sample == "positive" ? "line" : "line-force1"],
                        ["line-pad32", "line-force32"],
                        ["line", "run", "line-top1"],
                    ]
                    for group in same {
                        for mode in group.dropFirst() {
                            XCTAssertTrue(images[group[0]] == images[mode],
                                "\(sample) \(group[0]) / \(mode) \(rendering) scale=\(scale)")
                        }
                    }
                    if sample != "token" {
                        XCTAssertTrue(images["canvas-point"] == images["line-pad32"], "\(sample) point / padded")
                    }
                }
            }
        }
    }

    func testRecordingSelectionRejectsDynamicStorageBeforeCustomAndArchiveFlags() {
        // ASSERTIONS textUnstyledRecordingSelection27Observed
        for flags: ArchivedViewInput.Flags in [[], .isArchived, .preciseTextLayout, [.isArchived, .preciseTextLayout]] {
            for custom in [false, true] {
                for dynamic in [false, true] {
                    let storage = NSAttributedString(string: "A", attributes: dynamic ? [.updateSchedule: false] : [:])
                    let owner = ResolvedStyledText.StringDrawing(storage: storage,
                        archiveOptions: .init(flags: flags), features: custom ? .customRenderer : [])
                    XCTAssertEqual(owner.needsRBDisplayList,
                        !dynamic && (custom || flags == [.isArchived, .preciseTextLayout]))
                }
            }
        }
    }

    private func render(device: GraphicsDeviceContext, environment: EnvironmentValues,
                        content: (GraphicsContext) -> Void) throws -> [UInt8] {
        let scale = environment._contentScaleFactor
        let extent = CGSize(width: 128, height: 128) * scale
        let queue = try XCTUnwrap(device.renderQueue())
        let buffer = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(sceneResources: SceneResources(), environment: environment,
            viewport: CGRect(origin: .zero, size: extent), contentOffset: .zero,
            contentScaleFactor: scale, resolution: extent, commandBuffer: buffer))
        context.clear(with: .clear)
        content(context)
        let done = expectation(description: "Mounted text completion")
        buffer.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(buffer.commit())
        wait(for: [done], timeout: 5)
        let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        return Array(UnsafeRawBufferPointer(start: pointer, count: Int(extent.width * extent.height) * 4))
    }
}

private final class ZeroWidthCapture: @unchecked Sendable {
    var measures: [CGSize] = []
    var layouts: [Text.Layout] = []
}

private struct ZeroWidthRenderer: TextRenderer {
    let capture: ZeroWidthCapture
    let mode: String
    var displayPadding: EdgeInsets {
        EdgeInsets(top: mode == "line-top1" ? 1 : 0, leading: mode == "line-leading1" ? 1 : 0, bottom: 0,
            trailing: mode == "line-pad1" || mode == "marker-pad1" ? 1 : mode == "line-pad32" ? 32 : 0)
    }
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize {
        let size = text.sizeThatFits(proposal)
        capture.measures.append(size)
        return CGSize(width: mode == "line-force1" ? 1 : mode == "line-force32" ? 32 : size.width, height: size.height)
    }
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        capture.layouts.append(layout)
        if mode.hasPrefix("marker") {
            context.fill(Path(CGRect(x: 20, y: 20, width: 2, height: 2)), with: .color(.red))
            return
        }
        for line in layout {
            if mode == "run" { for run in line { context.draw(run) } }
            else if mode == "slice" { for run in line { for slice in run { context.draw(slice) } } }
            else { context.draw(line) }
        }
    }
}

private struct ZeroWidthMeasure: Layout {
    let width: CGFloat
    let capture: ZeroWidthCapture
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let dimensions = subviews[0].dimensions(in: ProposedViewSize(width: width, height: 60))
        let size = CGSize(width: dimensions.width, height: dimensions.height)
        capture.measures.append(size)
        return size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: width, height: 60))
    }
}
