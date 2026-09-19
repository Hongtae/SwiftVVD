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
        let context = try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        if ProcessInfo.processInfo.environment["VUI_PRIMITIVE_FORCE_FLOAT_OUTPUT"] == "1" {
            return GraphicsDeviceContext(device: GraphicsDeviceFeatureMask(context.device, features: []))
        }
        return context
        #else
        throw XCTSkip("Metal is required for this readback fixture")
        #endif
    }

    // ASSERTIONS recordedPrimitiveBlendPrecision27Observed
    func testPrimitiveShaderVariantsRequireBothDeviceFeatures() throws {
        #if canImport(Metal)
        let base = try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        let required: GraphicsDeviceFeatures = [.float16Arithmetic, .float16InputOutput]
        XCTAssertTrue(base.device.features.isSuperset(of: required))
        var retained: [GraphicsPipelineStates] = []
        for features: GraphicsDeviceFeatures in [[], [.float16Arithmetic], [.float16InputOutput], required] {
            let device = GraphicsDeviceFeatureMask(base.device, features: features)
            let queue = try XCTUnwrap(device.makeCommandQueue(flags: .render))
            let pipeline = try XCTUnwrap(GraphicsPipelineStates.sharedInstance(commandQueue: queue))
            let half = features == required
            XCTAssertEqual(pipeline.primitiveOutputUsesFloat16, half)
            XCTAssertTrue((pipeline.device as AnyObject) === device)
            XCTAssertFalse(retained.contains { $0 === pipeline })
            retained.append(pipeline)
            let otherQueue = try XCTUnwrap(device.makeCommandQueue(flags: .render))
            XCTAssertTrue(pipeline === GraphicsPipelineStates.sharedInstance(commandQueue: otherQueue))
            let outputs = device.loadedShaderOutputs.filter {
                $0.key.hasPrefix("primitive_") || $0.key.hasPrefix("plane_color")
            }
            let suffix = half ? "_half.frag" : ".frag"
            XCTAssertEqual(Set(outputs.keys), Set(["plane_color" + suffix,
                "primitive_color" + suffix, "primitive_group" + suffix]))
            for types in outputs.values { XCTAssertEqual(types, [half ? .half4 : .float4]) }
            for shader: _Shader in [.planeColor, .primitiveColor, .primitiveGroup] {
                XCTAssertNotNil(pipeline.renderState(shader: shader, colorFormat: .rgba8Unorm,
                    depthFormat: .invalid, blendState: .premultipliedAlphaBlend, sampleCount: 1))
            }
        }
        // Keeping every instance alive makes cross-device cache reuse observable.
        XCTAssertEqual(retained.count, 4)
        #else
        throw XCTSkip("Metal is required for this shader compilation fixture")
        #endif
    }

    private func recording() -> GraphicsContext {
        GraphicsContext(recording: RBDisplayList(viewport: CGRect(origin: .zero, size: size)),
            environment: EnvironmentValues(), inputs: .init(sceneResources: SceneResources(),
                viewport: CGRect(origin: .zero, size: size), contentScaleFactor: 1, resourceCommandQueue: nil))
    }

    private func render(_ device: GraphicsDeviceContext, scale: CGFloat,
                        draw: (inout GraphicsContext) throws -> Void) throws -> [UInt8] {
        let resolution = size * scale
        let queue = try XCTUnwrap(device.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        var context = try XCTUnwrap(GraphicsContext(sceneResources: SceneResources(), environment: .init(),
            viewport: CGRect(origin: .zero, size: resolution), contentOffset: .zero,
            contentScaleFactor: scale, resolution: resolution, commandBuffer: commands))
        context.clear(with: .clear)
        try draw(&context)
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
                            if name == "shear" && order == "both" && shape == "rect" && radius > 0 {
                                let (x, y) = density == 1 ? (120, 41) : (240, 83)
                                XCTAssertEqual(pixels[(y * Int(size.width * density) + x) * 4], 0,
                                               "The source fringe must not extend beyond its mesh: \(label)")
                            }
                            XCTAssertEqual(originalStyle.transform, originalTransform)
                            if let output { try Data(pixels).write(to: output.appendingPathComponent(label + ".rgba")) }
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS recordedPrimitiveIsolation27Observed
    // ASSERTIONS recordedPrimitiveMesh27Observed
    // ASSERTIONS recordedPrimitiveGroupScissor27Observed
    func testPrimitiveMetalIsolatesCoverageAndGroupOpacity() throws {
        let device = try device()
        let output = ProcessInfo.processInfo.environment["VUI_PRIMITIVE_ISOLATION"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let color = Color(.sRGB, red: 1, green: 0.2196044921875, blue: 0.2353515625, opacity: 0.6)
        for (name, basis) in bases where name == "identity" || name == "shear" {
            for shape in ["rect", "small", "circular", "circle"] {
                for radius: CGFloat in [0, 2, 12] {
                    for opacity in [1.0, 0.75] {
                        for density: CGFloat in [1, 2] {
                            var stages: [String: [UInt8]] = [:]
                            for role in ["source", "shadow", "composite"] {
                                let label = "\(name)-\(shape)-\(Int(radius))-\(Int(opacity * 100))-\(role)-\(Int(density))"
                                let pixels = try render(device, scale: density) { context in
                                    context.opacity = opacity
                                    context.concatenate(basis)
                                    if role != "source" {
                                        context.addFilter(.shadow(color: .black.opacity(0.5), radius: radius,
                                            x: 3, y: 2, options: role == "shadow" ? .shadowOnly : []))
                                    }
                                    // Exercise the encoder directly to isolate the source and the
                                    // still-gated zero-radius branch without widening public dispatch.
                                    let primitive = try XCTUnwrap(FilledPrimitive(path: path(shape), color: color.resolve(in: .init())))
                                    if let group = GraphicsContext.PrimitiveShadowGroup(source: primitive, context: context) {
                                        group.draw(in: context)
                                    } else {
                                        let pass = try XCTUnwrap(context.beginRenderPass(enableStencil: false, enableMSAA: false))
                                        XCTAssertTrue(context.encodePrimitive(renderPass: pass, primitive: primitive,
                                                                              transform: context.transform))
                                        pass.end()
                                        context.drawSource(primitive: primitive)
                                    }
                                }
                                stages[role] = pixels
                                XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }, label)
                                if role == "shadow" {
                                    XCTAssertTrue(stride(from: 0, to: pixels.count, by: 4).allSatisfy {
                                        pixels[$0] == 0 && pixels[$0 + 1] == 0 && pixels[$0 + 2] == 0
                                    }, label)
                                }
                                if name == "shear" && shape == "rect" && role == "source" {
                                    let points = density == 1 ? [(120, 41), (71, 48)] : [(240, 83), (143, 96)]
                                    for (x, y) in points {
                                        XCTAssertEqual(pixels[(y * Int(size.width * density) + x) * 4 + 3], 0,
                                                       "The primitive mesh must not extend its diagonal fringe: \(label)")
                                    }
                                }
                                if radius == 0 && opacity == 0.75 && shape == "rect" && role == "composite" {
                                    let point: (Int, Int)? = name == "shear" && density == 1 ? (59, 29)
                                        : name == "identity" && density == 2 ? (166, 51) : nil
                                    if let (x, y) = point {
                                        let offset = (y * Int(size.width * density) + x) * 4
                                        XCTAssertEqual(Array(pixels[offset..<offset + 4]), [0, 0, 0, 0],
                                            "Group bounds must exclude the outer mesh fringe: \(label)")
                                    }
                                }
                                if let output { try Data(pixels).write(to: output.appendingPathComponent(label + ".rgba")) }
                            }
                            if opacity == 1 {
                                let source = stages["source"]!, shadow = stages["shadow"]!, composite = stages["composite"]!
                                XCTAssertTrue(stride(from: 3, to: source.count, by: 4).allSatisfy {
                                    composite[$0] >= max(source[$0], shadow[$0])
                                }, "Composition must retain both isolated layers at full opacity")
                            }
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS recordedPrimitiveIntegralBounds27Observed
    func testPrimitivePreservesFractionalRectangleCornerCoverage() throws {
        let device = try device()
        let output = ProcessInfo.processInfo.environment["VUI_PRIMITIVE_PLANE_EDGES"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let color = Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 0.625).resolve(in: .init())
        for (name, offset) in [("below-integral-source", CGFloat(-0.004)),
                               ("near-integral-source", CGFloat(0.004))] {
            for density: CGFloat in [1, 2] {
                let primitive = try XCTUnwrap(FilledPrimitive(path:
                    Path(CGRect(x: 80 + offset, y: 40, width: 144, height: 120)), color: color))
                let pixels = try render(device, scale: density) { context in
                    let pass = try XCTUnwrap(context.beginRenderPass(enableStencil: false, enableMSAA: false))
                    XCTAssertTrue(context.encodePrimitive(renderPass: pass, primitive: primitive, transform: .identity))
                    pass.end()
                    context.drawSource(primitive: primitive)
                }
                let width = Int(size.width * density)
                let corners: [UInt8] = name.hasPrefix("below") ? [25, 24]
                    : density == 1 ? [0, 0] : [24, 25]
                for y in [Int(40 * density) - 1, Int(160 * density)] {
                    for (x, alpha) in zip([Int(80 * density) - 1, Int(224 * density)], corners) {
                        let index = (y * width + x) * 4
                        XCTAssertEqual(Array(pixels[index..<index + 4]), [0, alpha, 0, alpha],
                            "Fractional rectangle corner: \(name), density \(density), (\(x), \(y))")
                    }
                }
                if let output {
                    try Data(pixels).write(to: output.appendingPathComponent("\(name)-\(Int(density)).rgba"))
                }
            }
        }
    }

    // ASSERTIONS recordedPrimitiveGroupExecution27Observed
    // ASSERTIONS recordedPrimitiveGroupScissor27Observed
    // ASSERTIONS recordedPrimitiveSpillAttachments27Observed
    func testPrimitiveGroupsPreserveBackdropAndSiblingLifetime() throws {
        let device = try device()
        let output = ProcessInfo.processInfo.environment["VUI_PRIMITIVE_GROUPS"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let color = Color(.sRGB, red: 1, green: 0.2196044921875, blue: 0.2353515625, opacity: 0.6)
        for (name, basis) in bases where name == "identity" || name == "shear" {
            let controls: [(String, Double)] = [0.25, 0.5, 0.75, 0.999, 0.9999, 1].flatMap {
                [("single", $0), ("backdrop", $0)]
            } + [("siblings", 0.75)]
            for (kind, opacity) in controls {
                let draw = { (root: inout GraphicsContext) in
                    if kind != "single" {
                        root.fill(Path(CGRect(origin: .zero, size: self.size)),
                            with: .color(.sRGB, red: 0.25, green: 0.5, blue: 1, opacity: 0.5))
                    }
                    var first = root
                    first.opacity = opacity
                    first.concatenate(basis)
                    first.addFilter(.shadow(color: .black.opacity(0.5), radius: 2, x: 3, y: 2))
                    first.fill(self.path("rect"), with: .color(color))
                    if kind == "siblings" {
                        var second = root
                        second.translateBy(x: 20, y: 12)
                        second.opacity = 0.5
                        second.concatenate(basis)
                        second.addFilter(.shadow(color: .black.opacity(0.5), radius: 12, x: 3, y: 2))
                        second.fill(self.path("circle"), with: .color(color))
                        root.fill(Path(CGRect(x: 80, y: 40, width: 144, height: 120)),
                            with: .color(.sRGB, red: 0, green: 1, blue: 0, opacity: 0.625))
                    }
                }
                var source = recording()
                draw(&source)
                let contents = try XCTUnwrap(source.recording).moveContents()
                for density: CGFloat in [1, 2] {
                    let label = "\(name)-\(kind)-\(Int((opacity * 10000).rounded()))-\(Int(density))"
                    var scratch: Texture?
                    let pixels = try render(device, scale: density) {
                        draw(&$0)
                        scratch = $0.sourceTexture
                    }
                    let replay = try render(device, scale: density) { contents.draw(in: $0) }
                    XCTAssertTrue(pixels == replay, label)
                    if kind == "single" && Float16(opacity) < 1 {
                        let buffer = try XCTUnwrap(device.makeCPUAccessible(texture: try XCTUnwrap(scratch)))
                        let bytes = UnsafeRawBufferPointer(start: try XCTUnwrap(buffer.contents()),
                            count: Int(size.width * size.height * density * density) * 4)
                        XCTAssertTrue(bytes.allSatisfy { $0 == 0 }, "Completed group must release cleared scratch: \(label)")
                    }
                    let width = Int(size.width * density)
                    let untouched = (Int(180 * density) * width + Int(240 * density)) * 4
                    XCTAssertEqual(Array(pixels[untouched..<untouched + 4]),
                        kind == "single" ? [0, 0, 0, 0] : [32, 64, 128, 128], label)
                    if kind == "siblings" {
                        let after = (Int(150 * density) * width + Int(210 * density)) * 4
                        XCTAssertEqual(Array(pixels[after..<after + 4]), [12, 183, 48, 207], label)
                    }
                    if name == "identity" && kind == "single" && opacity == 0.75 && density == 1 {
                        XCTAssertEqual(pixels[(22 * width + 36) * 4 + 3], 1,
                            "Group opacity must be applied after child accumulation")
                    }
                    if let output { try Data(pixels).write(to: output.appendingPathComponent(label + ".rgba")) }
                }
            }
        }
    }

    // ASSERTIONS recordedPrimitiveBlendPrecision27Observed
    // ASSERTIONS recordedPrimitiveGroupExecution27Observed
    func testPrimitiveSiblingStagesPreserveUnaffectedPixels() throws {
        let output = ProcessInfo.processInfo.environment["VUI_PRIMITIVE_SIBLING_STAGES"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let device = try device()
        let color = Color(.sRGB, red: 1, green: 0.2196044921875, blue: 0.2353515625, opacity: 0.6)
        for (name, basis) in bases where name == "identity" || name == "shear" {
            for density: CGFloat in [1, 2] {
                var stages: [String: [UInt8]] = [:]
                for stage in ["prefix-first", "prefix-second", "shared", "overlay"] {
                    var sourceTexture: Texture?
                    let pixels = try render(device, scale: density) { root in
                        let scratch = try XCTUnwrap(root.beginRenderPass(enableStencil: false))
                        scratch.end()
                        if stage != "overlay" {
                            root.fill(Path(CGRect(origin: .zero, size: self.size)),
                                with: .color(.sRGB, red: 0.25, green: 0.5, blue: 1, opacity: 0.5))
                            var first = root
                            first.opacity = 0.75
                            first.concatenate(basis)
                            first.addFilter(.shadow(color: .black.opacity(0.5), radius: 2, x: 3, y: 2))
                            first.fill(self.path("rect"), with: .color(color))
                            if stage != "prefix-first" {
                                var second = root
                                second.translateBy(x: 20, y: 12)
                                second.opacity = 0.5
                                second.concatenate(basis)
                                second.addFilter(.shadow(color: .black.opacity(0.5), radius: 12, x: 3, y: 2))
                                second.fill(self.path("circle"), with: .color(color))
                            }
                        }
                        if stage == "shared" || stage == "overlay" {
                            root.fill(Path(CGRect(x: 80, y: 40, width: 144, height: 120)),
                                with: .color(.sRGB, red: 0, green: 1, blue: 0, opacity: 0.625))
                        }
                        sourceTexture = root.sourceTexture
                    }
                    stages[stage] = pixels
                    if let output {
                        let label = "\(name)-\(Int(density))-\(stage)"
                        try Data(pixels).write(to: output.appendingPathComponent(label + ".rgba"))
                        if stage == "shared" || stage == "overlay" {
                            let data = try XCTUnwrap(device.makeCPUAccessible(texture: try XCTUnwrap(sourceTexture)))
                            let bytes = Data(bytes: try XCTUnwrap(data.contents()), count: pixels.count)
                            XCTAssertTrue(bytes.allSatisfy { $0 == 0 }, "Direct plane must leave cleared scratch untouched")
                            try bytes.write(to: output.appendingPathComponent(label + "-source.rgba"))
                        }
                    }
                }
                let first = stages["prefix-first"]!, second = stages["prefix-second"]!
                let final = stages["shared"]!, overlay = stages["overlay"]!
                let width = Int(size.width * density)
                var preservesOutside = true
                for offset in stride(from: 0, to: final.count, by: 4) {
                    let x = offset / 4 % width, y = offset / 4 / width
                    if x < Int(80 * density) || x >= Int(224 * density) ||
                        y < Int(40 * density) || y >= Int(160 * density) {
                        preservesOutside = preservesOutside &&
                            final[offset..<offset + 4] == second[offset..<offset + 4] &&
                            overlay[offset..<offset + 4].allSatisfy { $0 == 0 }
                    }
                }
                XCTAssertTrue(preservesOutside, "Later drawing must preserve pixels outside its bounds: \(name)-\(density)")
                XCTAssertTrue(stride(from: 3, to: final.count, by: 4).allSatisfy {
                    second[$0] >= first[$0] && final[$0] >= second[$0]
                }, "Source-over drawing must retain accumulated coverage: \(name)-\(density)")
            }
        }
    }

    // ASSERTIONS recordedPrimitiveBlendPrecision27Observed
    func testPrimitiveFragmentPrecisionReadbacks() throws {
        let output = ProcessInfo.processInfo.environment["VUI_PRIMITIVE_NUMERICS"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let device = try device()
        for (name, basis) in bases where name == "identity" || name == "shear" {
            for density: CGFloat in [1, 2] {
                for format: PixelFormat in [.rgba8Unorm, .rgba16Float] {
                    for role in ["shadow", "source", "layer"] {
                        var texture: Texture?
                        _ = try render(device, scale: density) { context in
                            context.opacity = 0.75
                            context.concatenate(basis)
                            context.addFilter(.shadow(color: .black.opacity(0.5), radius: 2, x: 3, y: 2))
                            let color = Color(.sRGB, red: 1, green: 0.2196044921875, blue: 0.2353515625, opacity: 0.6)
                            let source = try XCTUnwrap(FilledPrimitive(path: self.path("rect"), color: color.resolve(in: .init())))
                            let group = try XCTUnwrap(GraphicsContext.PrimitiveShadowGroup(source: source, context: context))
                            let target = try XCTUnwrap(device.device.makeTexture(descriptor: TextureDescriptor(
                                textureType: .type2D, pixelFormat: format, width: Int(self.size.width * density),
                                height: Int(self.size.height * density), usage: [.renderTarget, .copySource])))
                            texture = target
                            let pass = try XCTUnwrap(context.beginRenderPass(viewport: context.viewport, renderTarget: target,
                                loadAction: .clear, clearColor: .clear, useStencil: false, useMSAA: false))
                            pass.encoder.setScissorRect(try XCTUnwrap(group.scissor))
                            if role != "source" {
                                XCTAssertTrue(context.encodePrimitive(renderPass: pass, primitive: group.shadow,
                                    transform: group.shadowTransform, blendState: .premultipliedAlphaBlend))
                            }
                            if role != "shadow" {
                                XCTAssertTrue(context.encodePrimitive(renderPass: pass, primitive: group.source,
                                    transform: group.sourceTransform, blendState: .premultipliedAlphaBlend))
                            }
                            pass.end()
                        }
                        let data = try XCTUnwrap(device.makeCPUAccessible(texture: try XCTUnwrap(texture)))
                        let isFloat = format == .rgba16Float
                        let bytes = Data(bytes: try XCTUnwrap(data.contents()),
                            count: Int(size.width * size.height * density * density) * (isFloat ? 8 : 4))
                        let label = "\(name)-\(role)-\(Int(density))" + (isFloat ? ".rgba16f" : ".rgba")
                        if name == "shear" && density == 1 && isFloat && role != "layer" {
                            let expected: [(Int, Int, [Float])] = role == "shadow" ? [
                                (127, 52, [0, 0, 0, 0.269775390625]),
                                (129, 55, [0, 0, 0, 0.269775390625]),
                                (129, 59, [0, 0, 0, 0.25146484375])
                            ] : [
                                (127, 52, [0.062042236328125, 0.01363372802734375, 0.0146026611328125, 0.062042236328125]),
                                (129, 55, [0.0618896484375, 0.0135955810546875, 0.0145721435546875, 0.0618896484375]),
                                (129, 59, [0.301025390625, 0.06610107421875, 0.07080078125, 0.301025390625])
                            ]
                            for (x, y, color) in expected {
                                let offset = (y * Int(size.width) + x) * 8
                                let words = bytes.withUnsafeBytes { buffer in
                                    (0..<4).map { buffer.loadUnaligned(fromByteOffset: offset + $0 * 2, as: UInt16.self) }
                                }
                                XCTAssertEqual(words, color.map { Float16($0).bitPattern }, "\(label) at (\(x), \(y))")
                            }
                        }
                        if name == "shear" && density == 1 && !isFloat && role == "layer" {
                            let half = device.device.features.isSuperset(of: [
                                .float16Arithmetic, .float16InputOutput
                            ])
                            let expected: [(Int, Int, [UInt8])] = [
                                (127, 52, [16, 3, 4, half ? 80 : 81]),
                                (129, 55, [16, 3, 4, half ? 80 : 81]),
                                (129, 59, [77, 17, 18, half ? 122 : 121])
                            ]
                            for (x, y, color) in expected {
                                let offset = (y * Int(size.width) + x) * 4
                                XCTAssertEqual(Array(bytes[offset..<offset + 4]), color, "\(label) at (\(x), \(y))")
                            }
                        }
                        if let output { try bytes.write(to: output.appendingPathComponent(label)) }
                    }
                }
            }
        }
    }

    // ASSERTIONS recordedPrimitiveGroupExecution27Observed
    // ASSERTIONS recordedPrimitiveGroupScissor27Observed
    func testPrimitiveGroupSelectionAndBounds() throws {
        let device = try device()
        let primitive = try XCTUnwrap(FilledPrimitive(path: path("rect"), color: Color.red.resolve(in: .init())))
        for (name, basis) in bases where name == "identity" || name == "shear" {
            for density: CGFloat in [1, 2] {
                _ = try render(device, scale: density) { context in
                    context.concatenate(basis)
                    context.addFilter(.shadow(color: .black.opacity(0.5), radius: 2, x: 3, y: 2))
                    for opacity in [0.25, 0.75, 0.999, 0.9999, 1] {
                        context.opacity = opacity
                        let group = try XCTUnwrap(GraphicsContext.PrimitiveShadowGroup(source: primitive, context: context))
                        XCTAssertEqual(group.opacity, Float(Float16(opacity)))
                        if Float16(opacity) == 1 {
                            XCTAssertNil(group.scissor)
                        } else {
                            let scissor = try XCTUnwrap(group.scissor)
                            let expected = name == "identity"
                                ? (density == 1 ? [29, 20, 60, 36] : [58, 40, 120, 72])
                                : (density == 1 ? [54, 26, 93, 42] : [109, 53, 185, 83])
                            XCTAssertEqual([scissor.x, scissor.y, scissor.width, scissor.height], expected)
                        }
                    }
                    context.blendMode = .multiply
                    XCTAssertNil(GraphicsContext.PrimitiveShadowGroup(source: primitive, context: context))
                    context.blendMode = .normal
                    context.addFilter(.blur(radius: 2))
                    XCTAssertNil(GraphicsContext.PrimitiveShadowGroup(source: primitive, context: context))
                }
            }
        }
        var context = recording()
        context.addFilter(.shadow(radius: 2, options: .shadowOnly))
        XCTAssertNil(GraphicsContext.PrimitiveShadowGroup(source: primitive, context: context))
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
