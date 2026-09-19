import Foundation
import XCTest
import VVD
@testable import VUI

final class TextForegroundStyleTests: XCTestCase {
    private let size = CGSize(width: 128, height: 80)
    private var gradient: LinearGradient {
        LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
    }

    func testInlineFactoryCopiesInheritedStyleAndKeepsValueEquality() throws {
        // ASSERTIONS textInlineStyleProducer27Observed
        let colored: Text = Text(verbatim: "A").foregroundStyle(.red)
        guard case .color(.some(.red)) = colored.modifiers.last else { return XCTFail() }
        let sharedGradient = gradient
        let first: Text = Text(verbatim: "A").foregroundStyle(sharedGradient)
        XCTAssertEqual(first, Text(verbatim: "A").foregroundStyle(sharedGradient))
        XCTAssertNotEqual(first, Text(verbatim: "A").foregroundStyle(gradient))
        XCTAssertNotEqual(first, Text(verbatim: "A").foregroundStyle(gradient.opacity(0.5)))
        guard case let .anyTextModifier(modifier) = first.modifiers.last else { return XCTFail() }
        XCTAssertTrue(modifier is TextForegroundStyleModifier)

        var style = Text.Style()
        style.color = .explicit(AnyShapeStyle(Color.red))
        var environment = EnvironmentValues()
        environment.foregroundStyleLevels = .init(primary: AnyShapeStyle(Color.blue))
        TextForegroundStyleModifier(AnyShapeStyle.opacity(0.4)).modify(style: &style, environment: environment)
        var properties = Text.ResolvedProperties()
        let color = try XCTUnwrap(style.color.resolve(in: environment, with: .allowsKeyColors,
            properties: &properties, includeDefaultAttributes: true))
        var expected = Color.red.resolveHDR(in: environment)
        expected.opacity *= 0.4
        XCTAssertEqual(color, expected)
        XCTAssertTrue(properties.styles.isEmpty)
    }

    func testPaletteFoldsColorsAndDeduplicatesAllStyleFields() throws {
        // ASSERTIONS textIndexedStyleAllocationObserved
        var properties = Text.ResolvedProperties()
        let hdr = VUI.Color.ResolvedHDR(.init(colorSpace: .sRGBLinear,
            red: 0.8, green: 0.2, blue: 0.1, opacity: 0.5), headroom: 2)
        var color = _ShapeStyle_Pack.Style(.color(hdr))
        color.opacity = 0.25
        color._blend = .normal
        var expected = hdr
        expected.opacity = 0.125
        XCTAssertEqual(properties.addCustomStyle(color), expected)
        XCTAssertTrue(properties.styles.isEmpty)
        XCTAssertFalse(properties.features.contains(.keyColor))

        let base = try resolvedStyle(gradient)
        var opacity = base
        opacity.opacity = 0.5
        var normal = base
        normal._blend = .normal
        let shadow = try resolvedStyle(gradient.shadow(.drop(radius: 2)))
        let variants = [base, opacity, normal, shadow]
        for (index, style) in variants.enumerated() {
            let key = properties.addCustomStyle(style)
            XCTAssertEqual(key.linearRed, -1)
            XCTAssertEqual(key.linearGreen, -1)
            XCTAssertEqual(key.linearBlue, Float(index) / 1024)
            XCTAssertEqual(key.opacity, 1)
            XCTAssertNil(key.headroom)
            XCTAssertEqual(properties.addCustomStyle(style), key)
        }
        XCTAssertEqual(properties.styles, variants)
        XCTAssertTrue(properties.features.contains(.keyColor))
    }

