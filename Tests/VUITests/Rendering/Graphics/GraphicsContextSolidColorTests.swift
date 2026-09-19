import Foundation
import XCTest
import VVD
@testable import VUI

final class GraphicsContextSolidColorTests: XCTestCase {
    private let size = CGSize(width: 256, height: 192)
    private let cases = [
        "integral", "fractional", "near-integral", "outside-integral",
        "scale", "quarter", "shear", "rotate", "fractional-no-aa", "shear-no-aa",
        "circle", "rounded", "stroke", "gradient", "circle-clip", "rect-clip",
        "contains-scissor", "opacity", "half-product", "opaque", "multiply",
        "destination-in", "plus-lighter", "source-atop", "blur", "below-integral",
        "below-integral-source", "near-integral-source", "partial-circle-clip"
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

    private func draw(_ root: GraphicsContext, name label: String) {
        let name = label.replacingOccurrences(of: "-source", with: "")
        var context = root
        var rect = CGRect(x: 80, y: 40, width: 144, height: 120)
        switch name {
        case "fractional", "fractional-no-aa": rect.origin.x += 0.5
        case "near-integral": rect.origin.x += 0.004
        case "outside-integral": rect.origin.x += 0.006
        case "below-integral": rect.origin.x -= 0.004
        case "scale": context.concatenate(.init(a: 0.5, b: 0, c: 0, d: 0.75, tx: 8, ty: 6))
        case "quarter": context.concatenate(.init(a: 0, b: 1, c: -1, d: 0, tx: 224, ty: -48))
        case "shear", "shear-no-aa": context.concatenate(.init(a: 0.75, b: 0.125, c: 0.25, d: 0.75, tx: 0, ty: 0))
        case "rotate": context.rotate(by: .degrees(9))
        case "contains-scissor": rect = CGRect(x: -0.5, y: -0.5, width: 257, height: 193)
        case "opacity", "half-product": context.opacity = 0.75
        case "multiply": context.blendMode = .multiply
        case "destination-in": context.blendMode = .destinationIn
        case "plus-lighter": context.blendMode = .plusLighter
        case "source-atop": context.blendMode = .sourceAtop
        case "circle-clip": context.clip(to: Path(ellipseIn: CGRect(x: 96, y: 48, width: 96, height: 96)))
        case "partial-circle-clip": context.clip(to: Path(ellipseIn: CGRect(x: 176, y: 96, width: 64, height: 64)))
        case "rect-clip": context.clip(to: Path(CGRect(x: 96, y: 48, width: 96, height: 96)))
        case "blur": context.addFilter(.blur(radius: 2))
        default: break
        }
        var path = Path(rect)
        if name == "circle" { path = Path(ellipseIn: CGRect(x: 80, y: 40, width: 120, height: 120)) }
        if name == "rounded" { path = Path(roundedRect: rect, cornerRadius: 8, style: .circular) }
        let alpha = name == "opaque" ? 1.0 : name == "half-product" ? 0.6 : 0.625
        let paint = GraphicsContext.Shading.color(.sRGB, red: 0, green: 1, blue: 0, opacity: alpha)
        if name == "stroke" {
            context.stroke(path, with: paint, lineWidth: 2)
        } else if name == "gradient" {
            context.fill(path, with: .linearGradient(Gradient(colors: [.green, .blue]),
                startPoint: CGPoint(x: 80, y: 40), endPoint: CGPoint(x: 224, y: 160)))
        } else {
            context.fill(path, with: paint, style: FillStyle(antialiased: !name.hasSuffix("no-aa")))
        }
    }

    private func render(_ device: GraphicsDeviceContext, density: CGFloat,
                        viewport: CGRect? = nil, contentOffset: CGPoint = .zero,
                        draw: (GraphicsContext) throws -> Void) throws -> [UInt8] {
        let resolution = size * density
        let queue = try XCTUnwrap(device.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(sceneResources: SceneResources(), environment: .init(),
            viewport: viewport ?? CGRect(origin: .zero, size: resolution), contentOffset: contentOffset,
            contentScaleFactor: density, resolution: resolution, commandBuffer: commands))
        context.clear(with: .clear)
        try draw(context)
        let done = expectation(description: "solid color readback")
        commands.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [done], timeout: 10)
        let buffer = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(buffer.contents()),
            count: Int(resolution.width * resolution.height) * 4))
    }

    // ASSERTIONS recordedSolidPlaneDispatch27Observed
    // ASSERTIONS recordedPrimitiveIntegralBounds27Observed
    func testSolidColorDirectTargetSelectionAndRecordedReplay() throws {
        let device = try device()
        let output = ProcessInfo.processInfo.environment["VUI_SOLID_PLANE_CAPTURE"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for name in cases {
            var recording = GraphicsContext(recording: RBDisplayList(viewport: CGRect(origin: .zero, size: size)),
                environment: EnvironmentValues(), inputs: .init(sceneResources: SceneResources(),
                    viewport: CGRect(origin: .zero, size: size), contentScaleFactor: 1, resourceCommandQueue: nil))
            let backdrop = { (context: GraphicsContext) in
                if !name.hasSuffix("-source") {
                    context.fill(Path(CGRect(origin: .zero, size: self.size)),
                        with: .color(.sRGB, red: 0.25, green: 0.5, blue: 1, opacity: 0.5))
                }
            }
            backdrop(recording)
            draw(recording, name: name)
            let contents = try XCTUnwrap(recording.recording).moveContents()
            for density: CGFloat in [1, 2] {
                let label = "\(name)-\(Int(density))"
                let direct = ["integral", "scale", "quarter", "fractional-no-aa", "shear-no-aa",
                    "contains-scissor", "opacity", "half-product", "opaque"].contains(name) ||
                    name == "fractional" && density == 2 ||
                    ["near-integral", "near-integral-source"].contains(name) && density == 1
                var scratch: Texture?
                let pixels = try render(device, density: density) { context in
                    backdrop(context)
                    if direct {
                        let pass = try XCTUnwrap(context.beginRenderPass(viewport: context.viewport,
                            renderTarget: context.sourceTexture, loadAction: .clear,
                            clearColor: BackendColor(r: 1, g: 0, b: 1, a: 1), useStencil: false, useMSAA: false))
                        pass.end()
                        scratch = context.sourceTexture
                    }
                    let target = context.backdrop
                    self.draw(context, name: name)
                    if direct {
                        XCTAssertTrue((target as AnyObject) === (context.backdrop as AnyObject),
                            "Solid color must draw into the current target: \(label)")
                    } else if name != "blur" {
                        XCTAssertFalse((target as AnyObject) === (context.backdrop as AnyObject),
                            "Paint, clip, blend and analytic coverage must retain their drawing path: \(label)")
                    }
                }
                if let scratch {
                    let buffer = try XCTUnwrap(device.makeCPUAccessible(texture: scratch))
                    let bytes = UnsafeRawBufferPointer(start: try XCTUnwrap(buffer.contents()), count: pixels.count)
                    XCTAssertTrue(stride(from: 0, to: bytes.count, by: 4).allSatisfy {
                        Array(bytes[$0..<$0 + 4]) == [255, 0, 255, 255]
                    }, "Direct color must not materialize or clear the scratch source: \(label)")
                }
                let replay = try render(device, density: density) { contents.draw(in: $0) }
                XCTAssertTrue(pixels == replay, "Live and recorded fill must agree: \(label)")
                let expected: [String: [UInt8]] = ["integral": [12, 183, 48, 207],
                    "opacity": [17, 154, 68, 188], "half-product": [18, 150, 70, 185], "opaque": [0, 255, 0, 255]]
                if let expected = expected[name] {
                    let index = (Int(70 * density) * Int(size.width * density) + Int(100 * density)) * 4
                    XCTAssertEqual(Array(pixels[index..<index + 4]), expected, label)
                }
                if let output { try Data(pixels).write(to: output.appendingPathComponent(label + ".rgba")) }
            }
        }
    }

    // ASSERTIONS recordedSolidPlaneDispatch27Observed
    // ASSERTIONS recordedPrimitiveIntegralBounds27Observed
    func testSolidColorPlaneUsesDestinationPixelCoordinates() throws {
        let device = try device()
        for density: CGFloat in [1, 2] {
            let viewport = CGRect(x: 8, y: 10, width: 128 * density, height: 96 * density)
            for offset in [CGPoint(x: 2, y: 3), CGPoint(x: 0.5, y: 0)] {
                let direct = offset.x == 2 || density == 2
                let pixels = try render(device, density: density, viewport: viewport, contentOffset: offset) { context in
                    let target = context.backdrop
                    context.fill(Path(CGRect(x: 1, y: 1, width: 10, height: 8)),
                        with: .color(.sRGB, red: 0, green: 1, blue: 0))
                    XCTAssertEqual((target as AnyObject) === (context.backdrop as AnyObject), direct)
                }
                let width = Int(size.width * density)
                let x = 8 + Int((1 + offset.x) * density) + 2
                let y = 10 + Int((1 + offset.y) * density) + 2
                XCTAssertEqual(Array(pixels[(y * width + x) * 4..<(y * width + x) * 4 + 4]), [0, 255, 0, 255])
                // Read only initialized pixels within the nonzero viewport.
                let untouched = (Int(10 + 80 * density) * width + Int(8 + 100 * density)) * 4
                XCTAssertEqual(Array(pixels[untouched..<untouched + 4]), [0, 0, 0, 0])
            }
        }
    }
}
