import Foundation
import XCTest
import VVD
@testable import VUI

final class ResourceResolutionLifetimeTests: XCTestCase {
    private final class Witness {
        weak var host: TestViewRendererHost?
        weak var viewGraph: ViewGraph?
        weak var graph: _AGGraph?
        weak var drawing: ResolvedStyledText.StringDrawing?
        weak var artwork: TextureFont?
        weak var deviceContext: GraphicsDeviceContext?
    }

    func testTextResourceRuleReleasesGraphAndPreparedBitmapFontsWithHost() throws {
        let witness = Witness()
        func populate() throws {
            let previousContext = appContext
            defer { appContext = previousContext }
            let context = GraphicsDeviceContext(device: LifetimeTestDevice())
            appContext = LifetimeTestAppContext(context)
            witness.deviceContext = context
            let host = TestViewRendererHost()
            let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: host)
            host.storage = viewGraph
            witness.host = host
            witness.viewGraph = viewGraph
            witness.graph = viewGraph.data.graph
            try viewGraph.data.withCurrent {
                let graph = viewGraph.data.graph
                let outputs = Text._makeView(
                    view: _GraphValue(_attribute: graph.makeInput(value: Text(verbatim: "ABC"))),
                    inputs: makeInputs(graph))
                let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
                let engine = try XCTUnwrap(computer.box as? LayoutEngineBox<StyledTextLayoutEngine>).engine
                let drawing = try XCTUnwrap(engine.text as? ResolvedStyledText.StringDrawing)
                witness.drawing = drawing
                XCTAssertGreaterThan(engine.sizeThatFits(.init(width: 200, height: 100)).width, 0)
                let prepared = try XCTUnwrap(drawing.preparedLayout)
                let face = try XCTUnwrap(prepared.lines.flatMap(\.glyphs).compactMap {
                    $0.face as? TextureTypeface
                }.first)
                witness.artwork = face.textureFont
                XCTAssertTrue(face.textureFont.deviceContext === context)
            }
        }
        try populate()
        XCTAssertNil(witness.host)
        XCTAssertNil(witness.viewGraph)
        XCTAssertNil(witness.graph)
        XCTAssertNil(witness.drawing)
        XCTAssertNil(witness.artwork)
        XCTAssertNil(witness.deviceContext)
    }

    func testManagerBackendCachePurgeReleasesItsLastTextureFontAndDevice() throws {
        try checkManagerBackendPurge(retainsScaledSource: false)
    }

    func testRetainedLayoutLineReleasesItsFontAndDeviceWithTheLastValue() throws {
        var layout: Text.Layout?
        var line: Text.Layout.Line?
        weak var artwork: TextureFont?
        weak var deviceContext: GraphicsDeviceContext?
        func populate() throws {
            let context = GraphicsDeviceContext(device: LifetimeTestDevice())
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let font = try XCTUnwrap(TextureFont(deviceContext: context, path: root.appendingPathComponent(
                "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf").path))
            artwork = font
            deviceContext = context
            let face = TextureTypeface(textureFont: font)
            let source = ResolvedTextSource(runs: [.text([face], "A")], scaleFactor: 1)
            layout = source.makeLayout(in: CGSize(width: 100, height: 100), layoutDirection: .leftToRight)
        }
        try populate()
        line = try XCTUnwrap(layout?.first)
        layout = nil
        withExtendedLifetime(line) {
            XCTAssertNotNil(artwork)
            XCTAssertNotNil(deviceContext)
        }
        line = nil
        XCTAssertNil(artwork)
        XCTAssertNil(deviceContext)
    }

    func testSuffixAttachmentReleasesItsLineFontAndDeviceWithTheLastOwner() throws {
        var owner: ResolvedStyledText.TextLayoutManager?
        weak var artwork: TextureFont?
        weak var deviceContext: GraphicsDeviceContext?
        func populate() throws {
            let context = GraphicsDeviceContext(device: LifetimeTestDevice())
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let font = try XCTUnwrap(TextureFont(deviceContext: context, path: root.appendingPathComponent(
                "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf").path))
            artwork = font
            deviceContext = context
            let source = ResolvedTextSource(runs: [.text([TextureTypeface(textureFont: font)], "A")], scaleFactor: 1)
            let line = try XCTUnwrap(source.makeLayout(in: CGSize(width: 100, height: 100),
                layoutDirection: .leftToRight).first)
            let attachment = ConcreteCustomTextAttachment(LineAttachment(line: line, bounds: line.typographicBounds))
            owner = ResolvedStyledText.TextLayoutManager(storage: attachment.nsAttributedString(with: [:]),
                suffix: .alwaysVisible(line, []), attachments: .init(characterIndices: [0]))
        }
        try populate()
        withExtendedLifetime(owner) {
            XCTAssertNotNil(artwork)
            XCTAssertNotNil(deviceContext)
        }
        owner = nil
        XCTAssertNil(artwork)
        XCTAssertNil(deviceContext)
    }

    // ASSERTIONS textManagerScaledStorageLifecycleObserved
    func testManagerScaledSourcePurgeReleasesItsLastTextureFontAndDevice() throws {
        try checkManagerBackendPurge(retainsScaledSource: true)
    }

    private func checkManagerBackendPurge(retainsScaledSource: Bool) throws {
        for reason: ResourcePurgeReason in [.lowMemory, .appTermination] {
            let cache = ResolvedStyledText.TextLayoutManager.GlyphLayoutCache()
            weak var textureFont: TextureFont?
            weak var deviceContext: GraphicsDeviceContext?
            weak var device: LifetimeTestDevice?
            func populate() throws {
                let graphics = LifetimeTestDevice()
                let context = GraphicsDeviceContext(device: graphics)
                var root = URL(fileURLWithPath: #filePath)
                for _ in 0..<5 { root.deleteLastPathComponent() }
                let font = try XCTUnwrap(TextureFont(deviceContext: context, path: root.appendingPathComponent(
                    "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf").path))
                textureFont = font
                deviceContext = context
                device = graphics
                let face = TextureTypeface(textureFont: font)
                if retainsScaledSource {
                    let source = ResolvedTextSource(runs: [.text([face], "A")], scaleFactor: 1)
                    _ = cache.source(at: 0.5, original: source)
                    _ = cache.source(at: 1, original: source)
                } else {
                    let glyph = ResolvedTextSource.Glyph(scalar: "A", face: face)
                    _ = cache.layout(in: CGSize(width: 80, height: 120), lineLimit: nil, truncationMode: .tail) {
                        .init(lines: [.init(glyphs: [glyph], ascender: 10, descender: -3, width: 8)],
                              lineCount: 1, forcedClusterBreak: false, truncatedRanges: [], hasUnlaidText: false)
                    }
                }
            }
            try populate()
            XCTAssertNotNil(textureFont)
            XCTAssertNotNil(deviceContext)
            XCTAssertNotNil(device)
            cache.purgeResources(reason: reason)
            withExtendedLifetime(cache) {
                XCTAssertNil(textureFont)
                XCTAssertNil(deviceContext)
                XCTAssertNil(device)
            }
        }
    }

    func testPendingBackendResourceTaskDoesNotRetainItsGraph() throws {
        let witness = Witness()
        func capture() throws -> ResourceList.Task {
            let host = TestViewRendererHost()
            let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: host)
            host.storage = viewGraph
            witness.host = host
            witness.viewGraph = viewGraph
            witness.graph = viewGraph.data.graph
            return try viewGraph.data.withCurrent {
                let graph = viewGraph.data.graph
                let text = Text(VUI.Image("missing-lifetime-test-image"))
                let inputs = makeInputs(graph)
                XCTAssertTrue(text._requiresBackendResolution(in: inputs.base.cachedEnvironment.value.environment.value))
                let outputs = Text._makeView(
                    view: _GraphValue(_attribute: graph.makeInput(value: text)), inputs: inputs)
                let resourceID = try XCTUnwrap(outputs.preferences.value(for: ResourceList.Key.self))
                return try XCTUnwrap(Attribute<ResourceList>(resourceID).value.items.first)
            }
        }
        let pending = try capture()
        withExtendedLifetime(pending) {
            XCTAssertNil(witness.host)
            XCTAssertNil(witness.viewGraph)
            XCTAssertNil(witness.graph)
        }
    }

    func testVectorImageResourceRuleDoesNotRetainItsGraph() throws {
        let witness = Witness()
        XCTAssertNil(try captureImage(VUI.Image(systemName: "settings"), witness: witness))
        XCTAssertNil(witness.host)
        XCTAssertNil(witness.viewGraph)
        XCTAssertNil(witness.graph)
    }

    func testPendingImageResourceTaskDoesNotRetainItsGraph() throws {
        let witness = Witness()
        let pending = try XCTUnwrap(captureImage(VUI.Image("missing-lifetime-test-image"), witness: witness))
        withExtendedLifetime(pending) {
            XCTAssertNil(witness.host)
            XCTAssertNil(witness.viewGraph)
            XCTAssertNil(witness.graph)
        }
    }

    func testOpacityDisplayListRuleDoesNotRetainItsGraph() throws {
        weak var graphReference: _AGGraph?
        func populate() throws {
            let graph = _AGGraph()
            graphReference = graph
            try _AGGraph.withCurrent(graph) {
                var child = _ViewOutputs()
                child.preferences.append(DisplayList.Key.self,
                    node: graph.makeInput(value: DisplayList()).identifier)
                let outputs = _OpacityEffect._makeView(
                    modifier: _GraphValue(_attribute: graph.makeInput(value: _OpacityEffect(opacity: 0.5))),
                    inputs: makeInputs(graph)
                ) { _, _ in child }
                let node = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
                XCTAssertTrue(Attribute<DisplayList>(node).value.items.isEmpty)
            }
        }
        try populate()
        XCTAssertNil(graphReference)
    }

    private func captureImage(_ image: VUI.Image, witness: Witness) throws -> ResourceList.Task? {
        let host = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: host)
        host.storage = viewGraph
        witness.host = host
        witness.viewGraph = viewGraph
        witness.graph = viewGraph.data.graph
        return try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let outputs = VUI.Image._makeView(
                view: _GraphValue(_attribute: graph.makeInput(value: image)), inputs: makeInputs(graph))
            let resourceID = try XCTUnwrap(outputs.preferences.value(for: ResourceList.Key.self))
            return Attribute<ResourceList>(resourceID).value.items.first
        }
    }

    private func makeInputs(_ graph: _AGGraph) -> _ViewInputs {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        var environment = EnvironmentValues()
        environment.font = .file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 13)
        environment.defaultFontRenderingMode = .bitmap()
        return _ViewInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(value: environment),
                transaction: graph.makeInput(value: Transaction())
            ),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(keys: PreferenceKeys(), hostKeys: graph.makeInput(value: PreferenceKeys())),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(width: 200, height: 100)),
            safeAreaInsets: OptionalAttribute(), containerSize: OptionalAttribute(), stackOrientation: nil
        )
    }
}

