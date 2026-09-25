import Observation
import XCTest
import VVD
@testable import VUI

final class CanvasSymbolTests: XCTestCase {
    private struct Pixels {
        var bounds = CGRect.null
        var alpha = 0
    }

    private func device() throws -> GraphicsDeviceContext {
        #if canImport(Metal)
        return try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        #else
        throw XCTSkip("A Metal device is required for pixel checks")
        #endif
    }

    private func render<Content: View>(
        _ host: SymbolHost<Content>,
        device: GraphicsDeviceContext,
        viewport: CGSize = CGSize(width: 100, height: 80),
        translation: CGSize = .zero
    ) throws -> Pixels {
        let width = Int(viewport.width)
        let height = Int(viewport.height)
        let queue = try XCTUnwrap(device.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        var context = try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(), environment: EnvironmentValues(),
            viewport: CGRect(x: 0, y: 0, width: width, height: height),
            contentOffset: .zero, contentScaleFactor: 1,
            resolution: CGSize(width: width, height: height), commandBuffer: commands
        ))
        context.clear(with: .clear)
        context.translateBy(x: translation.width, y: translation.height)
        host.host.data.withCurrent {
            host.host.data.rootSubgraph.update()
            host.renderer.render(list: host.list.value, at: .zero, in: context)
        }
        let condition = NSCondition()
        var completed = false
        commands.addCompletedHandler { _ in
            condition.lock()
            completed = true
            condition.signal()
            condition.unlock()
        }
        condition.lock()
        XCTAssertTrue(commands.commit())
        let deadline = Date(timeIntervalSinceNow: 5)
        while !completed {
            if !condition.wait(until: deadline) {
                condition.unlock()
                throw NSError(domain: "CanvasSymbolTests.GPUCompletion", code: 1)
            }
        }
        condition.unlock()
        let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(start: pointer, count: width * height * 4)
        var result = Pixels()
        for y in 0..<height {
            for x in 0..<width {
                let alpha = Int(bytes[(y * width + x) * 4 + 3])
                if alpha > 0 {
                    result.bounds = result.bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
                result.alpha += alpha
            }
        }
        return result
    }

