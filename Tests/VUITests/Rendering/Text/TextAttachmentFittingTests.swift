import Foundation
import XCTest
import VVD
@testable import VUI

final class TextAttachmentFittingTests: XCTestCase {
    // ASSERTIONS fontGraphicsFitting27Observed
    func testMountedSuppliedFittingPreservesDrawingAndRecordedPixels() throws {
        let device = try graphicsDevice()
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let data = try Data(contentsOf: file)
        for bitmap in [false, true] {
            for memory in [false, true] {
                for scale: CGFloat in [1, 2] {
                    var environment = EnvironmentValues()
                    environment.defaultFontRenderingMode = bitmap ? .bitmap() : .vector()
                    environment.displayScale = 2
                    environment._contentScaleFactor = scale
                    var images: [String: [UInt8]] = [:]
                    for mode in ["ordinary", "default", "measured", "ordinaryReference", "managerReference"] {
                        let reference = mode.hasSuffix("Reference")
                        let custom = mode != "ordinary" && mode != "ordinaryReference"
                        let factor: CGFloat = reference ? (custom ? 0.7421875 : 0.75) : 1
                        var backends: [VVD.Font] = []
                        func font(_ original: CGFloat) throws -> VUI.Font {
                            let size = !custom && reference ? (original * factor * 4).rounded() / 4 : original * factor
                            let backend: VVD.Font
                            if bitmap {
                                backend = try XCTUnwrap(memory ? TextureFont(deviceContext: device, data: data)
                                    : TextureFont(deviceContext: device, path: file.path))
                            } else {
                                backend = try XCTUnwrap(memory ? VVD.Font(data: data) : VVD.Font(path: file.path))
                            }
                            backend.setPointSize(size, dpi: (UInt32(72 * scale), UInt32(72 * scale)))
                            XCTAssertTrue(backend.setVariationCoordinates([0x77676874: 530.0013885498047, 0x77647468: 90]))
                            backends.append(backend)
                            return (backend as? TextureFont).map { VUI.Font($0) } ?? VUI.Font(vector: backend)
                        }
                        let text = try Text(verbatim: "AAA ").font(font(23.375)).foregroundColor(.red)
                            + Text(verbatim: "BBB BBB").font(font(31.375)).foregroundColor(.blue)
                        let capture = AttachmentFittingCapture()
                        let child = !custom ? AnyView(text) : mode == "default"
                            ? AnyView(text.textRenderer(AttachmentFittingDefaultRenderer(capture: capture)))
                            : AnyView(text.textRenderer(AttachmentFittingMeasuredRenderer(capture: capture)))
                        let value = AttachmentFittingMeasure(proposal: .init(width: 80, height: 120), capture: capture) {
                            child.lineLimit(2).minimumScaleFactor(reference ? 1 : 0.5)
                        }.foregroundStyle(.black).frame(width: 320, height: 160, alignment: .topLeading)
                        let rendererHost = TestViewRendererHost()
                        let host = ViewGraph(rootViewType: AnyView.self, content: AnyView(value),
                            rendererHost: rendererHost, initialEnvironment: environment)
                        rendererHost.storage = host
                        host.setSize(CGSize(width: 320, height: 160))
                        host.updateOutputs(at: .zero)
                        let list = try host.data.withCurrent { try XCTUnwrap(host.displayList()) }
                        let label = "bitmap=\(bitmap) memory=\(memory) scale=\(scale) \(mode)"
                        let direct = try render(list, device: device, resources: rendererHost.sceneResources,
                            environment: environment, replay: false)
                        let replay = try render(list, device: device, resources: rendererHost.sceneResources,
                            environment: environment, replay: true)
                        XCTAssertTrue(direct == replay, "recording " + label)
                        XCTAssertTrue(stride(from: 3, to: direct.count, by: 4).contains { direct[$0] != 0 }, label)
                        XCTAssertFalse(capture.measures.isEmpty, label)
                        for actual in capture.measures { XCTAssertEqual(actual, [80,56,22,50], label) }
                        images[mode] = direct
                        if !reference { XCTAssertEqual(backends.map(\.pointSize), [23.375, 31.375], label) }
                        XCTAssertTrue(backends.allSatisfy { $0.dpi.y == UInt32(72 * scale) }, label)
                    }
                    XCTAssertTrue(images["ordinary"]! == images["ordinaryReference"]!)
                    XCTAssertTrue(images["default"]! == images["measured"]!)
                    XCTAssertTrue(images["measured"]! == images["managerReference"]!)
                }
            }
        }
    }