    func testPreparationKeepsOriginalTextAndForegroundKeySeparateFromInlinePalette() throws {
        // ASSERTIONS textForegroundPreparation27Observed
        // ASSERTIONS textIndexedStyleAllocationObserved
        try withDevice { _ in
            let host = ForegroundTextHost(Text("fixture"))
            try host.graph.data.withCurrent {
                var environment = EnvironmentValues()
                environment.foregroundStyleLevels = .init(primary: AnyShapeStyle(gradient.shadow(.drop(radius: 1))))
                let text = Text("A") + Text("B").foregroundStyle(gradient) + Text("C").foregroundColor(.green)
                var helper = ResolvedTextHelper(includeDefaultAttributes: true, allowsKeyColors: true)
                let owner = try XCTUnwrap(helper.resolve(text, with: environment, sizeFitting: false))
                XCTAssertEqual(helper.lastText, text)
                XCTAssertEqual(owner.styles, [try resolvedStyle(gradient)])
                XCTAssertTrue(owner.needsStyledRendering)
                let colors = try XCTUnwrap(owner.resolvedText).runs.compactMap { run -> VUI.Color.ResolvedHDR? in
                    if case let .styledText(_, _, _, attributes) = run {
                        return attributes.foregroundColor?.resolveHDR(in: environment)
                    }
                    return nil
                }
                XCTAssertEqual(colors.map(\.linearBlue).prefix(2), [-1, 0])
                XCTAssertEqual(colors.last, Color.green.resolveHDR(in: environment))
                let layers = owner.layers(for: size, renderer: nil, deviceScale: 1,
                    environment: environment, inputs: drawingInputs(host))
                XCTAssertNotNil(layers.foreground)
                XCTAssertEqual(layers.keyed.map(\.index), [0])
                XCTAssertNotNil(layers.unstyled)
                XCTAssertLessThan(try XCTUnwrap(layers.foreground).boundingRect.maxX,
                    try XCTUnwrap(layers.unstyled).boundingRect.maxX)
            }
        }
    }

    func testSuffixPaletteIsImportedBeforeBodyAndUnusedEntriesDoNotProduceLayers() throws {
        // ASSERTIONS textSuffixPaletteReuseObserved
        // ASSERTIONS textKeyedLayerSelectionObserved
        try withDevice { _ in
            let host = ForegroundTextHost(Text("fixture"))
            try host.graph.data.withCurrent {
                var helper = ResolvedTextHelper(includeDefaultAttributes: true, allowsKeyColors: true,
                    features: .produceTextLayout)
                var environment = EnvironmentValues()
                let suffix = try XCTUnwrap(helper.resolve(Text(" more").foregroundStyle(gradient),
                    with: environment, sizeFitting: false))
                environment[TextSuffixKey.self] = Text.Suffix.truncated(Text(" more")).resolve(text: suffix)
                helper.features = [.useTextSuffix, .produceTextLayout]
                let repeated = try XCTUnwrap(helper.resolve(Text(verbatim: "A").foregroundStyle(gradient),
                    with: environment, sizeFitting: false))
                XCTAssertEqual(repeated.styles, suffix.styles)
                let repeatedLayers = repeated.layers(for: size, renderer: nil, deviceScale: 1,
                    environment: environment, inputs: drawingInputs(host))
                XCTAssertEqual(repeatedLayers.keyed.map(\.index), [0])
                let different = try XCTUnwrap(helper.resolve(Text(verbatim: "A").foregroundStyle(gradient.opacity(0.5)),
                    with: environment, sizeFitting: false))
                XCTAssertEqual(different.styles.count, 2)
                XCTAssertEqual(different.styles.first, suffix.styles.first)
                let layers = different.layers(for: size, renderer: nil, deviceScale: 1,
                    environment: environment, inputs: drawingInputs(host))
                XCTAssertEqual(layers.keyed.map(\.index), [1])
            }
        }
    }

