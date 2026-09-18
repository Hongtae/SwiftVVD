import Foundation
import XCTest
import VVD
@testable import VUI

final class ShapeStyleCompositionTests: XCTestCase {
    private let frame = CGRect(x: 30, y: 26, width: 36, height: 28)
    private var red: VUI.Color.ResolvedHDR { Color(.sRGBLinear, red: 0.8, green: 0.1, blue: 0.2).resolveHDR(in: .init()) }
    private var drop: ResolvedShadowStyle {
        ShadowStyle.drop(color: .green.opacity(0.7), radius: 2, x: 4, y: 3).resolve(in: .init())
    }
    private var inner: ResolvedShadowStyle {
        ShadowStyle.inner(color: .blue.opacity(0.6), radius: 3, x: -2, y: 1).resolve(in: .init())
    }
    private func style(_ shadows: [ResolvedShadowStyle], opacity: Float = 1,
                       blend: GraphicsContext.BlendMode? = nil) -> _ShapeStyle_Pack.Style {
        var style = _ShapeStyle_Pack.Style(.color(red))
        style.opacity = opacity
        style._blend = blend
        style.effects = shadows.map { .init(kind: .shadow($0), opacity: 1, _blend: nil) }
        return style
    }

    private func rendered(_ style: _ShapeStyle_Pack.Style, commit: Bool = true) throws -> _ShapeStyle_RenderedShape {
        let graph = _AGGraph()
        return try _AGGraph.withCurrent(graph) {
            var shape = _ShapeStyle_RenderedShape(shape: .path(Path(frame), FillStyle()),
                contentSeed: .init(decodedValue: 9), frame: frame,
                version: .init(value: 7), options: [],
                environment: graph.makeInput(value: EnvironmentValues()))
            shape.render(style: style)
            if commit { shape.item = try XCTUnwrap(shape.commitItem()) }
            return shape
        }
    }

    func testObservedStyleTopologyKeepsSeparateAboveBelowOwners() throws {
        // ASSERTIONS shapeStyleRenderedEffects27Observed
        // ASSERTIONS shapeStyleShadowComposition27Observed
        let profiles: [(_ShapeStyle_Pack.Style, String, UInt8)] = [
            (style([drop]), "shadow0(fill)", 0),
            (style([inner]), "shadow1(fill)", 1),
            (style([drop, drop]), "identity(shadow-content,shadow0(fill))", 0),
            (style([drop, inner]), "identity(shadow0(fill),shadow3(fill))", 1),
            (style([inner, drop]), "identity(shadow-content,shadow1(fill))", 1),
            (style([drop, drop, drop]), "identity(identity(shadow-content,shadow-content),shadow0(fill))", 0),
            (style([drop], opacity: 0.4), "identity(clip(shadow6(fill)),opacity(fill))", 1),
            (style([inner], opacity: 0.4), "identity(opacity(fill),compositingGroup(clip(identity(fill,shadow7(fill)))))", 1),
            (style([drop], blend: .multiply), "identity(flattened,blendMode(fill))", 0)
        ]
        for (style, expected, needs) in profiles {
            let shape = try rendered(style, commit: false)
            XCTAssertEqual(outline(shape.item), expected)
            XCTAssertEqual(shape.layerNeeds.rawValue, needs)
        }
        var translucent = style([drop])
        translucent.fill = .color(Color.red.opacity(0.4).resolveHDR(in: .init()))
        XCTAssertEqual(outline(try rendered(translucent, commit: false).item),
            "identity(clip(shadow6(fill)),fill)")
    }

    func testAccumulatorFlushesBlendAndNormalizesFramesBeforeRasterization() throws {
        // ASSERTIONS compositedItemAccumulator27Observed
        var accumulator = CompositedItemAccumulator(version: .init(value: 7),
            contentSeed: .init(decodedValue: 9), options: [])
        var first = try rendered(style([])).item
        first.addEffect(.filter(.shadow(drop)))
        let second = first
        accumulator.add(item: first, blend: .multiply, needsDrawingGroup: true)
        accumulator.add(item: second, blend: .multiply, needsDrawingGroup: false)
        XCTAssertEqual(accumulator.items.count, 0)
        XCTAssertEqual(accumulator.pendingItems.count, 2)
        accumulator.add(item: first, blend: .screen, needsDrawingGroup: false)
        XCTAssertEqual(accumulator.items.count, 1)
        XCTAssertEqual(accumulator.pendingItems.count, 1)
        XCTAssertTrue(accumulator.hasBlending)
        XCTAssertFalse(accumulator.drawingGroup)
        XCTAssertEqual(accumulator.items[0].frame, CGRect(x: 28, y: 23, width: 48, height: 40))
        guard case let .effect(.blendMode(.multiply), blended) = accumulator.items[0].value,
              case let .content(content) = blended.items[0].value,
              case let .flattened(list, origin, options) = content.value else {
            return XCTFail("missing blend around the drawing group")
        }
        XCTAssertEqual(origin, CGPoint(x: -2, y: -3))
        XCTAssertTrue(options.isAccelerated)
        XCTAssertEqual(content.seed, .init(decodedValue: 9))
        XCTAssertEqual(list.items[0].frame.origin, .zero)
        accumulator.commitPendingItems()
        XCTAssertEqual(accumulator.items.count, 2)
        XCTAssertTrue(accumulator.pendingItems.isEmpty)
        XCTAssertEqual(accumulator.currentBlend, .screen)
        XCTAssertTrue(accumulator.hasBlending)
    }