    // ASSERTIONS textAttachmentFittingDrawing27Observed textAttachmentFittingMetrics27Observed textAttachmentSuffixConfiguration27Observed
    func testMountedAttachmentFittingPreservesDrawingAndRecordedPixels() throws {
        let device = try graphicsDevice()
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
                for index in Self.managerMetrics.indices {
                    let family = index / 8
                    let texture = family == 1 || family == 2
                        ? try imageTexture(family == 1 ? CGSize(width: 40, height: 10) : CGSize(width: 10, height: 40), device: device)
                        : nil
                    let proposal = ProposedViewSize(width: index % 8 < 4 ? 80 : 30, height: index % 4 < 2 ? 120 : 24)
                    var images: [String: [UInt8]] = [:]
                    for mode in ["ordinary", "default", "measured", "reference"] {
                        let capture = AttachmentFittingCapture()
                        let text = mixedText(texture, factor: mode == "reference" ? Self.managerScales[index] : 1)
                        var child = mode == "ordinary" ? AnyView(text) : mode == "default"
                            ? AnyView(text.textRenderer(AttachmentFittingDefaultRenderer(capture: capture)))
                            : AnyView(text.textRenderer(AttachmentFittingMeasuredRenderer(capture: capture)))
                        if family == 3 {
                            child = AnyView(child.textSuffix(.alwaysVisible(Text(verbatim: " more")
                                .font(testFont(11)).foregroundColor(.green))))
                        }
                        let minimum: CGFloat = mode == "reference" || index % 2 == 0 ? 1 : 0.5
                        let value = AttachmentFittingMeasure(proposal: proposal, capture: capture) {
                            child.lineLimit(2).minimumScaleFactor(minimum)
                        }.foregroundStyle(.black).frame(width: 320, height: 160, alignment: .topLeading)
                        let rendererHost = TestViewRendererHost()
                        let host = ViewGraph(rootViewType: AnyView.self, content: AnyView(value),
                            rendererHost: rendererHost, initialEnvironment: environment)
                        rendererHost.storage = host
                        host.setSize(CGSize(width: 320, height: 160))
                        host.updateOutputs(at: .zero)
                        let list = try host.data.withCurrent { try XCTUnwrap(host.displayList()) }
                        let label = "\(backend) scale=\(scale) case=\(index + 1) \(mode)"
                        let direct = try render(list, device: device, resources: rendererHost.sceneResources,
                            environment: environment, replay: false)
                        let replay = try render(list, device: device, resources: rendererHost.sceneResources,
                            environment: environment, replay: true)
                        XCTAssertTrue(direct == replay, "replay " + label)
                        XCTAssertTrue(stride(from: 3, to: direct.count, by: 4).contains { direct[$0] != 0 }, label)
                        images[mode] = direct
                        XCTAssertFalse(capture.measures.isEmpty, label)
                        let expected = mode == "ordinary" ? Self.ordinaryMetrics[index] : Self.managerMetrics[index]
                        for actual in capture.measures { XCTAssertEqual(actual, expected, label) }
                        if mode != "ordinary" {
                            XCTAssertFalse(capture.lines.isEmpty, label)
                            for truncated in capture.truncated {
                                XCTAssertEqual(truncated, index < 24 && ![1, 9, 17].contains(index), label)
                            }
                            if mode != "reference" {
                                for actual in capture.lines {
                                    let expected = Self.managerLines[index]
                                    XCTAssertEqual(actual.count, expected.count, label)
                                    for (line, values) in zip(actual, expected) {
                                        for (a, b) in zip(line, values) { XCTAssertEqual(a, b, accuracy: 0.000001, label) }
                                    }
                                }
                            }
                        }
                    }
                    let label = "\(backend) scale=\(scale) case=\(index + 1)"
                    XCTAssertTrue(images["default"]! == images["measured"]!, "default/pass-through " + label)
                    XCTAssertTrue(images["measured"]! == images["reference"]!, "selected-font copy " + label)
                    if ![1, 2, 9, 13, 17, 18].contains(index) {
                        XCTAssertTrue(images["ordinary"]! == images["measured"]!, "ordinary/custom " + label)
                    }
                }
            }
        }
    }

    // ASSERTIONS textAttachmentFittingMetrics27Observed textAttachmentFontCopy27Observed textAttachmentSuffixConfiguration27Observed
    func testMixedImageAndSuffixFittingPreservesEachOwnersMetrics() throws {
        let device = try graphicsDevice()
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        for contentScale: CGFloat in [1, 2] {
            for index in Self.managerMetrics.indices {
                let family = index / 8
                let texture = family == 1 || family == 2
                    ? try imageTexture(family == 1 ? CGSize(width: 40, height: 10) : CGSize(width: 10, height: 40), device: device)
                    : nil
                for custom in [false, true] {
                    let rendererHost = TestViewRendererHost()
                    let host = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
                    rendererHost.storage = host
                    var environment = EnvironmentValues()
                    environment.defaultFontRenderingMode = .vector()
                    environment.displayScale = 2
                    environment._contentScaleFactor = contentScale
                    environment.lineLimit = 2
                    environment.minimumScaleFactor = index % 2 == 0 ? 1 : 0.5
                    let text = mixedText(texture)
                    var child = custom ? AnyView(text.textRenderer(AttachmentFittingRenderer())) : AnyView(text)
                    if family == 3 {
                        child = AnyView(child.textSuffix(.alwaysVisible(Text(verbatim: " more")
                            .font(testFont(11)).foregroundColor(.green))))
                    }
                    try host.data.withCurrent {
                        let graph = host.data.graph
                        let outputs = AnyView._makeView(view: _GraphValue(_attribute: graph.makeInput(value: child)),
                            inputs: inputs(graph: graph, environment: environment))
                        let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
                        let owner = try XCTUnwrap(computer.box as? LayoutEngineBox<StyledTextLayoutEngine>).engine.text
                        let label = "case=\(index + 1) scale=\(contentScale) custom=\(custom)"
                        let isManager = custom || family == 3
                        XCTAssertEqual(owner is ResolvedStyledText.TextLayoutManager, isManager, label)
                        let expected = isManager ? Self.managerMetrics[index] : Self.ordinaryMetrics[index]
                        let request = CGSize(width: index % 8 < 4 ? 80 : 30, height: index % 4 < 2 ? 120 : 24)
                        let metrics = owner.metrics(in: request, layoutMargins: nil)
                        XCTAssertEqual(metrics.size, CGSize(width: expected[0], height: expected[1]), label)
                        XCTAssertEqual(metrics.firstBaseline, expected[2], label)
                        XCTAssertEqual(metrics.lastBaseline, expected[3], label)
                        XCTAssertEqual(metrics.scale, isManager ? Self.managerScales[index] : Self.ordinaryScales[index], label)
                        XCTAssertEqual(metrics.numberOfLines, index % 4 < 2 ? 2 : 1, label)
                        XCTAssertEqual(metrics.hasTruncatedRanges, ![1, 9, 17, 25].contains(index), label)
                        XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                        if let manager = owner as? ResolvedStyledText.TextLayoutManager {
                            XCTAssertEqual(manager.attachments.characterIndices, family == 3 ? [11] : [], label)
                        }
                    }
                }
            }
        }
    }

    private static let managerLines: [[[CGFloat]]] = [
        [[0, 25.5, 50.716796875, 21, 6], [0, 60.5, 78.6806640625, 29, 8]],
        [[0, 25.5, 80, 21, 6], [0, 52.5, 42.552154541015625, 21, 6]],
        [[0, 25.5, 60.3974609375, 21, 6]],
        [[0, 18.5, 78.20068359375, 14, 4]],
        [[0, 25.5, 15.00390625, 21, 6], [0, 52.5, 15.3857421875, 21, 6]],
        [[0, 15.5, 25.3583984375, 11, 3], [0, 32.5, 29.68310546875, 14, 4]],
        [[0, 25.5, 15.3857421875, 21, 6]],
        [[0, 15.5, 22.69677734375, 11, 3]],
        [[0, 25.5, 50.716796875, 21, 6], [0, 52.5, 60.7373046875, 21, 6]],
        [[0, 18.5, 72.49044799804688, 14, 4], [0, 40.5, 79.16598510742188, 18, 5]],
        [[0, 25.5, 60.3974609375, 21, 6]],
        [[0, 15.5, 75.72705078125, 11, 3]],
        [[0, 25.5, 15.00390625, 21, 6], [0, 52.5, 15.3857421875, 21, 6]],
        [[0, 15.5, 25.3583984375, 11, 3], [0, 29.5, 7.69287109375, 11, 3]],
        [[0, 25.5, 15.3857421875, 21, 6]],
        [[0, 15.5, 22.69677734375, 11, 3]],
        [[0, 44.5, 60.716796875, 40, 6], [0, 79.5, 78.6806640625, 29, 8]],
        [[0, 44.5, 80, 40, 5], [0, 67.5, 37.119964599609375, 18, 5]],
        [[0, 44.5, 60.3974609375, 40, 6]],
        [[0, 44.5, 74.69873046875, 40, 4]],
        [[0, 25.5, 15.00390625, 21, 6], [0, 52.5, 15.3857421875, 21, 6]],
        [[0, 15.5, 25.3583984375, 11, 3], [0, 58.5, 20.36865234375, 40, 3]],
        [[0, 25.5, 15.3857421875, 21, 6]],
        [[0, 15.5, 22.69677734375, 11, 3]],
        [[0, 25.5, 50.716796875, 21, 6], [0, 60.5, 20.7373046875, 28.759765625, 7.568359375], [20.7373046875, 60.5, 28.10693359375, 10, 3]],
        [[0, 25.5, 80, 21, 6], [0, 52.5, 70.65908813476562, 21, 6]],
        [[0, 25.5, 30.3896484375, 21.337890625, 5.615234375], [30.3896484375, 25.5, 28.10693359375, 10, 3]],
        [[0, 18.5, 42.70849609375, 14.3798828125, 3.7841796875], [42.70849609375, 18.5, 28.10693359375, 10, 3]],
        [[0, 25.5, 15.00390625, 21, 6], [0, 52.5, 15.00390625, 21, 6]],
        [[0, 15.5, 25.3583984375, 11, 3], [0, 32.5, 30, 14, 4]],
        [[0, 25.5, 15.00390625, 21, 6]],
        [[0, 15.5, 25.3583984375, 11, 3]]]

    private static let managerMetrics: [[CGFloat]] = [
        [79,64,21,56], [80,54,21,48], [60.5,27,21,21], [78.5,18,14,14],
        [15.5,54,21,48], [30,32,11,28], [15.5,27,21,21], [23,14,11,11],
        [61,54,21,48], [79.5,41,14,36], [60.5,27,21,21], [76,14,11,11],
        [15.5,54,21,48], [25.5,28,11,25], [15.5,27,21,21], [23,14,11,11],
        [79,83,40,75], [80,68,40,63], [60.5,46,40,40], [75,44,40,40],
        [15.5,54,21,48], [25.5,57,11,54], [15.5,27,21,21], [23,14,11,11],
        [51,64,21,56], [80,54,21,48], [58.5,27,21,21], [71,18,14,14],
        [15.5,54,21,48], [30,32,11,28], [15.5,27,21,21], [25.5,14,11,11]]
    private static let ordinaryMetrics: [[CGFloat]] = {
        var result = managerMetrics
        for (index, values): (Int, [CGFloat]) in [(1, [80,52,21,47]), (2, [66,27,21,21]),
            (9, [80,42,14,37]), (18, [66,46,40,40])] { result[index] = values }
        return result
    }()
    private static let managerScales: [CGFloat] = [
        1,0.734375,1,0.5,1,0.5,1,0.5, 1,0.640625,1,0.5,1,0.5,1,0.5,
        1,0.640625,1,0.5,1,0.5,1,0.5, 1,0.734375,1,0.5,1,0.5,1,0.5]
    private static let ordinaryScales: [CGFloat] = {
        var result = managerScales
        result[1] = 0.7265625
        result[9] = 0.6484375
        result[17] = 0.6484375
        return result
    }()

    // ASSERTIONS textAttachmentFittingOwners27Observed
    func testInlineImageGraphResolutionRetainsTheConcreteTextOwner() throws {
        let device = try graphicsDevice()
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        for contentScale: CGFloat in [1, 2] {
            for size in [CGSize(width: 40, height: 10), CGSize(width: 10, height: 40)] {
                let texture = try imageTexture(size, device: device)
                let text = mixedText(texture)
                for custom in [false, true] {
                    let rendererHost = TestViewRendererHost()
                    let host = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
                    rendererHost.storage = host
                    var environment = EnvironmentValues()
                    environment.defaultFontRenderingMode = .vector()
                    environment.displayScale = 2
                    environment._contentScaleFactor = contentScale
                    let child = custom ? AnyView(text.textRenderer(AttachmentFittingRenderer())) : AnyView(text)
                    try host.data.withCurrent {
                        let graph = host.data.graph
                        let outputs = AnyView._makeView(view: _GraphValue(_attribute: graph.makeInput(value: child)),
                            inputs: inputs(graph: graph, environment: environment))
                        let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
                        let engine = try XCTUnwrap(computer.box as? LayoutEngineBox<StyledTextLayoutEngine>).engine
                        let label = "size=\(size) scale=\(contentScale) custom=\(custom)"
                        XCTAssertNotNil(engine.text.resolvedText, label)
                        if custom {
                            XCTAssertTrue(engine.text is ResolvedStyledText.TextLayoutManager, label)
                        } else {
                            XCTAssertTrue(engine.text is ResolvedStyledText.StringDrawing, label)
                        }
                        guard let source = engine.text.resolvedText else { return }
                        XCTAssertTrue(source.hasAttachments, label)
                        XCTAssertTrue(source.resolvedProperties?.customAttachments.isEmpty == true, label)
                        let measured = engine.sizeThatFits(.init(width: 80, height: 120))
                        XCTAssertGreaterThan(measured.width, 0, label)
                    }
                }
            }
        }
    }

    // ASSERTIONS textAttachmentFittingOwners27Observed textAttachmentFontCopy27Observed
    func testFontCopiesPreserveInlineImageDimensionsAndAttributes() throws {
        let device = try graphicsDevice()
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let queue = try XCTUnwrap(device.renderQueue())
        for contentScale: CGFloat in [1, 2] {
            for size in [CGSize(width: 40, height: 10), CGSize(width: 10, height: 40)] {
                let texture = try imageTexture(size, device: device)
                var environment = EnvironmentValues()
                environment.defaultFontRenderingMode = .vector()
                environment.displayScale = 2
                environment._contentScaleFactor = contentScale
                let commands = try XCTUnwrap(queue.makeCommandBuffer())
                let context = try XCTUnwrap(GraphicsContext(sceneResources: SceneResources(), environment: environment,
                    viewport: CGRect(x: 0, y: 0, width: 320 * contentScale, height: 160 * contentScale),
                    contentOffset: .zero, contentScaleFactor: contentScale,
                    resolution: CGSize(width: 320 * contentScale, height: 160 * contentScale), commandBuffer: commands))
                let owner = context.resolve(mixedText(texture)).resolved
                XCTAssertTrue(owner is ResolvedStyledText.StringDrawing)
                let source = try XCTUnwrap(owner.resolvedText)
                XCTAssertTrue(source.resolvedProperties?.customAttachments.isEmpty == true)
                for factor: CGFloat in [1, 0.5, 0.63] {
                    let scaled = source.scalingFonts(by: factor, toMultipleOf: nil)
                    let storage = scaled.attributedStorage
                    XCTAssertEqual(storage.string, "AAA \u{fffc}BBB BBB")
                    for (index, points): (Int, CGFloat) in [(0, 23), (4, 23), (5, 31)] {
                        let font = storage.attribute(.coreFont, at: index, effectiveRange: nil) as? VUI.Font
                        XCTAssertNotNil(font, "image=\(size) scale=\(contentScale) factor=\(factor) index=\(index)")
                        if let font {
                            XCTAssertEqual(font.platformFont(in: environment.fontResolutionContext).pointSize,
                                points * factor, accuracy: 0.000001)
                        }
                    }
                    let glyphs = scaled.makeGlyphLayout(maxWidth: 500, maximumHeight: .infinity).lines.flatMap(\.glyphs)
                    let images = glyphs.filter { if case .attachment = $0.content { true } else { false } }
                    XCTAssertEqual(images.count, 1)
                    if let glyph = images.first, case let .attachment(image) = glyph.content {
                        XCTAssertTrue(image.texture as AnyObject? === texture as AnyObject)
                        XCTAssertEqual(glyph.advance, size * contentScale)
                        XCTAssertEqual(glyph.ascender, size.height * contentScale)
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
        let done = expectation(description: "Attachment fitting readback")
        commands.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [done], timeout: 15)
        let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(staging.contents()), count: Int(extent.width * extent.height) * 4))
    }

    private func graphicsDevice() throws -> GraphicsDeviceContext {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        return device
    }

    private func imageTexture(_ size: CGSize, device: GraphicsDeviceContext) throws -> Texture {
        let width = Int(size.width), height = Int(size.height)
        let bytes = Data((0..<(width * height)).flatMap { _ in [UInt8(0), 220, 0, 255] })
        let image = VVD.Image(width: width, height: height, pixelFormat: .rgba8, data: bytes)
        return try XCTUnwrap(image.makeTexture(commandQueue: XCTUnwrap(device.renderQueue())))
    }

    private func testFont(_ size: CGFloat) -> VUI.Font {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let font = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        return .file(font, size: size)
    }

    private func mixedText(_ texture: Texture?, factor: CGFloat = 1) -> Text {
        let first = Text(verbatim: "AAA ").font(testFont(23 * factor)).foregroundColor(.red)
        let last = Text(verbatim: "BBB BBB").font(testFont(31 * factor)).foregroundColor(.blue)
        if let texture {
            return first + Text(Image(decorative: texture, scale: 1)).font(testFont(23 * factor)) + last
        }
        return first + last
    }

    private func inputs(graph: _AGGraph, environment: EnvironmentValues) -> _ViewInputs {
        _ViewInputs(base: _GraphInputs(time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()), environment: graph.makeInput(value: environment),
            transaction: graph.makeInput(value: Transaction())), customInputs: PropertyList(),
            preferences: PreferencesInputs(keys: PreferenceKeys(), hostKeys: graph.makeInput(value: PreferenceKeys())),
            transform: graph.makeInput(value: ViewTransform()), position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero), size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(), containerSize: OptionalAttribute(), stackOrientation: nil)
    }
}