    func testRendererRecordsDuringDisplayListEvaluation() {
        let log = SymbolLayoutLog()
        var calls = 0
        let host = SymbolHost(Canvas { context, _ in
            calls += 1
            guard let symbol = context.resolveSymbol(id: "layout") else {
                return XCTFail("Expected a resolved symbol")
            }
            context.draw(symbol, at: .zero, anchor: .topLeading)
        } symbols: {
            SymbolLayout(log: log) { Color.red }.tag("layout")
        })

        let list = host.host.data.withCurrent {
            host.host.data.rootSubgraph.update()
            return host.list.value
        }

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(log.proposals, [ProposedViewSize(width: 100, height: 80)])
        guard list.items.count == 1,
              case let .content(content) = list.items[0].value,
              case .drawing = content.value else {
            return XCTFail("Canvas evaluation must publish retained drawing contents")
        }

        host.host.data.withCurrent {
            host.host.data.rootSubgraph.update()
            _ = host.list.value
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(log.proposals.count, 1)
    }

    func testRendererOnlyInvalidationPreservesSymbolProviderCache() {
        let model = SymbolModel()
        let log = SymbolLayoutLog()
        var calls = 0
        var symbolLists: [ObjectIdentifier] = []
        let host = SymbolHost(Canvas { context, _ in
            calls += 1
            _ = model.tick
            guard let symbol = context.resolveSymbol(id: "layout") else {
                return XCTFail("Expected a resolved symbol")
            }
            symbolLists.append(ObjectIdentifier(symbol.list))
            context.draw(symbol, at: .zero, anchor: .topLeading)
            XCTAssertNil(context.resolveSymbol(id: "missing"))
        } symbols: {
            SymbolLayout(log: log) { Color.red }.tag("layout")
        })

        func evaluate() {
            host.host.data.withCurrent {
                host.host.data.rootSubgraph.update()
                _ = host.list.value
            }
        }

        evaluate()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(log.proposals.count, 1)

        model.tick += 1
        host.host.flushTransactions()
        evaluate()

        XCTAssertEqual(calls, 2)
        XCTAssertEqual(log.proposals.count, 1)
        XCTAssertEqual(symbolLists.count, 2)
        XCTAssertEqual(symbolLists[0], symbolLists[1])

        evaluate()
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(log.proposals.count, 1)
    }

    func testScrollRecordingUsesOverscannedBoundsAndReusesEachTile() throws {
        let inputs = CanvasScrollInputs()
        var calls = 0
        let host = SymbolHost(
            Canvas { context, _ in
                calls += 1
                for y in [19, 147, 275, 531, 968] as [CGFloat] {
                    context.fill(
                        Path(CGRect(x: 17, y: y, width: 21, height: 13)),
                        with: .color(.red)
                    )
                }
            },
            size: CGSize(width: 180, height: 1_000),
            features: [inputs]
        )

        func evaluate(_ offset: CGFloat?) -> DisplayList {
            host.host.data.withCurrent {
                if let offset {
                    inputs.setOffset(offset)
                }
                host.host.data.rootSubgraph.update()
                return host.list.value
            }
        }

        func drawing(
            _ list: DisplayList,
            frame: CGRect,
            origin: CGPoint,
            file: StaticString = #filePath,
            line: UInt = #line
        ) -> (ObjectIdentifier, DisplayList.Version)? {
            guard list.items.count == 1,
                  case let .content(content) = list.items[0].value,
                  case let .drawing(contents, actualOrigin, _) = content.value else {
                XCTFail("Expected one retained Canvas drawing", file: file, line: line)
                return nil
            }
            XCTAssertEqual(list.items[0].frame, frame, file: file, line: line)
            XCTAssertEqual(actualOrigin, origin, file: file, line: line)
            return (ObjectIdentifier(contents), list.items[0].version)
        }

        let initial = evaluate(nil)
        XCTAssertEqual(calls, 1)
        let initialDrawing = try XCTUnwrap(drawing(
            initial,
            frame: CGRect(x: 16, y: 16, width: 32, height: 144),
            origin: CGPoint(x: 16, y: 16)
        ))

        for offset in [40, 80, 127] as [CGFloat] {
            let reused = evaluate(offset)
            XCTAssertEqual(calls, 1, "offset \(offset)")
            let reusedDrawing = try XCTUnwrap(drawing(
                reused,
                frame: CGRect(x: 16, y: 16, width: 32, height: 144),
                origin: CGPoint(x: 16, y: 16)
            ))
            XCTAssertEqual(reusedDrawing.0, initialDrawing.0, "offset \(offset)")
            XCTAssertEqual(reusedDrawing.1, initialDrawing.1, "offset \(offset)")
        }

        let secondTile = evaluate(128)
        XCTAssertEqual(calls, 2)
        let secondDrawing = try XCTUnwrap(drawing(
            secondTile,
            frame: CGRect(x: 16, y: 144, width: 32, height: 144),
            origin: CGPoint(x: 16, y: 16)
        ))
        XCTAssertNotEqual(secondDrawing.0, initialDrawing.0)
        XCTAssertNotEqual(secondDrawing.1, initialDrawing.1)

        let reusedSecondTile = evaluate(200)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(
            try XCTUnwrap(drawing(
                reusedSecondTile,
                frame: CGRect(x: 16, y: 144, width: 32, height: 144),
                origin: CGPoint(x: 16, y: 16)
            )).0,
            secondDrawing.0
        )

        XCTAssertNotEqual(
            try XCTUnwrap(drawing(
                evaluate(256),
                frame: CGRect(x: 16, y: 272, width: 32, height: 16),
                origin: CGPoint(x: 16, y: 16)
            )).0,
            secondDrawing.0
        )
        XCTAssertEqual(calls, 3)
        _ = drawing(
            evaluate(600),
            frame: CGRect(x: 16, y: 528, width: 32, height: 16),
            origin: CGPoint(x: 16, y: 16)
        )
        XCTAssertEqual(calls, 4)
    }

    func testScrollRecordingReplaysAtCanvasCoordinates() throws {
        let device = try device()
        let inputs = CanvasScrollInputs()
        let host = SymbolHost(
            Canvas { context, _ in
                for y in [19, 147, 275, 531, 968] as [CGFloat] {
                    context.fill(
                        Path(CGRect(x: 17, y: y, width: 21, height: 13)),
                        with: .color(.red)
                    )
                }
            },
            size: CGSize(width: 180, height: 1_000),
            features: [inputs]
        )
        host.host.data.withCurrent {
            inputs.setOffset(128)
        }

        let pixels = try render(
            host,
            device: device,
            viewport: CGSize(width: 180, height: 140),
            translation: CGSize(width: 0, height: -128)
        )
        XCTAssertEqual(pixels.bounds, CGRect(x: 17, y: 19, width: 21, height: 13))
        XCTAssertEqual(pixels.alpha, 21 * 13 * 255)
    }

    func testTypedLookupDuplicateOptionalAndListTags() throws {
        let device = try device()
        var called = false
        let canvas = Canvas { context, _ in
            called = true
            XCTAssertNil(context.resolveSymbol(id: "missing"))
            XCTAssertNil(context.resolveSymbol(id: "empty"))
            XCTAssertNil(context.resolveSymbol(id: "inner"))
            XCTAssertNil(context.resolveSymbol(id: "onlyID"))
            XCTAssertNil(context.resolveSymbol(id: Int64(7)))
            XCTAssertNil(context.resolveSymbol(id: Optional("noOptional")))
            XCTAssertEqual(context.resolveSymbol(id: "rect")?.size, CGSize(width: 20, height: 10))
            XCTAssertEqual(context.resolveSymbol(id: Optional("rect"))?.size, CGSize(width: 20, height: 10))
            XCTAssertEqual(context.resolveSymbol(id: "duplicate")?.size, CGSize(width: 11, height: 12))
            XCTAssertEqual(context.resolveSymbol(id: "zero")?.size, .zero)
            XCTAssertEqual(context.resolveSymbol(id: 0)?.size.width, 3)
            XCTAssertEqual(context.resolveSymbol(id: 2)?.size.width, 9)
            // Numeric AnyHashable keys share the cached miss from the Int64 lookup.
            XCTAssertNil(context.resolveSymbol(id: 7))
            XCTAssertNil(context.resolveSymbol(id: 3))
        } symbols: {
            Color.red.frame(width: 20, height: 10).tag("rect")
            EmptyView().tag("empty")
            Color.clear.frame(width: 0, height: 0).tag("zero")
            Color.blue.frame(width: 11, height: 12).tag("duplicate")
            Color.yellow.frame(width: 21, height: 22).tag("duplicate")
            HStack { Color.green.frame(width: 5, height: 6).tag("inner") }.tag("group")
            Color.red.frame(width: 8, height: 9).id("onlyID")
            Color.red.frame(width: 7, height: 6).tag(7)
            Color.red.frame(width: 4, height: 5).tag("noOptional", includeOptional: false)
            ForEach(1..<4) { i in Color.black.frame(width: CGFloat(i * 3), height: 5) }
        }
        _ = try render(SymbolHost(canvas), device: device)
        XCTAssertTrue(called)
    }

    func testResolutionIsLazyUsesCanvasProposalAndDrawDoesNotRelayout() throws {
        let device = try device()
        let log = SymbolLayoutLog()
        var called = false
        let canvas = Canvas { context, size in
            called = true
            XCTAssertEqual(size, CGSize(width: 100, height: 80))
            XCTAssertTrue(log.proposals.isEmpty)
            guard let symbol = context.resolveSymbol(id: "layout") else {
                return XCTFail("Expected a layout symbol")
            }
            XCTAssertEqual(symbol.size, CGSize(width: 20, height: 10))
            XCTAssertEqual(log.proposals, [ProposedViewSize(width: 100, height: 80)])
            let count = log.proposals.count
            XCTAssertEqual(context.resolveSymbol(id: "layout")?.size, symbol.size)
            context.draw(symbol, in: CGRect(x: 0, y: 0, width: 40, height: 20))
            context.draw(symbol, at: CGPoint(x: 50, y: 50))
            XCTAssertEqual(log.proposals.count, count)
        } symbols: {
            SymbolLayout(log: log) { Color.red }.tag("layout")
        }
        _ = try render(SymbolHost(canvas), device: device)
        XCTAssertTrue(called)
    }

    func testSymbolDrawingCoordinatesClipOpacityAndRetainedSnapshot() throws {
        let device = try device()
        var retained: GraphicsContext.ResolvedSymbol?
        let cases: [(String, CGRect, Int)] = [
            ("point", CGRect(x: 10, y: 15, width: 20, height: 10), 51_000),
            ("rect", CGRect(x: 10, y: 15, width: 40, height: 30), 306_000),
            ("transform", CGRect(x: 27, y: 24, width: 40, height: 30), 306_000),
            ("clip", CGRect(x: 12, y: 13, width: 4, height: 3), 3_060),
            ("opacity", CGRect(x: 10, y: 15, width: 20, height: 10), 25_600),
            ("retained", CGRect(x: 10, y: 15, width: 20, height: 10), 51_000)
        ]
        for (name, bounds, alpha) in cases {
            let canvas = Canvas { context, _ in
                guard let symbol = name == "retained" ? retained : context.resolveSymbol(id: "rect") else {
                    return XCTFail("Expected a resolved symbol")
                }
                if name == "point" { retained = symbol }
                switch name {
                case "rect": context.draw(symbol, in: CGRect(x: 10, y: 15, width: 40, height: 30))
                case "transform":
                    context.translateBy(x: 7, y: 9)
                    context.scaleBy(x: 2, y: 3)
                    let before = context.transform
                    context.draw(symbol, at: CGPoint(x: 10, y: 5), anchor: .topLeading)
                    XCTAssertEqual(context.transform, before)
                case "clip":
                    context.clip(to: Path(CGRect(x: 12, y: 13, width: 4, height: 3)))
                    let before = context.clipBoundingRect
                    context.draw(symbol, in: CGRect(x: 10, y: 10, width: 20, height: 10))
                    XCTAssertEqual(context.clipBoundingRect, before)
                case "opacity":
                    context.opacity = 0.5
                    context.draw(symbol, at: CGPoint(x: 20, y: 20))
                    XCTAssertEqual(context.opacity, 0.5)
                default: context.draw(symbol, at: CGPoint(x: 20, y: 20))
                }
            } symbols: {
                Color.red.frame(width: 20, height: 10).tag("rect")
            }
            let result = try render(SymbolHost(canvas), device: device)
            XCTAssertEqual(result.bounds, bounds, name)
            XCTAssertEqual(result.alpha, alpha, accuracy: 200, name)
        }

        let overlap = Canvas { context, _ in
            context.opacity = 0.5
            if let symbol = context.resolveSymbol(id: "r") {
                context.draw(symbol, at: CGPoint(x: 20, y: 20))
            }
        } symbols: {
            ZStack { Color.red; Color.green }.frame(width: 20, height: 10).tag("r")
        }
        let result = try render(SymbolHost(overlap), device: device)
        XCTAssertEqual(result.bounds, CGRect(x: 10, y: 15, width: 20, height: 10))
        XCTAssertEqual(result.alpha, 38_200, accuracy: 200)
    }

    func testLayersInheritSymbolsAndNestedCanvasHasItsOwnNamespace() throws {
        let device = try device()
        var nestedCalls = 0
        let canvas = Canvas { context, _ in
            context.drawLayer { layer in
                XCTAssertNotNil(layer.resolveSymbol(id: "rect"))
            }
            context.clipToLayer { layer in
                if let symbol = layer.resolveSymbol(id: "rect") {
                    layer.draw(symbol, at: CGPoint(x: 10, y: 10), anchor: .topLeading)
                }
            }
            if let nested = context.resolveSymbol(id: "nested") {
                XCTAssertEqual(nestedCalls, 1)
                context.draw(nested, at: CGPoint(x: 10, y: 10), anchor: .topLeading)
                context.draw(nested, at: CGPoint(x: 40, y: 40), anchor: .topLeading)
                XCTAssertEqual(nestedCalls, 1)
            }
        } symbols: {
            Color.red.frame(width: 20, height: 10).tag("rect")
            Canvas { inner, _ in
                nestedCalls += 1
                XCTAssertNil(inner.resolveSymbol(id: "rect"))
                inner.fill(Path(CGRect(x: 0, y: 0, width: 20, height: 10)), with: .color(.red))
            }.frame(width: 20, height: 10).tag("nested")
        }
        let result = try render(SymbolHost(canvas), device: device)
        XCTAssertEqual(nestedCalls, 1)
        XCTAssertEqual(result.bounds, CGRect(x: 10, y: 10, width: 20, height: 10))
        XCTAssertEqual(result.alpha, 51_000)
    }

    func testRetainedChildStateReorderRemovalAndSymbolInvalidation() throws {
        let device = try device()
        let model = SymbolModel()
        let identities = SymbolIdentities()
        let host = SymbolHost(StatefulCanvas(model: model, identities: identities))
        _ = try render(host, device: device)
        let first = identities.tokens
        XCTAssertEqual(identities.widths.last, 21)
        model.width = 30
        host.host.flushTransactions()
        _ = try render(host, device: device)
        XCTAssertEqual(identities.widths.last, 31)
        model.rows = [2, 1, 3]
        host.host.flushTransactions()
        _ = try render(host, device: device)
        XCTAssertEqual(identities.tokens[1], first[1])
        XCTAssertEqual(identities.tokens[2], first[2])
        XCTAssertNotNil(identities.tokens[3])
        model.rows = [2, 3]
        host.host.flushTransactions()
        _ = try render(host, device: device)
        XCTAssertEqual(identities.widths.last, -1)
        model.rows = [1, 2, 3]
        host.host.flushTransactions()
        _ = try render(host, device: device)
        XCTAssertNotEqual(identities.tokens[1], first[1])
        XCTAssertEqual(identities.tokens[2], first[2])
        XCTAssertEqual(identities.previous?.size.width, 21)
    }

    func testNestedRendererObservationInvalidatesNewSymbolAndPreservesOldCommands() throws {
        let device = try device()
        let model = SymbolModel()
        var calls = 0
        var first: GraphicsContext.ResolvedSymbol?
        let canvas = Canvas { context, _ in
            if let symbol = context.resolveSymbol(id: "drawing") {
                first = first ?? symbol
                context.draw(symbol, at: CGPoint(x: 10, y: 10), anchor: .topLeading)
            }
        } symbols: {
            Canvas { context, _ in
                calls += 1
                context.fill(Path(CGRect(x: 0, y: 0, width: model.width, height: 10)), with: .color(.red))
            }.frame(width: 50, height: 10).tag("drawing")
        }
        let host = SymbolHost(canvas)
        XCTAssertEqual(try render(host, device: device).alpha, 51_000)
        model.width = 30
        XCTAssertEqual(try render(host, device: device).alpha, 76_500)
        let retained = Canvas { context, _ in
            if let first { context.draw(first, at: CGPoint(x: 10, y: 10), anchor: .topLeading) }
        }
        XCTAssertEqual(try render(SymbolHost(retained), device: device).alpha, 51_000)
        XCTAssertEqual(calls, 2)
    }

    func testChangedTagRefreshesLookupAndCachedMiss() throws {
        let device = try device()
        let model = SymbolModel()
        let result = SymbolTagResults()
        let host = SymbolHost(TaggedCanvas(model: model, result: result))
        _ = try render(host, device: device)
        XCTAssertEqual(result.found, [true, false])
        model.tag = "second"
        _ = try render(host, device: device)
        XCTAssertEqual(result.found, [false, true])
    }

    func testRecordedSymbolRetainsTextImagePathAndLayerDrawing() throws {
        let device = try device()
        var retained: GraphicsContext.ResolvedSymbol?
        let canvas = Canvas { context, _ in
            retained = context.resolveSymbol(id: "mixed")
            if let retained { context.draw(retained, at: .zero, anchor: .topLeading) }
        } symbols: {
            HStack(spacing: 0) {
                Text("A").font(.system(size: 14)).foregroundStyle(.red)
                Image(systemName: "star.fill").resizable().frame(width: 15, height: 15)
                Circle().stroke(.blue, lineWidth: 2).frame(width: 10, height: 10)
            }.padding(2).background(.green).opacity(0.75).tag("mixed")
        }
        let first = try render(SymbolHost(canvas), device: device)
        XCTAssertGreaterThan(first.alpha, 0)
        let replay = Canvas { context, _ in
            if let retained { context.draw(retained, at: .zero, anchor: .topLeading) }
        }
        let second = try render(SymbolHost(replay), device: device)
        XCTAssertEqual(second.bounds, first.bounds)
        XCTAssertEqual(second.alpha, first.alpha)
    }
}

private final class SymbolHost<Content: View> {
    let rendererHost = TestViewRendererHost()
    let host: ViewGraph
    let renderer = DisplayList.GraphicsRenderer()
    var list: Attribute<DisplayList> { host.rootDisplayList! }

