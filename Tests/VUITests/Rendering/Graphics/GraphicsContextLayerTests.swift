import XCTest
import VVD
@testable import VUI

final class GraphicsContextLayerTests: XCTestCase {
    private struct Sample {
        var name: String
        var frame: CGRect
        var transform: CGAffineTransform = .identity
        var offset: CGPoint = .zero
        var expected: CGRect
    }

    private func render(
        device: GraphicsDeviceContext,
        size: CGSize = CGSize(width: 64, height: 48),
        scale: CGFloat = 1,
        offset: CGPoint = .zero,
        viewportOrigin: CGPoint = .zero,
        content: (inout GraphicsContext) throws -> Void
    ) throws -> [UInt8] {
        let viewport = CGRect(origin: viewportOrigin, size: size * scale)
        let width = Int(viewport.maxX)
        let height = Int(viewport.maxY)
        let queue = try XCTUnwrap(device.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        var context = try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(),
            environment: EnvironmentValues(),
            viewport: viewport,
            contentOffset: offset,
            contentScaleFactor: scale,
            resolution: CGSize(width: width, height: height),
            commandBuffer: commandBuffer
        ))
        context.clear(with: .clear)
        try content(&context)

        let completed = expectation(description: "GPU layer completion")
        commandBuffer.addCompletedHandler { _ in completed.fulfill() }
        XCTAssertTrue(commandBuffer.commit())
        wait(for: [completed], timeout: 5)
        let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        return Array(UnsafeRawBufferPointer(start: pointer, count: width * height * 4))
    }

    private func assertCoverage(
        _ pixels: [UInt8],
        width: Int,
        bounds expected: CGRect,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var bounds = CGRect.null
        var count = 0
        var alpha = 0
        for i in 0..<(pixels.count / 4) {
            let value = Int(pixels[i * 4 + 3])
            if value > 0 {
                bounds = bounds.union(CGRect(x: i % width, y: i / width, width: 1, height: 1))
                count += 1
            }
            alpha += value
        }
        let expectedCount = expected.isNull ? 0 : Int(expected.width * expected.height)
        XCTAssertEqual(bounds, expected, message, file: file, line: line)
        XCTAssertEqual(count, expectedCount, message, file: file, line: line)
        XCTAssertEqual(alpha, expectedCount * 255, message, file: file, line: line)
    }

    // ASSERTIONS graphicsContextAffineLayerVisibilityObserved
    func testSizedLayerUsesCompositedViewportCoordinatesOnGPU() throws {
        guard let device = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let samples = [
            Sample(name: "identity", frame: CGRect(x: 8, y: 8, width: 16, height: 12),
                   expected: CGRect(x: 8, y: 8, width: 16, height: 12)),
            Sample(name: "translateX", frame: CGRect(x: 80, y: 8, width: 16, height: 12),
                   transform: CGAffineTransform(translationX: -72, y: 0),
                   expected: CGRect(x: 8, y: 8, width: 16, height: 12)),
            Sample(name: "translateY", frame: CGRect(x: 8, y: 64, width: 16, height: 12),
                   transform: CGAffineTransform(translationX: 0, y: -56),
                   expected: CGRect(x: 8, y: 8, width: 16, height: 12)),
            Sample(name: "translateNegative", frame: CGRect(x: -40, y: -24, width: 16, height: 12),
                   transform: CGAffineTransform(translationX: 48, y: 32),
                   expected: CGRect(x: 8, y: 8, width: 16, height: 12)),
            Sample(name: "quarterTurn", frame: CGRect(x: 80, y: 8, width: 16, height: 12),
                   transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 28, ty: -72),
                   expected: CGRect(x: 8, y: 8, width: 12, height: 16)),
            Sample(name: "reflection", frame: CGRect(x: 80, y: 64, width: 16, height: 12),
                   transform: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 104, ty: 84),
                   expected: CGRect(x: 8, y: 8, width: 16, height: 12)),
            Sample(name: "scaleDown", frame: CGRect(x: 80, y: 64, width: 32, height: 24),
                   transform: CGAffineTransform(scaleX: 0.25, y: 0.25),
                   expected: CGRect(x: 20, y: 16, width: 8, height: 6)),
            Sample(name: "contentOffset", frame: CGRect(x: 80, y: 64, width: 16, height: 12),
                   offset: CGPoint(x: -72, y: -56),
                   expected: CGRect(x: 8, y: 8, width: 16, height: 12)),
            Sample(name: "rotationAndOffset", frame: CGRect(x: 80, y: 8, width: 16, height: 12),
                   transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 28, ty: -72),
                   offset: CGPoint(x: 4, y: 4),
                   expected: CGRect(x: 12, y: 12, width: 12, height: 16)),
            Sample(name: "rightInterior", frame: CGRect(x: 40, y: 8, width: 16, height: 12),
                   expected: CGRect(x: 40, y: 8, width: 16, height: 12)),
            Sample(name: "partialRight", frame: CGRect(x: 56, y: 8, width: 16, height: 12),
                   expected: CGRect(x: 56, y: 8, width: 8, height: 12)),
            Sample(name: "partialLeft", frame: CGRect(x: -8, y: 8, width: 16, height: 12),
                   expected: CGRect(x: 0, y: 8, width: 8, height: 12))
        ]
        for scale: CGFloat in [0.5, 1, 2] {
            for sample in samples {
                var calls = 0
                let pixels = try render(device: device, scale: scale, offset: sample.offset) { context in
                    context.transform = sample.transform
                    context.drawLayer(in: sample.frame) { layer, size in
                        calls += 1
                        XCTAssertEqual(size, sample.frame.size)
                        layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                    }
                }
                let message = "\(sample.name), scale \(scale)"
                XCTAssertEqual(calls, 1, message)
                assertCoverage(pixels, width: Int(64 * scale),
                               bounds: sample.expected.applying(CGAffineTransform(scaleX: scale, y: scale)),
                               message)
            }
        }
    }

    // ASSERTIONS graphicsContextAffineLayerVisibilityObserved
    func testSizedLayerCullsOutsideEveryViewportEdgeOnGPU() throws {
        guard let device = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let frames = [
            CGRect(x: 80, y: 8, width: 16, height: 12),
            CGRect(x: 8, y: 64, width: 16, height: 12),
            CGRect(x: -32, y: 8, width: 16, height: 12),
            CGRect(x: 8, y: -24, width: 16, height: 12)
        ]
        for frame in frames {
            let pixels = try render(device: device) { context in
                context.drawLayer(in: frame) { _, _ in
                    XCTFail("Offscreen unfiltered layer should not allocate or draw: \(frame)")
                }
            }
            assertCoverage(pixels, width: 64, bounds: .null, "\(frame)")
        }
        let pixels = try render(device: device) { context in
            context.translateBy(x: 80, y: 0)
            context.drawLayer(in: CGRect(x: 8, y: 8, width: 16, height: 12)) { _, _ in
                XCTFail("A transformed offscreen layer should be culled")
            }
        }
        assertCoverage(pixels, width: 64, bounds: .null, "transformed outside")
    }

    // ASSERTIONS graphicsContextAffineLayerVisibilityObserved
    func testSizedLayerOffscreenBlendPreservesDestinationOnGPU() throws {
        guard let device = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        for blendMode: GraphicsContext.BlendMode in [.copy, .destinationIn] {
            let pixels = try render(device: device) { context in
                context.clear(with: .red)
                context.blendMode = blendMode
                context.drawLayer(in: CGRect(x: -32, y: 8, width: 16, height: 12)) { layer, size in
                    layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                }
            }
            let unchanged = stride(from: 0, to: pixels.count, by: 4).allSatisfy { index in
                let red = pixels[index] == 255 && pixels[index + 1] == 0
                let opaque = pixels[index + 2] == 0 && pixels[index + 3] == 255
                return red && opaque
            }
            XCTAssertTrue(unchanged,
                          "An offscreen layer must preserve the destination for mode \(blendMode.rawValue)")
        }
    }

    // ASSERTIONS graphicsContextAffineLayerVisibilityObserved
    func testSizedLayerUsesViewportExtentIndependentlyOfTextureOriginOnGPU() throws {
        guard let device = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let pixels = try render(device: device, scale: 0.5,
                                offset: CGPoint(x: -72, y: -56),
                                viewportOrigin: CGPoint(x: 8, y: 6)) { context in
            context.drawLayer(in: CGRect(x: 80, y: 64, width: 16, height: 12)) { layer, size in
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            }
        }
        assertCoverage(pixels, width: 40, bounds: CGRect(x: 12, y: 10, width: 8, height: 6),
                       "nonzero viewport origin")
    }

    // ASSERTIONS graphicsContextOffscreenLayerCallbackObserved
    // ASSERTIONS canvasSymbolRecordedDrawingObserved
    func testSizedLayerRecordingKeepsCommandsForReplayViewportAndTransform() throws {
        guard let device = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        var commands: RBMovedDisplayListContents?
        var calls = 0
        _ = try render(device: device, size: CGSize(width: 16, height: 12)) { context in
            var recording = context.recordingContext(size: CGSize(width: 128, height: 48))
            recording.translateBy(x: -40, y: 0)
            recording.drawLayer(in: CGRect(x: 80, y: 8, width: 16, height: 12)) { layer, size in
                calls += 1
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            }
            commands = recording.recording?.moveContents()
        }
        let retained = try XCTUnwrap(commands)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(retained.items.count, 1)
        for scale: CGFloat in [0.5, 1, 2] {
            let pixels = try render(device: device, scale: scale,
                                    offset: CGPoint(x: 4, y: 4)) { context in
                context.translateBy(x: -32, y: 0)
                retained.draw(in: context)
            }
            assertCoverage(pixels, width: Int(64 * scale),
                           bounds: CGRect(x: 12, y: 12, width: 16, height: 12)
                            .applying(CGAffineTransform(scaleX: scale, y: scale)),
                           "recorded replay at scale \(scale)")
            XCTAssertEqual(calls, 1, "Replay must not reenter the original callback")
        }
    }

    // ASSERTIONS canvasRecordedOwnership27Observed
    func testMovedContentsReplayThroughDrawingDispatchAndAnotherRecording() throws {
        guard let device = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        func paint(_ context: inout GraphicsContext) {
            context.clip(to: Path(CGRect(x: 6, y: 5, width: 12, height: 10)))
            context.clipToLayer { mask in
                mask.fill(Path(CGRect(x: 8, y: 3, width: 12, height: 16)), with: .color(.white))
            }
            context.opacity = 0.5
            context.drawLayer { layer in
                layer.fill(Path(CGRect(x: 0, y: 0, width: 20, height: 20)), with: .color(.red))
                layer.fill(Path(CGRect(x: 12, y: 8, width: 8, height: 12)), with: .color(.blue))
            }
        }
        let expected = try render(device: device) { context in
            context.translateBy(x: 3, y: 4)
            paint(&context)
        }
        XCTAssertTrue(expected.contains { $0 != 0 })

        var saved: RBMovedDisplayListContents?
        _ = try render(device: device) { context in
            var recording = context.recordingContext(size: CGSize(width: 64, height: 48))
            paint(&recording)
            saved = recording.recording?.moveContents()
        }
        let contents = try XCTUnwrap(saved)
        let content = DisplayList.Content(drawing: contents, origin: CGPoint(x: 3, y: 4), options: .init())
        let frame = try XCTUnwrap(content.command.bounds)
        var list = DisplayList()
        list.items = [.init(content: content, frame: frame, identity: .none, version: .init())]
        list.interpolationBounds = frame

        for route in 0..<3 {
            let pixels = try render(device: device) { context in
                switch route {
                case 0:
                    content.draw(in: context)
                case 1:
                    DisplayList.GraphicsRenderer().render(list: list, at: .zero, in: context)
                default:
                    let recording = context.recordingContext(size: CGSize(width: 64, height: 48))
                    DisplayList.GraphicsRenderer().render(list: list, at: .zero, in: recording)
                    recording.recording?.moveContents().draw(in: context)
                }
            }
            XCTAssertEqual(pixels, expected, "retained contents route \(route)")
        }
    }

    // ASSERTIONS graphicsContextLayerFilterContributionObserved
    func testSizedLayerDoesNotCullOffscreenFilterContributionOnGPU() throws {
        guard let device = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        var calls = 0
        let pixels = try render(device: device) { context in
            var matrix = ColorMatrix()
            matrix.a5 = 1
            context.addFilter(.colorMatrix(matrix))
            context.drawLayer(in: CGRect(x: 80, y: 8, width: 16, height: 12)) { layer, size in
                calls += 1
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            }
        }
        XCTAssertEqual(calls, 1)
        assertCoverage(pixels, width: 64, bounds: CGRect(x: 0, y: 0, width: 64, height: 48),
                       "alpha bias contributes outside source geometry")
        XCTAssertTrue(stride(from: 0, to: pixels.count, by: 4).allSatisfy {
            pixels[$0] == 0 && pixels[$0 + 1] == 0 && pixels[$0 + 2] == 0
        })
    }
}