    func testMountedForegroundStylePartitionsInheritedAndExplicitRuns() throws {
        // ASSERTIONS textForegroundPreparation27Observed
        // ASSERTIONS textKeyedLayerSelectionObserved
        try withDevice { device in
            let content = AnyView(Text("A") + Text("B").foregroundColor(.green))
                .foregroundStyle(gradient).font(.system(size: 24))
            let host = ForegroundTextHost(content)
            let list = try host.list()
            let drawings = drawingContents(in: list)
            XCTAssertEqual(drawings.filter { !$0.1.alphaOnly }.count, 1)
            XCTAssertEqual(drawings.filter { $0.1.alphaOnly }.count, 1)
            let pixels = try pixels(list, device: device, resources: host.rendererHost.sceneResources)
            let opaque = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0 + 3] > 100 }
            XCTAssertTrue(opaque.contains { pixels[$0 + 1] > pixels[$0] && pixels[$0 + 1] > pixels[$0 + 2] })
            XCTAssertTrue(opaque.contains { pixels[$0] > pixels[$0 + 1] || pixels[$0 + 2] > pixels[$0 + 1] })
        }
    }

    func testAlphaOnlyReplayIgnoresRecordedRGBAndPreservesCoverage() throws {
        try withDevice { device in
            let host = ForegroundTextHost(Text("fixture"))
            func list(_ color: VUI.Color) -> DisplayList {
                let context = GraphicsContext(recording: RBDisplayList(viewport: CGRect(origin: .zero, size: size)),
                    environment: .init(), inputs: drawingInputs(host))
                let bounds = CGRect(x: 10, y: 12, width: 20, height: 18)
                context.fill(Path(bounds), with: .color(color.opacity(0.5)))
                let contents = context.recording!.moveContents()
                var list = DisplayList()
                list.items = [DisplayList.Item(content: DisplayList.Content(drawing: contents, origin: .zero,
                    options: .init(flags: [.defaultFlags, .alphaOnly])), frame: bounds,
                    identity: .none, version: .init())]
                return list
            }
            let expected = try pixels(list(.white), device: device, resources: host.rendererHost.sceneResources)
            XCTAssertGreaterThan(expected[(16 * 128 + 16) * 4 + 3], 100)
            for color: VUI.Color in [.black, .red, .blue] {
                XCTAssertEqual(try pixels(list(color), device: device, resources: host.rendererHost.sceneResources), expected)
            }
        }
    }

    func testKeyedMaskKeepsTextPlacementAndFillInBothDrawingModes() throws {
        // ASSERTIONS textKeyedLayerSelectionObserved
        try withDevice { device in
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                let text = Text("Abg").font(.system(size: 22)).italic().underline()
                let direct = ForegroundTextHost(text.foregroundColor(.blue)
                    .environment(\.defaultFontRenderingMode, mode)
                    .frame(width: 128, height: 80, alignment: .bottomTrailing))
                let keyed = ForegroundTextHost(text.foregroundStyle(Color.blue.shadow(.drop(color: .clear, radius: 0)))
                    .environment(\.defaultFontRenderingMode, mode)
                    .frame(width: 128, height: 80, alignment: .bottomTrailing))
                let expected = try pixels(direct.list(), device: device, resources: direct.rendererHost.sceneResources)
                let actual = try pixels(keyed.list(), device: device, resources: keyed.rendererHost.sceneResources)
                // Offscreen color multiplication can round an RGB channel by one byte.
                XCTAssertEqual(stride(from: 3, to: actual.count, by: 4).map { actual[$0] },
                    stride(from: 3, to: expected.count, by: 4).map { expected[$0] })
                XCTAssertLessThanOrEqual(zip(actual, expected).map { abs(Int($0) - Int($1)) }.max()!, 1)
            }
        }
    }

    func testCustomRendererRecordsOnceAndStyleLayersUseReversePaletteOrder() throws {
        // ASSERTIONS textKeyedLayerSelectionObserved
        // ASSERTIONS textMixedRecordingPartitionObserved
        try withDevice { device in
            let host = ForegroundTextHost(Text("fixture"))
            try host.graph.data.withCurrent {
                var environment = EnvironmentValues()
                environment.foregroundStyleLevels = .init(primary: AnyShapeStyle(Color.red.shadow(.drop(radius: 0))))
                let text = Text("A") + Text("B").foregroundStyle(gradient) +
                    Text("C").foregroundStyle(gradient.opacity(0.5)) + Text("D").foregroundColor(.green)
                var helper = ResolvedTextHelper(includeDefaultAttributes: true, allowsKeyColors: true,
                    features: [.customRenderer, .produceTextLayout])
                let owner = try XCTUnwrap(helper.resolve(text, with: environment, sizeFitting: false))
                let renderer = ForegroundRecordingRenderer(values: environment)
                let group = _ShapeStyle_InterpolatorGroup()
                var layers = _ShapeStyle_RenderedLayers(group: group)
                var shape = _ShapeStyle_RenderedShape(shape: .text(.init(text: owner, renderer: renderer)),
                    contentSeed: .init(), frame: CGRect(origin: .zero, size: size), options: [],
                    environment: host.graph.data.graph.makeInput(value: environment))
                let outer = try resolvedStyle(Color.red.shadow(.drop(radius: 0)))
                shape.renderItem(name: .foreground,
                    styles: .init(styles: [(.init(.foreground, 0), outer)]), layers: &layers)
                let list = layers.commit(shape: &shape)
                XCTAssertEqual(renderer.draws, 1)
                XCTAssertEqual(group.layers.map(\.id), [.unstyled, .customStyle(1), .customStyle(0), .styled(.foreground, 0)])
                XCTAssertEqual(group.layers[1].style, owner.styles[1])
                XCTAssertEqual(group.layers[2].style, owner.styles[0])
                _ = try pixels(list, device: device, resources: host.rendererHost.sceneResources)
                _ = try pixels(list, device: device, resources: host.rendererHost.sceneResources)
                XCTAssertEqual(renderer.draws, 1)
                guard case .alphaMask = shape.shape else { return XCTFail("The final mask belongs to trailing retirement") }

                let plain = try XCTUnwrap(helper.resolve(Text("plain").foregroundColor(.green),
                    with: environment, sizeFitting: false))
                var replacement = _ShapeStyle_RenderedShape(shape: .text(.init(text: plain, renderer: nil)),
                    contentSeed: .init(), frame: CGRect(origin: .zero, size: size), options: [],
                    environment: host.graph.data.graph.makeInput(value: environment))
                var nextLayers = _ShapeStyle_RenderedLayers(group: group)
                replacement.renderItem(name: .foreground,
                    styles: .init(styles: [(.init(.foreground, 0), outer)]), layers: &nextLayers)
                _ = nextLayers.commit(shape: &replacement)
                XCTAssertFalse(group.layers[0].isRemoved)
                XCTAssertTrue(group.layers.dropFirst().allSatisfy(\.isRemoved))
                XCTAssertEqual(group.cursor, 0)
            }
        }
    }

    // ASSERTIONS textFontWidthHost27Observed
    // ASSERTIONS viewFontWidthEnvironment27Observed
    func testFontWidthReachesMountedBitmapAndVectorDrawingAtBothScales() throws {
        try withDevice { device in
            let font = VUI.Font.system(size: 23)
            let text = Text(verbatim: "Hg0123")
            let controls: [(AnyView, VUI.Font)] = [
                (AnyView(text.fontWidth(.condensed)), font.width(.condensed)),
                (AnyView(text.fontWidth(.condensed).fontWidth(.expanded)), font.width(.condensed)),
                (AnyView(text.fontWidth(nil).fontWidth(.condensed)), font),
                (AnyView(AnyView(text).fontWidth(.condensed).fontWidth(.expanded)), font.width(.condensed)),
                (AnyView(AnyView(text).fontWidth(nil).fontWidth(.expanded)), font),
                (AnyView(AnyView(text.fontWidth(nil)).fontWidth(.condensed)), font),
                (AnyView(AnyView(text).fontWidth(nil).fontWidth(.expanded).font(font.width(.condensed))), font.width(.condensed)),
                (AnyView(text.fontWidth(.standard).font(font.width(.condensed))), font)
            ]
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for (view, expectedFont) in controls {
                        let host = ForegroundTextHost(view.font(font)
                            .environment(\.defaultFontRenderingMode, mode), scale: scale)
                        let reference = ForegroundTextHost(text.font(expectedFont)
                            .environment(\.defaultFontRenderingMode, mode), scale: scale)
                        let actual = try pixels(host.list(), device: device, resources: host.rendererHost.sceneResources, scale: scale)
                        let expected = try pixels(reference.list(), device: device, resources: reference.rendererHost.sceneResources, scale: scale)
                        XCTAssertTrue(stride(from: 3, to: actual.count, by: 4).contains { actual[$0] > 0 })
                        XCTAssertEqual(actual, expected)
                    }
                }
            }
        }
    }

    // ASSERTIONS textFontWidthHost27Observed
    func testChangingViewWidthInvalidatesTheMountedTextResolution() throws {
        try withDevice { device in
            let text = Text(verbatim: "Hg0123")
            let font = VUI.Font.system(size: 23)
            func content(_ width: VUI.Font.Width?) -> some View {
                AnyView(text).fontWidth(width).fontWidth(.condensed).font(font)
                    .environment(\.defaultFontRenderingMode, .vector())
            }
            var environment = EnvironmentValues()
            environment.displayScale = 2
            let renderer = TestViewRendererHost()
            let graph = ViewGraph(replaceableContent: content(.condensed), rendererHost: renderer,
                initialEnvironment: environment)
            renderer.storage = graph
            graph.setSize(size)
            let values: [VUI.Font.Width?] = [.condensed, nil, .standard, .expanded, .condensed, nil]
            for (index, width) in values.enumerated() {
                try graph.data.withCurrent {
                    try XCTUnwrap(graph.rootAnyViewContentInput).setValue(AnyView(content(width)))
                }
                graph.updateOutputs(at: Time(seconds: Double(index)))
                let list = try graph.data.withCurrent { try XCTUnwrap(graph.displayList()) }
                let actual = try pixels(list, device: device, resources: renderer.sceneResources, scale: 2)
                let reference = ForegroundTextHost(text.font(font.width(width ?? .standard))
                    .environment(\.defaultFontRenderingMode, .vector()), scale: 2)
                let expected = try pixels(reference.list(), device: device, resources: reference.rendererHost.sceneResources, scale: 2)
                XCTAssertEqual(actual, expected)
            }
        }
    }

    private func resolvedStyle<S: ShapeStyle>(_ style: S) throws -> _ShapeStyle_Pack.Style {
        var shape = _ShapeStyle_Shape(operation: .resolveStyle(name: .foreground, levels: 0..<1), environment: .init())
        style._apply(to: &shape)
        guard case let .pack(pack) = shape.result else { throw XCTUnwrapError.missingStyle }
        return try XCTUnwrap(pack.styles.first?.style)
    }
    private enum XCTUnwrapError: Error { case missingStyle }

    private func withDevice(_ body: (GraphicsDeviceContext) throws -> Void) throws {
        #if canImport(Metal)
        let device = try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        try body(device)
        #else
        throw XCTSkip("Metal is required for this rendering fixture")
        #endif
    }

    private func drawingInputs(_ host: ForegroundTextHost) -> GraphicsContext.DrawingInputs {
        .init(sceneResources: host.rendererHost.sceneResources, viewport: CGRect(origin: .zero, size: size),
            contentScaleFactor: 1, resourceCommandQueue: nil)
    }

    private func pixels(_ list: DisplayList, device: GraphicsDeviceContext, resources: SceneResources, scale: CGFloat = 1) throws -> [UInt8] {
        let commands = try XCTUnwrap(device.renderQueue()?.makeCommandBuffer())
        let resolution = CGSize(width: size.width * scale, height: size.height * scale)
        var context = try XCTUnwrap(GraphicsContext(sceneResources: resources, environment: .init(),
            viewport: CGRect(origin: .zero, size: resolution), contentOffset: .zero, contentScaleFactor: scale,
            resolution: resolution, commandBuffer: commands))
        context.clear(with: .clear)
        list.draw(in: context)
        let done = expectation(description: "foreground readback")
        commands.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [done], timeout: 15)
        let buffer = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(buffer.contents()), count: Int(resolution.width * resolution.height) * 4))
    }

    private func drawingContents(in list: DisplayList) -> [(any RBDisplayListContents, RasterizationOptions)] {
        var result: [(any RBDisplayListContents, RasterizationOptions)] = []
        for item in list.items {
            switch item.value {
            case let .content(content):
                if case let .drawing(contents, _, options) = content.value { result.append((contents, options)) }
                if case let .flattened(child, _, _) = content.value { result += drawingContents(in: child) }
            case let .effect(effect, child):
                result += drawingContents(in: child)
                if case let .mask(mask, _) = effect { result += drawingContents(in: mask) }
            default: break
            }
        }
        return result
    }
}