    func testCompositionKeepsOwnerFrameAndDrawingGroupExpandsItsExtent() throws {
        // ASSERTIONS compositedItemAccumulator27Observed
        var owner = try rendered(style([])).item
        var outside = owner
        outside.frame = CGRect(x: 10.5, y: 20.5, width: 36, height: 28)
        owner.composite(outside, above: false)
        XCTAssertEqual(owner.frame, frame)
        guard case let .effect(.identity, list) = owner.value else { return XCTFail() }
        XCTAssertEqual(list.items.map(\.frame.origin), [CGPoint(x: -19.5, y: -5.5), .zero])
        owner.addDrawingGroup(contentSeed: .init(decodedValue: 4))
        XCTAssertEqual(owner.frame, CGRect(x: 10, y: 20, width: 56, height: 34))
        guard case let .content(content) = owner.value,
              case let .flattened(_, origin, _) = content.value else { return XCTFail() }
        XCTAssertEqual(origin, CGPoint(x: -20, y: -6))
    }

    func testCommitAppliesBlendAfterInterpolatorAndResetsRendererState() throws {
        // ASSERTIONS shapeStyleRenderedEffects27Observed
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let group = _ShapeStyle_InterpolatorGroup()
            var shape = _ShapeStyle_RenderedShape(shape: .path(Path(frame), FillStyle()),
                contentSeed: .init(decodedValue: 1), frame: frame, options: [],
                environment: graph.makeInput(value: EnvironmentValues()))
            shape.interpolatorData = (group, 2)
            shape.render(style: style([], blend: .multiply))
            XCTAssertEqual(outline(try XCTUnwrap(shape.commitItem())), "blendMode(interpolator(fill))")
            XCTAssertEqual(shape.blendMode, .normal)
            XCTAssertEqual(shape.opacity, 1)
            XCTAssertTrue(shape.layerNeeds.isEmpty)
            XCTAssertNil(shape.interpolatorData)
            XCTAssertEqual(shape.item.frame, frame)
            XCTAssertNil(shape.commitItem())
        }
    }

    func testShadowBackendEvaluatesRetainedContentsOnce() {
        let viewport = CGRect(x: 0, y: 0, width: 96, height: 80)
        for shadow in [drop, inner] {
            let context = GraphicsContext(recording: RBDisplayList(viewport: viewport),
                environment: .init(), inputs: .init(sceneResources: SceneResources(),
                    viewport: viewport, contentScaleFactor: 1, resourceCommandQueue: nil))
            var calls = 0
            GraphicsFilter.shadow(shadow).draw(in: context) { context in
                calls += 1
                context.fill(Path(self.frame), with: .color(.red))
            }
            XCTAssertEqual(calls, 1, "Raster passes must reuse the retained source without revisiting renderer callbacks")
            XCTAssertFalse(context.recording!.isEmpty)
        }
    }

    func testPublicShadowFillReachesTheSharedMetalConsumer() throws {
        // ASSERTIONS shapeStyleShadowProducer27Observed
        let color = Color(.sRGBLinear, red: 0.8, green: 0.1, blue: 0.2)
        let shadow = ShadowStyle.drop(color: .green.opacity(0.7), radius: 2, x: 4, y: 3)
        let host = CompositionHost(Rectangle().fill(color.shadow(shadow)).frame(width: 36, height: 28))
        let list = try host.list()
        let actual = try pixels(list.items, resources: host.rendererHost.sceneResources)
        let expected = try pixels([rendered(style([drop])).item])
        XCTAssertEqual(actual, expected)
    }

    func testImplicitPublicShadowCopiesForegroundAndOuterOpacityForMetal() throws {
        // ASSERTIONS shapeStyleShadowProducer27Observed
        // ASSERTIONS shapeStyleImplicitCopy27Observed
        // ASSERTIONS shapeStyleOpacityProducer27Observed
        let color = Color(.sRGBLinear, red: 0.8, green: 0.1, blue: 0.2)
        let shadow = ShadowStyle.drop(color: .green.opacity(0.7), radius: 2, x: 4, y: 3)
        let host = CompositionHost(Rectangle().fill(.shadow(shadow).opacity(0.4))
            .frame(width: 36, height: 28).foregroundStyle(color))
        let list = try host.list()
        let actual = try pixels(list.items, resources: host.rendererHost.sceneResources)
        var resolved = style([drop], opacity: 0.4)
        resolved.effects[0].opacity = 0.4
        let expected = try pixels([rendered(resolved).item])
        XCTAssertEqual(actual, expected)
    }

    func testMetalDrawingGroupPreservesPlacementAndShadowOutsideOriginalFrame() throws {
        // ASSERTIONS shapeStyleShadowComposition27Observed
        let direct = try rendered(style([drop])).item
        var grouped = direct
        grouped.addDrawingGroup(contentSeed: .init(decodedValue: 9))
        let first = try pixels([direct])
        let second = try pixels([grouped])
        XCTAssertGreaterThan(first[(40 * 96 + 40) * 4 + 3], 250)
        XCTAssertGreaterThan(first[(55 * 96 + 68) * 4 + 3], 0)
        XCTAssertGreaterThan(second[(55 * 96 + 68) * 4 + 3], 0)
        XCTAssertEqual(second[(10 * 96 + 10) * 4 + 3], 0)
        let a = first.enumerated().filter { $0.offset % 4 == 3 }.map { Int($0.element) }
        let b = second.enumerated().filter { $0.offset % 4 == 3 }.map { Int($0.element) }
        XCTAssertLessThan(zip(a, b).map { abs($0 - $1) }.reduce(0, +), 1200)
    }

    func testMetalDrawingGroupTransformsPreserveLocalRasterContent() throws {
        var item = try rendered(style([drop])).item
        item.addDrawingGroup(contentSeed: .init(decodedValue: 9))
        var list = DisplayList()
        list.items = [item]
        list.interpolationBounds = item.frame
        for transform in [CGAffineTransform(translationX: 5, y: 4),
                          CGAffineTransform(translationX: 18, y: 5).rotated(by: 0.12).scaledBy(x: 0.8, y: 0.9)] {
            let expected = try pixels(list.items, transform: transform)
            let transformed = list.transformed(by: transform)
            let actual = try pixels(transformed.items)
            let differences = zip(expected, actual).map { abs(Int($0) - Int($1)) }
            XCTAssertLessThan(differences.reduce(0, +), 1200)
            let materialized = transformed.materializingInterpolationContents()
            XCTAssertEqual(try pixels(materialized.items), actual)
        }
    }

    func testMetalInnerShadowKeepsCoverageAndTintsOnlyInside() throws {
        // ASSERTIONS shapeStyleShadowComposition27Observed
        let base = try pixels([rendered(style([])).item])
        let inner = try pixels([rendered(style([inner])).item])
        XCTAssertEqual(inner[(20 * 96 + 25) * 4 + 3], 0)
        XCTAssertGreaterThan(inner[(40 * 96 + 40) * 4 + 3], 250)
        XCTAssertNotEqual(Array(base[(28 * 96 + 63) * 4..<(28 * 96 + 63) * 4 + 3]),
                          Array(inner[(28 * 96 + 63) * 4..<(28 * 96 + 63) * 4 + 3]))
    }

    func testMountedTextUsesMovedAlphaMaskAndReplaysIntoMetal() throws {
        let device = try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        // ASSERTIONS shapeStyleRenderedEffects27Observed
        let host = CompositionHost(Text("Abc").font(.system(size: 24))
            .frame(width: 96, height: 80))
        let source = try host.list()
        var text: DisplayList.Content.TextValue?
        visit(source) { item in
            if case let .content(content) = item.value,
               case let .text(value) = content.value { text = value }
        }
        let mounted = try XCTUnwrap(text)
        let list = try host.graph.data.withCurrent {
            var environment = EnvironmentValues()
            environment.foregroundStyleLevels = .init(primary: AnyShapeStyle(Color.white.shadow(.drop(radius: 0))))
            var helper = ResolvedTextHelper(includeDefaultAttributes: true, allowsKeyColors: true)
            let prepared = try XCTUnwrap(helper.resolve(Text("Abc").font(.system(size: 24)),
                with: environment, sizeFitting: false))
            let view = StyledTextContentView(text: prepared, renderer: nil)
            var renderer = _ShapeStyle_RenderedShape(shape: .text(view),
                contentSeed: .init(decodedValue: 9), frame: mounted.frame,
                options: [], environment: host.graph.data.graph.makeInput(value: EnvironmentValues()))
            var layers = _ShapeStyle_RenderedLayers(group: _ShapeStyle_InterpolatorGroup())
            renderer.renderItem(name: .foreground,
                styles: _ShapeStyle_Pack(styles: [(.init(.foreground, 0), style([drop, inner]))]),
                layers: &layers)
            return layers.commit(shape: &renderer)
        }
        var drawings: [RBMovedDisplayListContents] = []
        visit(list) { item in
            if case let .content(content) = item.value,
               case let .drawing(contents, _, options) = content.value,
               let moved = contents as? RBMovedDisplayListContents {
                XCTAssertTrue(options.alphaOnly)
                drawings.append(moved)
            }
        }
        XCTAssertFalse(drawings.isEmpty)
        XCTAssertTrue(drawings.contains { !$0.isEmpty })
        let data = try pixels(list.items, resources: host.rendererHost.sceneResources, device: device)
        XCTAssertGreaterThan(data.enumerated().filter { $0.offset % 4 == 3 }.reduce(0) { $0 + Int($1.element) }, 20000)
        XCTAssertEqual(data[(4 * 96 + 4) * 4 + 3], 0)
    }

    private func outline(_ item: DisplayList.Item) -> String {
        switch item.value {
        case .empty: return "empty"
        case let .effect(effect, list):
            let label: String
            switch effect {
            case .identity: label = "identity"
            case .opacity: label = "opacity"
            case .blendMode: label = "blendMode"
            case let .filter(.shadow(shadow)): label = "shadow\(shadow.kind.rawValue)"
            case .filter: label = "filter"
            case .clip: label = "clip"
            case .mask: label = "mask"
            case .compositingGroup: label = "compositingGroup"
            case .interpolatorLayer: label = "interpolator"
            default: label = "effect"
            }
            return label + "(" + list.items.map(outline).joined(separator: ",") + ")"
        case let .content(content):
            switch content.value {
            case .flattened: return "flattened"
            case .shadow: return "shadow-content"
            case .drawing: return "drawing"
            default: return "fill"
            }
        case .states: return "states"
        }
    }

    private func visit(_ list: DisplayList, body: (DisplayList.Item) -> Void) {
        for item in list.items {
            body(item)
            switch item.value {
            case let .effect(effect, list):
                visit(list, body: body)
                if case let .mask(mask, _) = effect { visit(mask, body: body) }
            case let .content(content):
                if case let .flattened(list, _, _) = content.value { visit(list, body: body) }
            default: break
            }
        }
    }

    private func pixels(_ items: [DisplayList.Item], resources: SceneResources = SceneResources(), device: GraphicsDeviceContext? = nil, transform: CGAffineTransform = .identity) throws -> [UInt8] {
        #if canImport(Metal)
        let device = try XCTUnwrap(device ?? makeGraphicsDeviceContext(api: .metal))
        let queue = try XCTUnwrap(device.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let size = CGSize(width: 96, height: 80)
        var context = try XCTUnwrap(GraphicsContext(sceneResources: resources, environment: .init(),
            viewport: CGRect(origin: .zero, size: size), contentOffset: .zero, contentScaleFactor: 1,
            resolution: size, commandBuffer: commands))
        context.clear(with: .clear)
        var list = DisplayList()
        list.items = items
        context.concatenate(transform)
        list.draw(in: context)
        let done = expectation(description: "style composition readback")
        commands.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [done], timeout: 15)
        let buffer = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(buffer.contents()), count: 96 * 80 * 4))
        #else
        throw XCTSkip("Metal is required for this rendering boundary")
        #endif
    }
}

private final class CompositionHost {
    let rendererHost = TestViewRendererHost()
    let graph: ViewGraph
    init<V: View>(_ view: V) {
        graph = ViewGraph(rootViewType: V.self, content: view, rendererHost: rendererHost)
        rendererHost.storage = graph
        graph.setSize(CGSize(width: 96, height: 80))
    }
    func list() throws -> DisplayList {
        graph.updateOutputs(at: .zero)
        return try graph.data.withCurrent { try XCTUnwrap(graph.displayList()) }
    }
}
