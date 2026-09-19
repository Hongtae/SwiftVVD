import Foundation
import XCTest
import VVD
@testable import VUI

final class GraphicsContextPrimitiveTests: XCTestCase {
    private let size = CGSize(width: 256, height: 192)
    private let bases: [(String, CGAffineTransform)] = [
        ("identity", .identity),
        ("scale", .init(a: 1.5, b: 0, c: 0, d: 0.75, tx: 8, ty: 6)),
        ("quarter", .init(a: 0, b: 1, c: -1, d: 0, tx: 128, ty: 0)),
        ("shear", .init(a: 1.25, b: 0.25, c: 0.5, d: 0.75, tx: 8, ty: 4))
    ]

    private func device() throws -> GraphicsDeviceContext {
        #if canImport(Metal)
        return try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        #else
        throw XCTSkip("Metal is required for this readback fixture")
        #endif
    }

    private func recording() -> GraphicsContext {
        GraphicsContext(recording: RBDisplayList(viewport: CGRect(origin: .zero, size: size)),
            environment: EnvironmentValues(), inputs: .init(sceneResources: SceneResources(),
                viewport: CGRect(origin: .zero, size: size), contentScaleFactor: 1, resourceCommandQueue: nil))
    }

    private func render(_ device: GraphicsDeviceContext, scale: CGFloat,
                        draw: (inout GraphicsContext) -> Void) throws -> [UInt8] {
        let resolution = size * scale
        let queue = try XCTUnwrap(device.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        var context = try XCTUnwrap(GraphicsContext(sceneResources: SceneResources(), environment: .init(),
            viewport: CGRect(origin: .zero, size: resolution), contentOffset: .zero,
            contentScaleFactor: scale, resolution: resolution, commandBuffer: commands))
        context.clear(with: .clear)
        draw(&context)
        let done = expectation(description: "primitive readback")
        commands.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [done], timeout: 10)
        let data = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(data.contents()),
            count: Int(resolution.width * resolution.height) * 4))
    }

    private func path(_ name: String) -> Path {
        let rect = CGRect(x: 32, y: 24, width: 48, height: 24)
        switch name {
        case "small": return Path(CGRect(x: 32, y: 24, width: 8, height: 6))
        case "circular": return Path(roundedRect: rect, cornerRadius: 4, style: .circular)
        case "circle": return Path(ellipseIn: CGRect(x: 32, y: 24, width: 24, height: 24))
        default: return Path(rect)
        }
    }

    private func draw(_ context: inout GraphicsContext, basis: CGAffineTransform, order: String,
                      shape: String, radius: CGFloat) {
        context.opacity = 0.75
        if order != "item" { context.concatenate(basis) }
        context.addFilter(.shadow(color: .black.opacity(0.5), radius: radius, x: 3, y: 2))
        if order == "item" { context.concatenate(basis) }
        if order == "style" { context.concatenate(basis.inverted()) }
        context.fill(path(shape), with: .color(.sRGB, red: 1,
            green: 0.2196044921875, blue: 0.2353515625, opacity: 0.6))
    }

    // ASSERTIONS recordedPrimitiveShadowCoverage27Observed
    // ASSERTIONS recordedPrimitiveShadowPayload27Observed
    func testPrimitiveRadiusSmallShapeAlphaAndRejectedGeometry() throws {
        let rectangle = try XCTUnwrap(FilledPrimitive(path: path("rect"), color: .init(
            colorSpace: .sRGB, red: 1, green: 0, blue: 0, opacity: 0.6)))
        let black = Color.black.opacity(0.5).resolve(in: .init())
        let large = try XCTUnwrap(rectangle.shadow(radius: 12, color: black,
            itemTransform: .identity, styleTransform: .identity, offset: .zero))
        XCTAssertEqual(large.primitive.cornerRadius, 12)
        XCTAssertEqual(large.primitive.color.w, 0.25732421875)
        let shear = bases[3].1
        for (item, style, radius) in [(shear, CGAffineTransform.identity, Float(2.6299822330474854)),
                                     (.identity, shear, Float(2.176142692565918))] {
            let shadow = try XCTUnwrap(rectangle.shadow(radius: 2, color: black,
                itemTransform: item, styleTransform: style, offset: CGPoint(x: 3, y: 2)))
            XCTAssertEqual(shadow.primitive.blurRadius, radius, accuracy: 0.000001)
            XCTAssertEqual(shadow.transform.tx - item.tx, style.a * 3 + style.c * 2)
            XCTAssertEqual(shadow.transform.ty - item.ty, style.b * 3 + style.d * 2)
        }
        XCTAssertNil(FilledPrimitive(path: Path(ellipseIn: CGRect(x: 0, y: 0, width: 48, height: 24)), color: black))
        XCTAssertNil(FilledPrimitive(path: Path(roundedRect: CGRect(x: 0, y: 0, width: 48, height: 24),
            cornerRadius: 4, style: .continuous), color: black))
        var context = recording()
        context.addFilter(.shadow(radius: 0))
        XCTAssertNil(context.analyticShadowPrimitive(path("rect"), shading: .color(.red), style: FillStyle()))
    }

    // ASSERTIONS recordedPrimitiveFragment27Observed
    // ASSERTIONS recordedAffineFilterDrawing27Observed
    // ASSERTIONS recordedAffineStyleCopy27Observed
    func testPrimitiveMetalReplayPreservesCapturedCoordinatesAndDensity() throws {
        let device = try device()
        let output = ProcessInfo.processInfo.environment["VUI_PRIMITIVE_CAPTURE"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for (name, basis) in bases {
            for order in ["both", "item", "style"] {
                for shape in ["rect", "small", "circular", "circle"] {
                    for radius: CGFloat in [0, 2, 12] {
                        var source = recording()
                        draw(&source, basis: basis, order: order, shape: shape, radius: radius)
                        let contents = try XCTUnwrap(source.recording).moveContents()
                        let originalStyle = try XCTUnwrap(contents.items.first?.state.style)
                        let originalTransform = originalStyle.transform
                        for density: CGFloat in [1, 2] {
                            let label = "\(name)-\(order)-\(shape)-\(Int(radius))-\(Int(density))"
                            let pixels = try render(device, scale: density) { contents.draw(in: $0) }
                            let direct = try render(device, scale: density) {
                                draw(&$0, basis: basis, order: order, shape: shape, radius: radius)
                            }
                            XCTAssertTrue(pixels == direct, label)
                            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }, label)
                            XCTAssertEqual(originalStyle.transform, originalTransform)
                            if let output { try Data(pixels).write(to: output.appendingPathComponent(label + ".rgba")) }
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS recordedAffineEffectCoordinates27Observed
    func testAffineBoundsAndColorCopiesKeepStyleCoordinates() throws {
        let expected: [String: CGRect] = [
            "both": CGRect(x: 52.1, y: 21.3, width: 88.8, height: 26.4),
            "item": CGRect(x: 53.4, y: 20.4, width: 83.2, height: 29.2),
            "style": CGRect(x: 28.1, y: 21.3, width: 64.8, height: 32.4)
        ]
        for order in ["both", "item", "style"] {
            var context = recording()
            draw(&context, basis: bases[1].1, order: order, shape: "rect", radius: 2)
            let source = try XCTUnwrap(context.recording).moveContents()
            let bounds = try XCTUnwrap(expected[order])
            for (value, wanted) in zip([source.boundingRect.minX, source.boundingRect.minY,
                                        source.boundingRect.width, source.boundingRect.height],
                                       [bounds.minX, bounds.minY, bounds.width, bounds.height]) {
                XCTAssertEqual(value, wanted, accuracy: 0.00002, order)
            }
            let predicate = RBDisplayListPredicate()
            predicate.addCondition(fillColor: SIMD4(repeating: -32768), colorSpace: .sRGB)
            let copy = try XCTUnwrap(predicate.copyFilteredDisplayList(source) as? RBMovedDisplayListContents)
            XCTAssertEqual(copy.boundingRect, source.boundingRect)
            XCTAssertFalse(copy.items[0].state.style === source.items[0].state.style)
            XCTAssertEqual(copy.items[0].state.style?.transform, source.items[0].state.style?.transform)
        }
    }

    private struct EffectRenderer: TextRenderer {
        let basis: CGAffineTransform
        let before: Bool
        let blur: Bool
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            if before { context.concatenate(basis) }
            context.addFilter(blur ? .blur(radius: 2) : .shadow(color: .black.opacity(0.5), radius: 2, x: 3, y: 2))
            if !before { context.concatenate(basis) }
            context.fill(Path(CGRect(x: 32, y: 24, width: 48, height: 24)), with: .color(.red))
            for line in layout { context.draw(line) }
        }
    }

    private func renderer(_ renderer: EffectRenderer, environment: EnvironmentValues) throws -> TextRendererBoxBase {
        let graph = _AGGraph()
        return try _AGGraph.withCurrent(graph) {
            let modifier = _TextRendererViewModifier(renderer: renderer)
            let attribute = graph.makeInput(value: modifier)
            var inputs = _ViewInputs(base: _GraphInputs(time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(value: environment), transaction: graph.makeInput(value: Transaction())),
                customInputs: PropertyList(), preferences: PreferencesInputs(keys: PreferenceKeys(),
                    hostKeys: graph.makeInput(value: PreferenceKeys())),
                transform: graph.makeInput(value: ViewTransform()), position: graph.makeInput(value: CGPoint.zero),
                containerPosition: graph.makeInput(value: CGPoint.zero),
                size: graph.makeInput(value: ViewSize(width: 0, height: 0)), safeAreaInsets: OptionalAttribute(),
                containerSize: OptionalAttribute(), stackOrientation: nil)
            type(of: modifier)._makeViewInputs(modifier: _GraphValue(_attribute: attribute), inputs: &inputs)
            return try XCTUnwrap(inputs[TextRendererInput.self].value)
        }
    }

    // ASSERTIONS recordedAffineTextRenderer27Observed
    // ASSERTIONS recordedAffineFilterKernel27Observed
    func testTextRendererGlyphAndPrimitiveOwnersSurviveAffineColorOperationsOnMetal() throws {
        let device = try device()
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let scales = RBDisplayList.Style.axisScales(bases[1].1)
        XCTAssertEqual(scales * 2, SIMD2<Float>(3, 1.5))
        XCTAssertEqual(RBDisplayList.Style.axisScales(bases[1].1.concatenating(bases[2].1)), scales)
        for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            for (_, basis) in bases {
                for before in [false, true] {
                    for blur in [false, true] {
                        var context = recording()
                        context.environment.font = .system(size: 16)
                        context.environment.defaultFontRenderingMode = mode
                        let styled = context.resolve(Text(verbatim: "Abc")).resolved
                        let box = try renderer(EffectRenderer(basis: basis, before: before, blur: blur),
                                               environment: context.environment)
                        let contents = styled.makeRBDisplayList(for: size, renderer: box, deviceScale: 1,
                            environment: context.environment, inputs: context.storage.inputs)
                        let items = recordedItems(in: contents)
                        XCTAssertTrue(items.contains { if case .text = $0.contents { return true }; return false })
                        XCTAssertTrue(items.contains { if case .fill = $0.contents { return true }; return false })
                        let replacement = RBDisplayListTransform()
                        replacement.addColorReplacement(from: SIMD4(repeating: -32768),
                            to: SIMD4(1, 0, 0, 1), colorSpace: .sRGB)
                        let replaced = replacement.copyApplyingToDisplayList(contents)
                        let glyphs = RBMovedDisplayListContents(items: recordedItems(in: replaced).filter {
                            if case .text = $0.contents { return true }; return false
                        })
                        for scale: CGFloat in [1, 2] {
                            let first = try render(device, scale: scale) { replaced.draw(in: $0) }
                            let replay = recording()
                            replaced.draw(in: replay)
                            let copy = try XCTUnwrap(replay.recording).moveContents()
                            let second = try render(device, scale: scale) { copy.draw(in: $0) }
                            XCTAssertTrue(first == second)
                            XCTAssertTrue(stride(from: 3, to: first.count, by: 4).contains { first[$0] != 0 })
                            let glyphPixels = try render(device, scale: scale) { glyphs.draw(in: $0) }
                            XCTAssertTrue(stride(from: 0, to: glyphPixels.count, by: 4).contains {
                                glyphPixels[$0] > 0 && glyphPixels[$0 + 3] > 0
                            }, "The actual glyph consumer must draw independently of the rectangle")
                        }
                    }
                }
            }
        }
    }
}