    init(
        _ content: Content,
        size: CGSize = CGSize(width: 100, height: 80),
        features: [any ViewGraphFeature] = []
    ) {
        host = ViewGraph(
            rootViewType: Content.self,
            content: content,
            rendererHost: rendererHost,
            features: features
        )
        host.setSize(size)
        host.instantiateIfNeeded()
    }
}

private final class CanvasScrollInputs: ViewGraphFeature {
    private var transform: Attribute<VUI.ViewTransform>?

    func modifyViewInputs(inputs: inout _ViewInputs, graph: ViewGraph) {
        let transform = graph.data.graph.makeInput(value: value(offset: 0))
        self.transform = transform
        inputs.transform = transform
        inputs[UsingGraphicsRenderer.self] = false
    }

    func setOffset(_ offset: CGFloat) {
        guard let transform else {
            fatalError("Canvas scroll inputs have not been installed.")
        }
        transform.setValue(value(offset: offset))
    }

    private func value(offset: CGFloat) -> VUI.ViewTransform {
        var transform = VUI.ViewTransform()
        transform.appendScrollGeometry(
            ScrollGeometry(
                contentOffset: CGPoint(x: 0, y: offset),
                contentSize: CGSize(width: 180, height: 1_000),
                containerSize: CGSize(width: 180, height: 140)
            ),
            isClipped: true
        )
        return transform
    }
}

private final class SymbolLayoutLog: @unchecked Sendable {
    var proposals: [ProposedViewSize] = []
}

private struct SymbolLayout: Layout {
    var log: SymbolLayoutLog
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        log.proposals.append(proposal)
        return CGSize(width: 20, height: 10)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for view in subviews { view.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}

@Observable private final class SymbolModel {
    var tick = 0
    var width: CGFloat = 20
    var rows = [1, 2]
    var tag = "first"
}

private final class SymbolTagResults {
    var found: [Bool] = []
}

private struct TaggedCanvas: View {
    var model: SymbolModel
    var result: SymbolTagResults
    var body: some View {
        Canvas { context, _ in
            result.found = [context.resolveSymbol(id: "first") != nil, context.resolveSymbol(id: "second") != nil]
        } symbols: {
            Color.red.frame(width: 20, height: 10).tag(model.tag)
        }
    }
}

private final class SymbolIdentities {
    var tokens: [Int: UUID] = [:]
    var widths: [CGFloat] = []
    var previous: GraphicsContext.ResolvedSymbol?
}

private struct StatefulCanvas: View {
    var model: SymbolModel
    var identities: SymbolIdentities
    var body: some View {
        Canvas { context, _ in
            _ = context.resolveSymbol(id: 2)
            _ = context.resolveSymbol(id: 3)
            let symbol = context.resolveSymbol(id: 1)
            identities.widths.append(symbol?.size.width ?? -1)
            identities.previous = identities.previous ?? symbol
            if let symbol { context.draw(symbol, at: .zero, anchor: .topLeading) }
        } symbols: {
            ForEach(model.rows, id: \.self) { row in
                StatefulCanvasSymbol(row: row, model: model, identities: identities)
            }
        }
    }
}

private struct StatefulCanvasSymbol: View {
    var row: Int
    var model: SymbolModel
    var identities: SymbolIdentities
    @State private var token = UUID()
    var body: some View {
        identities.tokens[row] = token
        return Color.red.frame(width: model.width + CGFloat(row), height: 10)
    }
}
