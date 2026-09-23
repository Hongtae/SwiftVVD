import Foundation
import XCTest
import VVD
@testable import VUI

final class ResourceResolutionLifetimeTests: XCTestCase {
    // ASSERTIONS fontGraphicsSizeCopy27Observed
    func testSuppliedTextureSizeCopyReleasesOriginalFaceAndRetainsItsDevice() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let path = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf").path
        let resolution = EnvironmentValues().fontResolutionContext
        for memory in [false, true] {
            weak var original: TextureFont?
            weak var copied: TextureFont?
            weak var source: VVD.Font.Source?
            weak var device: GraphicsDeviceContext?
            var retained: FontResource?
            func populate() throws {
                let graphics = GraphicsDeviceContext(device: LifetimeTestDevice())
                device = graphics
                let backend = try XCTUnwrap(memory
                    ? TextureFont(deviceContext: graphics, data: Data(contentsOf: URL(fileURLWithPath: path)))
                    : TextureFont(deviceContext: graphics, path: path))
                original = backend
                source = backend.source
                backend.setPointSize(23.375, dpi: (96, 144))
                XCTAssertTrue(backend.setVariationCoordinates([0x77676874: 700, 0x77647468: 90]))
                backend.boldStrength = 0.75
                backend.outlineThickness = 0.5
                backend.isBitmapPreferred = true
                backend.isKerningEnabled = false
                backend.isColorEnabled = false
                let input = VUI.Font(backend).monospacedDigit()
                let resource = FontResource(descriptor: input.resolveDescriptor(in: resolution), in: resolution)
                retained = try XCTUnwrap(resource.fontWithSize(31.375))
                let face = try XCTUnwrap(retained?.provider.makeTypeface(LifetimeTestAppContext(graphics), dpi: 216) as? TextureTypeface)
                copied = face.textureFont
                XCTAssertFalse(face.textureFont === backend)
                XCTAssertTrue(face.textureFont.deviceContext === graphics)
                XCTAssertEqual(face.textureFont.pointSize, 31.375)
                XCTAssertEqual(face.textureFont.dpi.x, 96)
                XCTAssertEqual(face.textureFont.dpi.y, 144)
                XCTAssertEqual(face.textureFont.variationCoordinates, backend.variationCoordinates)
                XCTAssertEqual(face.textureFont.boldStrength, 0.75)
                XCTAssertEqual(face.textureFont.outlineThickness, 0.5)
                XCTAssertTrue(face.textureFont.isBitmapPreferred)
                XCTAssertFalse(face.textureFont.isKerningEnabled)
                XCTAssertFalse(face.textureFont.isColorEnabled)
                XCTAssertEqual(face.selectedFont?.variation, [0x77676874: 700, 0x77647468: 90])
                XCTAssertNil(face.selectedFont?.variationExtras)
                XCTAssertEqual(retained?.shapingFeatures, resource.shapingFeatures)
                let restored = try XCTUnwrap(retained?.fontWithSize(23.375))
                XCTAssertEqual(restored, resource)
                XCTAssertEqual(restored.hashValue, resource.hashValue)
                XCTAssertEqual(backend.pointSize, 23.375)
                XCTAssertNotNil(face.glyphMetrics(for: "A"))
            }
            try populate()
            XCTAssertNil(original)
            XCTAssertNotNil(copied)
            XCTAssertNotNil(source)
            XCTAssertNotNil(device)
            XCTAssertNotNil(retained?.fontWithSize(15.375))
            retained = nil
            XCTAssertNil(copied)
            XCTAssertNil(source)
            XCTAssertNil(device)
        }
    }

    // ASSERTIONS fontGraphicsSizeCopy27Observed fontStructureInputs27Observed fontPlatformInputs27Observed
    func testSuppliedTextureCacheIdentityKeepsRasterConfigurationSeparateFromSelection() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let path = root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"
        ).path
        let graphics = GraphicsDeviceContext(device: LifetimeTestDevice())
        let backend = try XCTUnwrap(TextureFont(deviceContext: graphics, path: path))
        backend.setPointSize(23.375, dpi: (96, 144))
        XCTAssertTrue(backend.setVariationCoordinates([0x7767_6874: 700, 0x7764_7468: 90]))

        func copy(_ update: (TextureFont) -> Void = { _ in }) throws -> TextureFont {
            let value = try XCTUnwrap(backend.copy() as? TextureFont)
            update(value)
            return value
        }
        func selected(_ font: VUI.Font) throws -> SelectedFont {
            let provider = try XCTUnwrap(font.typefaceProvider as? FixedFontProvider)
            return try XCTUnwrap(provider.face.selectedFont)
        }

        let original = VUI.Font(try copy())
        let equivalent = VUI.Font(try copy())
        let resolution = EnvironmentValues().fontResolutionContext
        XCTAssertEqual(original, equivalent)
        XCTAssertEqual(original.hashValue, equivalent.hashValue)
        XCTAssertEqual(original.platformFont(in: resolution), equivalent.platformFont(in: resolution))

        let controls: [(String, VUI.Font)] = [
            ("bold", VUI.Font(try copy { $0.boldStrength = 0.75 })),
            ("outline", VUI.Font(try copy { $0.outlineThickness = 0.5 })),
            ("dpi", VUI.Font(try copy { $0.dpi = (72, 72) })),
            ("bitmap", VUI.Font(try copy { $0.isBitmapPreferred = true })),
            ("kerning", VUI.Font(try copy { $0.isKerningEnabled = false })),
            ("color", VUI.Font(try copy { $0.isColorEnabled = false }))
        ]
        let originalSelection = try selected(original)
        for (label, value) in controls {
            XCTAssertTrue(originalSelection.isEqual(to: try selected(value)), label)
            XCTAssertNotEqual(original, value, label)
            XCTAssertNotEqual(original.platformFont(in: resolution), value.platformFont(in: resolution), label)
        }
    }

    // ASSERTIONS fontGraphicsSource27Observed fontVariationSelection27Observed
    func testSuppliedTextureFontRetainsVariationAndDeviceWithoutDescriptorExtras() throws {
        let context = GraphicsDeviceContext(device: LifetimeTestDevice())
        let app = LifetimeTestAppContext(context)
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let path = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf").path
        let resolution = EnvironmentValues().fontResolutionContext
        let weight: UInt32 = 0x7767_6874, width: UInt32 = 0x7764_7468
        let controls: [([UInt32: CGFloat], [UInt32: CGFloat])] = [
            ([:], [:]),
            ([weight: 700], [weight: 700]),
            ([weight: 700, width: 90], [weight: 700, width: 90]),
            ([weight: 530.0014], [weight: 530.0013])
        ]
        for (request, comparison) in controls {
            let backend = try XCTUnwrap(TextureFont(deviceContext: context, path: path))
            XCTAssertTrue(backend.setVariationCoordinates(request))
            backend.setPointSize(23.375, dpi: (144, 144))
            let coordinates = backend.variationCoordinates
            let input = VUI.Font(backend)
            let resource = input.resolve(in: resolution).resource
            let wrapped = VUI.Font(provider: FontBox(VUI.Font.PlatformFontProvider(font: resource)))
            for font in [input, wrapped, input.monospacedDigit(), wrapped.monospacedDigit()] {
                let face = try XCTUnwrap(font.resolve(in: resolution).resource.provider.makeTypeface(app, dpi: 216) as? TextureTypeface)
                let selected = try XCTUnwrap(face.selectedFont)
                XCTAssertEqual(selected.variation, comparison)
                XCTAssertNil(selected.variationExtras)
                XCTAssertEqual(selected.pointSize, 23.375)
                guard case let .supplied(owner) = selected.descriptor.source else {
                    return XCTFail("A supplied texture font lost its resource identity")
                }
                XCTAssertTrue(owner === backend.source)
                XCTAssertTrue(face.textureFont === backend)
                XCTAssertTrue(face.textureFont.deviceContext === context)
            }
            XCTAssertEqual(backend.variationCoordinates, coordinates)
            XCTAssertEqual(backend.dpi.x, 144)
            XCTAssertEqual(backend.dpi.y, 144)
        }
    }

    // ASSERTIONS fontGraphicsConstruction27Observed
    func testSuppliedTextureFontPreservesPointSizeAndRetainedDevice() throws {
        let context = GraphicsDeviceContext(device: LifetimeTestDevice())
        let app = LifetimeTestAppContext(context)
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let path = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf").path
        let resolution = EnvironmentValues().fontResolutionContext
        for dpi: UInt32 in [72, 144] {
            for size: CGFloat in [23, 23.375] {
                let backend = try XCTUnwrap(TextureFont(deviceContext: context, path: path))
                backend.setPointSize(size, dpi: (dpi, dpi))
                let height = backend.height
                XCTAssertNotEqual(height, size)
                let input = VUI.Font(backend)
                let resource = input.resolve(in: resolution).resource
                let wrapped = VUI.Font(provider: FontBox(VUI.Font.PlatformFontProvider(font: resource)))
                for font in [input, wrapped, input.monospacedDigit(), wrapped.monospacedDigit()] {
                    XCTAssertEqual(font.resolve(in: resolution).pointSize, size)
                    let face = try XCTUnwrap(font.resolve(in: resolution).resource.provider.makeTypeface(app, dpi: 216) as? TextureTypeface)
                    XCTAssertTrue(face.textureFont === backend)
                    XCTAssertTrue(face.textureFont.deviceContext === context)
                    XCTAssertEqual(face.lineHeight, height)
                    XCTAssertEqual(face.selectedFont?.pointSize, size)
                    XCTAssertEqual(face.textureFont.dpi.x, dpi)
                    XCTAssertEqual(face.textureFont.dpi.y, dpi)
                }
                XCTAssertEqual(backend.pointSize, size)
                XCTAssertEqual(backend.height, height)
            }
        }
    }

    // ASSERTIONS textResolvedFontsIdentityAndMetricsObserved
    func testRetainedFontCollectionsReleaseFixedDeviceResourcesOnTerminationOrLastValue() throws {
        for ownerType: ResolvedStyledText.Type in [ResolvedStyledText.StringDrawing.self, ResolvedStyledText.TextLayoutManager.self] {
            for terminates in [false, true] {
                var owner: ResolvedStyledText?
                var retainedFonts: Text.ResolvedProperties.Fonts?
                weak var artwork: TextureFont?
                weak var deviceContext: GraphicsDeviceContext?
                weak var resourceReference: FontResource?
                func populate() throws {
                    let context = GraphicsDeviceContext(device: LifetimeTestDevice())
                    var root = URL(fileURLWithPath: #filePath)
                    for _ in 0..<5 { root.deleteLastPathComponent() }
                    let font = try XCTUnwrap(TextureFont(deviceContext: context, path: root.appendingPathComponent(
                        "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf").path))
                    artwork = font
                    deviceContext = context
                    let face = TextureTypeface(textureFont: font)
                    let resource = FontResource(descriptor: FontDescriptor(source: .typeface(FixedFontProvider(face, pointSize: 23)), pointSize: 23),
                        in: EnvironmentValues().fontResolutionContext)
                    resourceReference = resource
                    var attributes = _ResolvedTextRunAttributes()
                    attributes.fontResource = resource
                    attributes.font = VUI.Font(provider: FontBox(Font.PlatformFontProvider(font: resource)))
                    var source = ResolvedTextSource(runs: [.styledText([face], "A", .init(), attributes)], scaleFactor: 1)
                    var properties = Text.ResolvedProperties()
                    properties.fonts.storage.insert(resource)
                    source.resolvedProperties = properties
                    owner = ownerType.init(storage: source.attributedStorage, resolvedText: source)
                    retainedFonts = owner?.fonts
                }
#if canImport(ObjectiveC)
                try autoreleasepool(invoking: populate)
#else
                try populate()
#endif
                XCTAssertNotNil(artwork)
                owner?.purgeResources(reason: .lowMemory)
                XCTAssertNotNil(artwork)
                if terminates {
                    owner?.purgeResources(reason: .appTermination)
                    withExtendedLifetime((owner, retainedFonts)) {
                        XCTAssertNil(resourceReference)
                        XCTAssertNil(artwork)
                        XCTAssertNil(deviceContext)
                    }
                } else {
                    owner = nil
                    withExtendedLifetime(retainedFonts) { XCTAssertNotNil(artwork) }
                    retainedFonts = nil
                    XCTAssertNil(resourceReference)
                    XCTAssertNil(artwork)
                    XCTAssertNil(deviceContext)
                }
            }
        }
    }

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
#if canImport(ObjectiveC)
        try autoreleasepool(invoking: populate)
#else
        try populate()
#endif
        withExtendedLifetime(owner) {
            XCTAssertNotNil(artwork)
            XCTAssertNotNil(deviceContext)
        }
        owner = nil
        XCTAssertNil(artwork)
        XCTAssertNil(deviceContext)
    }

    // ASSERTIONS textSuffixRetainedMetricsLayoutObserved
    // ASSERTIONS textSuffixDrawingConsumersObserved
    func testRetainedSuffixDrawingReleasesFontsAfterPurgeAndLastValueRelease() throws {
        var drawing: ResolvedTextSource.Drawing?
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
            let source = ResolvedTextSource(runs: [.text([TextureTypeface(textureFont: font)], "A\nB")], scaleFactor: 1)
            let suffix = try XCTUnwrap(source.makeLayout(in: CGSize(width: 100, height: 100),
                layoutDirection: .leftToRight).first)
            var properties = TextLayoutProperties()
            properties.lineLimit = 1
            let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: properties,
                suffix: .truncated(suffix, []), resolvedText: source)
            let prepared = try XCTUnwrap(manager.prepareDrawing(in: .zero,
                with: CGSize(width: 100, height: 100), applyingMarginOffsets: false))
            XCTAssertNotNil(prepared.layout)
            drawing = source.makeDrawing(lineGlyphs: prepared.lines, layout: prepared.layout)
            manager.glyphLayoutCache.purgeResources(reason: .appTermination)
        }
        try populate()
        withExtendedLifetime(drawing) {
            XCTAssertNotNil(artwork)
            XCTAssertNotNil(deviceContext)
        }
        drawing = nil
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

    func testPreparedBackendTextUsesTheSameResourceVersionOnPublicationAndReuse() throws {
        #if canImport(Metal)
        let device = try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let host = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: host)
        host.storage = viewGraph
        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            var renders = 0
            let image = VUI.Image(size: CGSize(width: 8, height: 8)) { context in
                renders += 1
                context.fill(Path(CGRect(x: 0, y: 0, width: 8, height: 8)), with: .color(.red))
            }
            let inputs = makeInputs(graph)
            let text = Text(verbatim: "A") + Text(image)
            let outputs = Text._makeView(view: _GraphValue(_attribute: graph.makeInput(value: text)), inputs: inputs)
            let resources = Attribute<ResourceList>(try XCTUnwrap(outputs.preferences.value(for: ResourceList.Key.self)))
            let commands = try XCTUnwrap(device.renderQueue()?.makeCommandBuffer())
            let environment = inputs.base.cachedEnvironment.value.environment
            let context = try XCTUnwrap(GraphicsContext(sceneResources: host.sceneResources, environment: environment.value,
                viewport: CGRect(x: 0, y: 0, width: 200, height: 100), contentOffset: .zero,
                contentScaleFactor: 1, resolution: CGSize(width: 200, height: 100), commandBuffer: commands))
            try XCTUnwrap(resources.value.items.first)(context)
            XCTAssertEqual(renders, 1)
            XCTAssertTrue(resources.value.items.isEmpty)
            var changed = environment.value
            changed.foregroundStyleLevels = .init(primary: AnyShapeStyle(VUI.Color.green))
            environment.value = changed
            try XCTUnwrap(resources.value.items.first)(context)
            XCTAssertEqual(renders, 2)
            XCTAssertTrue(resources.value.items.isEmpty)
            XCTAssertTrue(commands.commit())
        }
        #else
        throw XCTSkip("Metal is required for generated text attachments")
        #endif
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
    let features: GraphicsDeviceFeatures = []
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