private final class ForegroundRecordingRenderer: TextRendererBoxBase {
    let values: EnvironmentValues
    var draws = 0
    init(values: EnvironmentValues) { self.values = values }
    override var environment: EnvironmentValues { values }
    override var displayPadding: EdgeInsets { .init() }
    override func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize { text.sizeThatFits(proposal) }
    override func textLayoutBounds(size: CGSize, text: TextProxy) -> CGRect { CGRect(origin: .zero, size: size) }
    override func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        draws += 1
        for line in layout { context.draw(line) }
        context.fill(Path(CGRect(x: 3, y: 50, width: 6, height: 6)), with: .color(.green))
    }
}

private final class ForegroundTextHost {
    let rendererHost = TestViewRendererHost()
    let graph: ViewGraph
    init<V: View>(_ view: V, scale: CGFloat = 1) {
        var environment = EnvironmentValues()
        environment.displayScale = scale
        graph = ViewGraph(rootViewType: V.self, content: view, rendererHost: rendererHost, initialEnvironment: environment)
        rendererHost.storage = graph
        graph.setSize(CGSize(width: 128, height: 80))
    }
    func list() throws -> DisplayList {
        graph.updateOutputs(at: .zero)
        return try graph.data.withCurrent { try XCTUnwrap(graph.displayList()) }
    }
}