private final class LifetimeTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext?
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    init(_ context: GraphicsDeviceContext) { graphicsDeviceContext = context }
    func resourceData(forURL: URL) -> (any DataProtocol)? { nil }
    func setResource(data: (any DataProtocol)?, forURL: URL) {}
}

private final class LifetimeTestDevice: GraphicsDevice {
    let name = "Text resource lifetime test"
    func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue? { nil }
    func makeShaderModule(from: VVD.Shader) -> ShaderModule? { nil }
    func makeShaderBindingSet(layout: ShaderBindingSetLayout) -> ShaderBindingSet? { nil }
    func makeRenderPipelineState(descriptor: RenderPipelineDescriptor,
        reflection: UnsafeMutablePointer<PipelineReflection>?) -> RenderPipelineState? { nil }
    func makeComputePipelineState(descriptor: ComputePipelineDescriptor,
        reflection: UnsafeMutablePointer<PipelineReflection>?) -> ComputePipelineState? { nil }
    func makeDepthStencilState(descriptor: DepthStencilDescriptor) -> DepthStencilState? { nil }
    func makeBuffer(length: Int, storageMode: StorageMode, cpuCacheMode: CPUCacheMode) -> GPUBuffer? { nil }
    func makeTexture(descriptor: TextureDescriptor) -> Texture? { nil }
    func makeTransientRenderTarget(type: TextureType, pixelFormat: PixelFormat,
        width: Int, height: Int, depth: Int, sampleCount: Int) -> Texture? { nil }
    func makeSamplerState(descriptor: SamplerDescriptor) -> SamplerState? { nil }
    func makeEvent() -> GPUEvent? { nil }
    func makeSemaphore() -> GPUSemaphore? { nil }
}
