import Foundation
import XCTest
import VVD
@testable import VUI

final class TextGlyphCompositionTests: XCTestCase {
    // ASSERTIONS textGlyphSubmissionPartition27Observed textGlyphMaskOpacity27Observed
    // ASSERTIONS textGlyphPathOpacity27Observed
    func testGlyphPartitionsPreserveOpaqueOrderAndTranslucentCoverage() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let font = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let output = ProcessInfo.processInfo.environment["VUI_TEXT_GLYPH_COMPOSITION_OUTPUT"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for (backend, rendering) in [("bitmap", VUI.Font.DefaultRenderingMode.bitmap()),
                                      ("vector", VUI.Font.DefaultRenderingMode.vector())] {
            for scale: CGFloat in [1, 2] {
                for sample in ["single", "collapsed", "overlap", "mixed"] {
                    var images: [String: [UInt8]] = [:]
                    let modes = ["line", "run", "slice"] + (["collapsed", "overlap"].contains(sample)
                        ? (0..<7).map { "glyph\($0)" } : [])
                    for flavor in ["opaque", "color-half", "context-half"] {
                        let alpha = flavor == "color-half" ? 0.5 : 1.0
                        let first = Text(verbatim: sample == "single" ? "A" : sample == "overlap" ? "" : "AAA")
                            .font(.file(font, size: 23)).foregroundColor(.red.opacity(alpha)).kerning(-16)
                        let text = ["mixed", "overlap"].contains(sample)
                            ? first + Text(verbatim: "BBB BBB").font(.file(font, size: 31))
                                .foregroundColor(.blue.opacity(alpha)).kerning(-16)
                            : first
                        for mode in modes {
                            let value = text.textRenderer(GlyphCompositionRenderer(mode: mode,
                                opacity: flavor == "context-half" ? 0.5 : 1))
                                .lineLimit(1).minimumScaleFactor(1)
                                .padding(.top, 16).padding(.leading, 16)
                                .frame(width: 128, height: 128, alignment: .topLeading)
                            var environment = EnvironmentValues()
                            environment.defaultFontRenderingMode = rendering
                            environment.displayScale = scale
                            environment._contentScaleFactor = scale
                            let rendererHost = TestViewRendererHost()
                            let host = ViewGraph(rootViewType: AnyView.self, content: AnyView(value),
                                rendererHost: rendererHost, initialEnvironment: environment)
                            rendererHost.storage = host
                            host.setSize(CGSize(width: 128, height: 128))
                            host.updateOutputs(at: .zero)
                            let list = try host.data.withCurrent { try XCTUnwrap(host.displayList()) }
                            let label = "\(backend)-\(Int(scale))-\(sample)-\(flavor)-\(mode)"
                            let direct = try render(list, device: device, resources: rendererHost.sceneResources,
                                environment: environment, replay: false)
                            let replay = try render(list, device: device, resources: rendererHost.sceneResources,
                                environment: environment, replay: true)
                            compare(direct, replay, label: "replay " + label)
                            images[flavor + "-" + mode] = direct
                            if let output { try Data(direct).write(to: output.appendingPathComponent(label + ".rgba")) }
                        }
                    }
                    let label = "\(backend) scale=\(scale) \(sample)"
                    for flavor in ["opaque", "color-half", "context-half"] {
                        compare(images[flavor + "-line"]!, images[flavor + "-run"]!, label: "line/run \(flavor) " + label)
                    }
                    compare(images["opaque-line"]!, images["opaque-slice"]!, label: "opaque line/slice " + label)
                    for mode in modes {
                        compare(images["color-half-" + mode]!, images["context-half-" + mode]!, label: "opacity \(mode) " + label)
                    }
                    if sample != "single" {
                        XCTAssertTrue(images["color-half-line"]! != images["color-half-slice"]!, "opacity belongs to each submitted group: " + label)
                    }
                    if ["collapsed", "overlap"].contains(sample) {
                        for flavor in ["color-half", "context-half"] {
                            let whole = images[flavor + "-line"]!
                            let slices = (0..<7).map { images[flavor + "-glyph\($0)"]! }
                            let maximum = whole.indices.map { index in slices.map { $0[index] }.max()! }
                            if backend == "bitmap" {
                                compare(whole, maximum, label: "mask maximum \(flavor) " + label)
                            }
                            let wholeAlpha = stride(from: 3, to: whole.count, by: 4).map { whole[$0] }
                            let individual = images[flavor + "-slice"]!
                            let individualAlpha = stride(from: 3, to: individual.count, by: 4).map { individual[$0] }
                            XCTAssertLessThanOrEqual(wholeAlpha.max()!, 128, label)
                            XCTAssertGreaterThan(individualAlpha.max()!, 128, label)
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS textGlyphFontRunPartitions27Observed
    func testOrdinaryTextPreservesFontRunGroupsWithTheSameFill() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let font = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        for (backend, rendering) in [("bitmap", VUI.Font.DefaultRenderingMode.bitmap()),
                                      ("vector", VUI.Font.DefaultRenderingMode.vector())] {
            for scale: CGFloat in [1, 2] {
                for sameColor in [false, true] {
                    for alpha in [1.0, 0.5] {
                        let text = Text(verbatim: "AAA").font(.file(font, size: 23))
                            .foregroundColor(.red.opacity(alpha)).kerning(-16)
                            + Text(verbatim: "BBB BBB").font(.file(font, size: 31))
                                .foregroundColor((sameColor ? Color.red : Color.blue).opacity(alpha)).kerning(-16)
                        var images: [String: [UInt8]] = [:]
                        for mode in ["ordinary", "line", "run", "slice"] {
                            let child = mode == "ordinary" ? AnyView(text)
                                : AnyView(text.textRenderer(GlyphCompositionRenderer(mode: mode, opacity: 1)))
                            let value = child.lineLimit(1).minimumScaleFactor(1)
                                .padding(.top, 16).padding(.leading, 16)
                                .frame(width: 128, height: 128, alignment: .topLeading)
                            var environment = EnvironmentValues()
                            environment.defaultFontRenderingMode = rendering
                            environment.displayScale = scale
                            environment._contentScaleFactor = scale
                            let rendererHost = TestViewRendererHost()
                            let host = ViewGraph(rootViewType: AnyView.self, content: AnyView(value),
                                rendererHost: rendererHost, initialEnvironment: environment)
                            rendererHost.storage = host
                            host.setSize(CGSize(width: 128, height: 128))
                            host.updateOutputs(at: .zero)
                            let list = try host.data.withCurrent { try XCTUnwrap(host.displayList()) }
                            let label = "\(backend) scale=\(scale) sameColor=\(sameColor) alpha=\(alpha) \(mode)"
                            let direct = try render(list, device: device, resources: rendererHost.sceneResources,
                                environment: environment, replay: false)
                            let replay = try render(list, device: device, resources: rendererHost.sceneResources,
                                environment: environment, replay: true)
                            compare(direct, replay, label: "replay " + label)
                            images[mode] = direct
                        }
                        let label = "\(backend) scale=\(scale) sameColor=\(sameColor) alpha=\(alpha)"
                        compare(images["ordinary"]!, images["line"]!, label: "ordinary/line " + label)
                        compare(images["line"]!, images["run"]!, label: "line/run " + label)
                        if alpha == 1 {
                            compare(images["line"]!, images["slice"]!, label: "opaque line/slice " + label)
                        } else {
                            XCTAssertTrue(images["line"]! != images["slice"]!, "separate translucent submissions: " + label)
                            let whole = images["ordinary"]!
                            let maximum = stride(from: 3, to: whole.count, by: 4).map { whole[$0] }.max()!
                            XCTAssertGreaterThan(maximum, 128, "font runs own separate coverage groups: " + label)
                            XCTAssertLessThanOrEqual(maximum, 192, label)
                        }
                    }
                }
            }
        }
    }

    private func compare(_ actual: [UInt8], _ expected: [UInt8], label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        let pairs = zip(actual, expected)
        let count = pairs.filter { $0 != $1 }.count
        let delta = pairs.map { abs(Int($0) - Int($1)) }.max() ?? 0
        XCTAssertTrue(count == 0 && actual.count == expected.count,
                      "\(label): changedBytes=\(count), maxDelta=\(delta)", file: file, line: line)
    }

    private func render(_ list: DisplayList, device: GraphicsDeviceContext, resources: SceneResources,
                        environment: EnvironmentValues, replay: Bool) throws -> [UInt8] {
        let scale = environment._contentScaleFactor
        let extent = CGSize(width: 128, height: 128) * scale
        let commands = try XCTUnwrap(device.renderQueue()?.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(sceneResources: resources, environment: environment,
            viewport: CGRect(origin: .zero, size: extent), contentOffset: .zero,
            contentScaleFactor: scale, resolution: extent, commandBuffer: commands))
        context.clear(with: .clear)
        if replay {
            let recording = context.recordingContext(size: CGSize(width: 128, height: 128))
            list.draw(in: recording)
            try XCTUnwrap(recording.recording).draw(in: context)
        } else {
            list.draw(in: context)
        }
        let done = expectation(description: "Glyph composition readback")
        commands.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [done], timeout: 15)
        let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(staging.contents()), count: Int(extent.width * extent.height) * 4))
    }
}

private struct GlyphCompositionRenderer: TextRenderer {
    let mode: String
    let opacity: Double
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize {
        CGSize(width: 80, height: text.sizeThatFits(proposal).height)
    }
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        context.opacity = opacity
        if mode.hasPrefix("glyph") {
            let index = Int(mode.dropFirst(5))!
            let glyphs = layout.flatMap { $0.flatMap { Array($0) } }
            if index < glyphs.count { context.draw(glyphs[index]) }
            return
        }
        for line in layout {
            if mode == "run" { for run in line { context.draw(run) } }
            else if mode == "slice" { for run in line { for glyph in run { context.draw(glyph) } } }
            else { context.draw(line) }
        }
    }
}