private struct AttachmentFittingRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout { context.draw(line) }
    }
}

// The fixture measures and draws synchronously on its test thread.
private final class AttachmentFittingCapture: @unchecked Sendable {
    var measures: [[CGFloat]] = []
    var lines: [[[CGFloat]]] = []
    var truncated: [Bool] = []
    func draw(_ layout: Text.Layout, in context: inout GraphicsContext) {
        lines.append(layout.map { line in
            let bounds = line.typographicBounds
            return [line.origin.x, line.origin.y, bounds.width, bounds.ascent, bounds.descent]
        })
        truncated.append(layout.isTruncated)
        for line in layout { context.draw(line) }
    }
}

private struct AttachmentFittingDefaultRenderer: TextRenderer {
    let capture: AttachmentFittingCapture
    func draw(layout: Text.Layout, in context: inout GraphicsContext) { capture.draw(layout, in: &context) }
}

private struct AttachmentFittingMeasuredRenderer: TextRenderer {
    let capture: AttachmentFittingCapture
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize { text.sizeThatFits(proposal) }
    func draw(layout: Text.Layout, in context: inout GraphicsContext) { capture.draw(layout, in: &context) }
}

private struct AttachmentFittingMeasure: Layout {
    let proposal: ProposedViewSize
    let capture: AttachmentFittingCapture
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
