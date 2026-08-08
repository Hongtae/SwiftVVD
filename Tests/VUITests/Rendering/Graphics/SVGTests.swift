import XCTest
import VVD
@testable import VUI

final class SVGTests: XCTestCase {
    func testDocumentParserPreservesLayerStylesAndInheritedPresentation() throws {
        let svg = try SVG(source: """
        <svg xmlns="http://www.w3.org/2000/svg"
             width="48px" height="24" viewBox="0 0 24 12">
          <g transform="translate(10 4)" opacity="0.5"
             fill="#000" stroke-width="2" stroke-linecap="round">
            <path d="M1 1 L2 1 L2 2 Z"
                  transform="scale(2)" opacity="0.5"
                  color="#ff0000" stroke="currentColor"
                  stroke-opacity="0.75" stroke-dasharray="3 1"
                  fill="#ffffff"
                  style="fill:#336699; fill-opacity:25%; fill-rule:evenodd" />
          </g>
        </svg>
        """)

        XCTAssertEqual(svg.viewBox, CGRect(x: 0, y: 0, width: 24, height: 12))
        XCTAssertEqual(svg.intrinsicSize, CGSize(width: 48, height: 24))
        XCTAssertEqual(svg.layers.count, 1)

        let layer = try XCTUnwrap(svg.layers.first)
        XCTAssertEqual(layer.opacity, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(layer.styles.count, 2)
        XCTAssertEqual(
            layer.path.applying(layer.transform).boundingRect,
            CGRect(x: 12, y: 6, width: 2, height: 2)
        )

        guard case let .fill(paint, style, opacity) = layer.styles[0] else {
            return XCTFail("Expected fill before stroke.")
        }
        XCTAssertEqual(
            paint,
            .color(Color(
                .sRGB,
                red: 0x33 / 255.0,
                green: 0x66 / 255.0,
                blue: 0x99 / 255.0
            ))
        )
        XCTAssertTrue(style.isEOFilled)
        XCTAssertEqual(opacity, 0.25, accuracy: 0.000_001)

        guard case let .stroke(paint, style, opacity) = layer.styles[1] else {
            return XCTFail("Expected stroke after fill.")
        }
        XCTAssertEqual(
            paint,
            .color(Color(.sRGB, red: 1, green: 0, blue: 0))
        )
        XCTAssertEqual(style.lineWidth, 2)
        XCTAssertEqual(style.lineCap, .round)
        XCTAssertEqual(style.dash, [3, 1])
        XCTAssertEqual(opacity, 0.75, accuracy: 0.000_001)
    }

    func testParserKeepsStandardAndEnvironmentPaintsDistinct() throws {
        let svg = try SVG(source: """
        <svg viewBox="0 0 10 10">
          <path d="M0 0H1V1Z" fill="currentColor" />
          <path d="M1 0H2V1Z" fill="foregroundStyle" />
          <path d="M2 0H3V1Z" fill="backgroundStyle" />
          <path d="M3 0H4V1Z" fill="none" stroke="#0f08" />
        </svg>
        """)

        XCTAssertEqual(svg.layers.count, 4)
        XCTAssertEqual(svg.layers[0].styles.first?.paint, .currentColor)
        XCTAssertEqual(svg.layers[1].styles.first?.paint, .foregroundStyle)
        XCTAssertEqual(svg.layers[2].styles.first?.paint, .backgroundStyle)

        guard case let .stroke(paint, _, _) = svg.layers[3].styles[0] else {
            return XCTFail("Expected a stroke-only layer.")
        }
        XCTAssertEqual(
            paint,
            .color(Color(
                .sRGB,
                red: 0,
                green: 1,
                blue: 0,
                opacity: 0x88 / 255.0
            ))
        )
    }

    func testEmbeddedClassStyleAppliesBeforeInlineStyle() throws {
        let svg = try SVG(source: """
        <svg viewBox="0 0 10 10">
          <style>
            .logo { fill: #a41e22; stroke: #000000; stroke-width: 2; }
          </style>
          <path class="logo" d="M0 0H4V4Z" />
          <path class="logo" style="fill:#ffffff" d="M5 0H9V4Z" />
        </svg>
        """)

        XCTAssertEqual(svg.layers.count, 2)
        XCTAssertEqual(
            svg.layers[0].styles[0].paint,
            .color(Color(
                .sRGB,
                red: 0xa4 / 255.0,
                green: 0x1e / 255.0,
                blue: 0x22 / 255.0
            ))
        )
        XCTAssertEqual(svg.layers[0].styles.count, 2)
        XCTAssertEqual(
            svg.layers[1].styles[0].paint,
            .color(Color(.sRGB, red: 1, green: 1, blue: 1))
        )
    }

    func testContentsOfURLLoadsTheSameDocumentAsSource() throws {
        let source = """
        <svg width="8" height="6">
          <path d="M0 0H8V6H0Z" />
        </svg>
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("svg")
        try Data(source.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            try SVG(contentsOf: url),
            try SVG(source: source)
        )
    }

    func testBasicSVGGeometryElementsBecomePathLayers() throws {
        let svg = try SVG(source: """
        <svg viewBox="0 0 30 20">
          <rect x="1" y="2" width="5" height="4" />
          <rect x="0" y="0" width="30" height="20" fill="none" />
          <circle cx="10" cy="5" r="2" />
          <ellipse cx="16" cy="5" rx="3" ry="2" />
          <line x1="1" y1="10" x2="6" y2="10"
                fill="none" stroke="black" />
          <polyline points="8,10 10,12 12,10"
                    fill="none" stroke="black" />
          <polygon points="14,10 16,12 18,10" />
        </svg>
        """)

        XCTAssertEqual(svg.layers.count, 6)
        XCTAssertEqual(svg.layers[0].path.boundingRect, CGRect(x: 1, y: 2, width: 5, height: 4))
        XCTAssertEqual(svg.layers[1].path.boundingRect, CGRect(x: 8, y: 3, width: 4, height: 4))
        XCTAssertEqual(svg.layers[2].path.boundingRect, CGRect(x: 13, y: 3, width: 6, height: 4))
        XCTAssertEqual(svg.layers[3].styles.count, 1)
        XCTAssertEqual(svg.layers[4].styles.count, 1)
        XCTAssertEqual(svg.layers[5].path.currentPoint, CGPoint(x: 14, y: 10))
    }

    func testSVGImageProviderDoesNotEnterTheSymbolEffectPath() throws {
        let svg = try SVG(source: """
        <svg viewBox="0 0 12 8">
          <path d="M0 0H12V8H0Z" fill="foregroundStyle" />
        </svg>
        """)
        let image = Image(svg: svg)
        let provider = try XCTUnwrap(image.provider as? SVGImageProvider)

        XCTAssertEqual(provider.makeSVG(), svg)
        XCTAssertNil(provider.makeVectorSymbol())

        let resolved = GraphicsContext.ResolvedImage(svg: svg)
        XCTAssertEqual(resolved.svg, svg)
        XCTAssertNil(resolved.symbol)
        XCTAssertEqual(resolved.size, CGSize(width: 12, height: 8))

        let record = DisplayList.ItemRecord.ImageRecord(
            resolved,
            placementRect: CGRect(x: 1, y: 2, width: 12, height: 8),
            shading: nil
        )
        XCTAssertEqual(record.vectorID, resolved.vectorID)
        XCTAssertNil(record.symbolID)
    }

    func testResizableSVGMatchesNativeProposalRouting() throws {
        let svg = try SVG(source: """
        <svg viewBox="0 0 1300 500">
          <path d="M0 0H1300V500H0Z" fill="#ff0000" />
        </svg>
        """)
        let original = Image(svg: svg)
        let resizable = original.resizable()
        let provider = try XCTUnwrap(
            resizable.provider as? ResizableProvider
        )

        XCTAssertEqual(provider.base, original)
        XCTAssertEqual(provider.capInsets, EdgeInsets())
        XCTAssertEqual(provider.resizingMode, .stretch)

        let host = GraphHost()
        let graph = host.data.graph
        try host.data.withCurrent {
            var inputs = makeViewInputs(graph: graph)
            inputs.requestsLayoutComputer = true

            func layoutComputer(for image: VUI.Image) throws -> LayoutComputer {
                let attribute = graph.makeInput(value: image)
                let outputs = VUI.Image._makeView(
                    view: _GraphValue(_attribute: attribute),
                    inputs: inputs
                )
                return try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            }

            let originalLayout = try layoutComputer(for: original)
            XCTAssertEqual(
                originalLayout.sizeThatFits(.unspecified),
                CGSize(width: 1300, height: 500)
            )
            XCTAssertEqual(
                originalLayout.sizeThatFits(
                    _ProposedSize(width: 160, height: 62)
                ),
                CGSize(width: 1300, height: 500)
            )

            let resizableLayout = try layoutComputer(for: resizable)
            XCTAssertEqual(
                resizableLayout.sizeThatFits(.unspecified),
                CGSize(width: 1300, height: 500)
            )
            XCTAssertEqual(
                resizableLayout.sizeThatFits(.zero),
                .zero
            )
            XCTAssertEqual(
                resizableLayout.sizeThatFits(
                    _ProposedSize(width: 160, height: nil)
                ),
                CGSize(width: 160, height: 500)
            )
            XCTAssertEqual(
                resizableLayout.sizeThatFits(
                    _ProposedSize(width: nil, height: 62)
                ),
                CGSize(width: 1300, height: 62)
            )
            XCTAssertEqual(
                resizableLayout.sizeThatFits(
                    _ProposedSize(width: 160, height: 62)
                ),
                CGSize(width: 160, height: 62)
            )
        }

        // ASSERTIONS imageResizableFixedFrameRuntimeObserved
    }

    func testResizableSVGStretchesIntoTheProposedFrameOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let svg = try SVG(source: """
        <svg viewBox="0 0 10 10">
          <path d="M0 0H10V10H0Z" fill="#ff0000" />
        </svg>
        """)
        let width = 40
        let height = 10
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(),
            environment: EnvironmentValues(),
            viewport: CGRect(x: 0, y: 0, width: width, height: height),
            contentOffset: .zero,
            contentScaleFactor: 1,
            resolution: CGSize(width: width, height: height),
            commandBuffer: commandBuffer
        ))
        context.clear(with: .clear)
        context.draw(
            context.resolve(Image(svg: svg)),
            in: CGRect(x: 0, y: 0, width: 20, height: 10)
        )
        context.draw(
            context.resolve(Image(svg: svg).resizable()),
            in: CGRect(x: 20, y: 0, width: 20, height: 10)
        )
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(
            deviceContext.makeCPUAccessible(texture: context.backdrop)
        )
        let pointer = try XCTUnwrap(staging.contents())
        func pixel(x: Int, y: Int) -> [UInt8] {
            let offset = ((y * width) + x) * 4
            return Array(
                UnsafeRawBufferPointer(
                    start: pointer + offset,
                    count: 4
                )
            )
        }

        XCTAssertEqual(pixel(x: 1, y: 5), [0, 0, 0, 0])
        XCTAssertEqual(pixel(x: 6, y: 5), [255, 0, 0, 255])
        XCTAssertEqual(pixel(x: 21, y: 5), [255, 0, 0, 255])
        XCTAssertEqual(pixel(x: 39, y: 5), [255, 0, 0, 255])

        // ASSERTIONS imageResizableFixedFrameRuntimeObserved
    }

    @MainActor
    func testResizableSVGFixedFrameInsideOptionalKeepsFollowingTextBelowImage() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal),
              let renderQueue = deviceContext.renderQueue(),
              let fontURL = defaultFontURL,
              let textureFont = TextureFont(
                deviceContext: deviceContext,
                path: fontURL.path
              ) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        _ = textureFont
        let previousAppContext = appContext
        appContext = SVGTestAppContext(graphicsDeviceContext: deviceContext)
        defer { appContext = previousAppContext }

        let svg = try SVG(source: """
        <svg viewBox="0 0 1300 500">
          <path d="M0 0H1300V500H0Z" fill="#ff0000" />
        </svg>
        """)
        let controller = WindowController(
            content: ResizableSVGCaptionRoot(
                portrait: Image(
                    size: CGSize(width: 154, height: 180),
                    opaque: true
                ) { _ in },
                logo: Image(svg: svg)
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ResizableSVGCaptionRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 360, height: 440),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 360, height: 440),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the text resource graphics context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        controller.updateFrame(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 360, height: 440),
            shouldDrawFrame: false,
            withGC
        )

        let displayList = try controller.viewGraph.data.withCurrent {
            try XCTUnwrap(controller.viewGraph.rootDisplayList?.value)
        }
        let imageBounds = displayBounds(of: .image, in: displayList)
        let textBounds = displayBounds(of: .text, in: displayList)
        let imageFrame = try XCTUnwrap(
            imageBounds.first {
                abs($0.width - 160) <= 0.5 &&
                    abs($0.height - 62) <= 0.5
            }
        )
        let captionFrame = try XCTUnwrap(
            textBounds.first {
                $0.minY >= imageFrame.minY &&
                    $0.minY <= imageFrame.maxY + 40
            }
        )

        XCTAssertEqual(imageFrame.size, CGSize(width: 160, height: 62))
        XCTAssertGreaterThanOrEqual(
            captionFrame.minY,
            imageFrame.maxY + 13.5,
            "caption=\(captionFrame), image=\(imageFrame)"
        )

        // ASSERTIONS imageResizableFixedFrameRuntimeObserved
        // ASSERTIONS conditionalMultiviewDynamicItemsUnaryObserved
    }

    func testSVGDrawsThroughOrderedPathPassesOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let svg = try SVG(source: """
        <svg viewBox="0 0 8 8">
          <path d="M0 0H8V8H0Z" fill="#ff0000" />
          <path d="M2 2H6V6H2Z" fill="#0000ff" fill-opacity="0.5" />
        </svg>
        """)
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(),
            environment: EnvironmentValues(),
            viewport: CGRect(x: 0, y: 0, width: 8, height: 8),
            contentOffset: .zero,
            contentScaleFactor: 1,
            resolution: CGSize(width: 8, height: 8),
            commandBuffer: commandBuffer
        ))
        context.clear(with: .clear)
        context.draw(
            context.resolve(Image(svg: svg)),
            in: CGRect(x: 0, y: 0, width: 8, height: 8)
        )
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        func pixel(x: Int, y: Int) -> [UInt8] {
            let offset = ((y * 8) + x) * 4
            return Array(UnsafeRawBufferPointer(start: pointer + offset, count: 4))
        }

        XCTAssertEqual(pixel(x: 1, y: 1), [255, 0, 0, 255])
        let blended = pixel(x: 4, y: 4)
        XCTAssertEqual(blended[3], 255)
        XCTAssertEqual(blended[0], 128, accuracy: 1)
        XCTAssertEqual(blended[1], 0)
        XCTAssertEqual(blended[2], 128, accuracy: 1)
    }

    func testMalformedPathAndUnsupportedPaintFailExplicitly() {
        XCTAssertThrowsError(try SVG(source: """
        <svg viewBox="0 0 10 10"><path d="M0 nope" /></svg>
        """)) { error in
            XCTAssertEqual(error as? SVG.ParsingError, .invalidPathData)
        }

        XCTAssertThrowsError(try SVG(source: """
        <svg viewBox="0 0 10 10"><path d="M0 0H1V1Z" fill="url(#paint)" /></svg>
        """)) { error in
            XCTAssertEqual(
                error as? SVG.ParsingError,
                .unsupportedPaint("url(#paint)")
            )
        }
    }

    private func waitForCompletion(_ commandBuffer: CommandBuffer) throws {
        let condition = NSCondition()
        var completed = false
        commandBuffer.addCompletedHandler { _ in
            condition.lock()
            completed = true
            condition.broadcast()
            condition.unlock()
        }
        condition.lock()
        defer { condition.unlock() }
        XCTAssertTrue(commandBuffer.commit())
        let timeout = Date(timeIntervalSinceNow: 5)
        while !completed {
            if !condition.wait(until: timeout) {
                XCTFail("GPU command buffer timed out")
                break
            }
        }
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: graph.makeInput(value: EnvironmentValues()),
            transaction: graph.makeInput(value: Transaction())
        )
        return _ViewInputs(
            base: base,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }

    private func displayBounds(
        of kind: DisplayList.ItemRecord.Kind,
        in displayList: DisplayList
    ) -> [CGRect] {
        var bounds = displayList.itemRecords.compactMap { record -> CGRect? in
            guard record.kind == kind else { return nil }
            return record.bounds
        }
        for effect in displayList.effects {
            bounds.append(contentsOf: displayBounds(
                of: kind,
                in: effect.contents
            ).map {
                $0.offsetBy(
                    dx: effect.frame.minX,
                    dy: effect.frame.minY
                )
            })
        }
        return bounds
    }
}

private struct ResizableSVGCaptionRoot: View {
    let portrait: VUI.Image
    let logo: VUI.Image?

    var body: some View {
        VStack(spacing: 14) {
            Text("Image Lab")
                .font(.system(size: 22, weight: .semibold))

            portrait
                .frame(width: 154, height: 180)

            Text("Named JPEG resource · 154 × 180")
                .font(.system(.caption))
                .foregroundColor(.secondary)

            if let logo {
                logo
                    .resizable()
                    .frame(width: 160, height: 62)

                Text("SVG resource · 160 × 62")
                    .font(.system(.caption))
                    .foregroundColor(.secondary)
            }

            Button("Close") {
            }
        }
        .padding(20)
        .frame(width: 360, height: 440)
    }
}

private final class SVGTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext?
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    private var resources: [URL: any DataProtocol] = [:]

    init(graphicsDeviceContext: GraphicsDeviceContext) {
        self.graphicsDeviceContext = graphicsDeviceContext
    }

    func resourceData(forURL url: URL) -> (any DataProtocol)? {
        resources[url]
    }

    func setResource(data: (any DataProtocol)?, forURL url: URL) {
        resources[url] = data
    }

    func checkWindowActivities() {
    }
}

private extension SVG.Style {
    var paint: SVG.Paint {
        switch self {
        case let .fill(paint, _, _), let .stroke(paint, _, _):
            paint
        }
    }
}
