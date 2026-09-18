import Foundation
import Dispatch
import Synchronization
import XCTest
import VVD
@testable import VUI

final class GraphicsContextRecordingTests: XCTestCase {
    private let size = CGSize(width: 64, height: 48)

    private func recording(scale: CGFloat = 1, environment: EnvironmentValues = .init(),
                           resources: SceneResources = SceneResources(),
                           queue: CommandQueue? = nil) -> GraphicsContext {
        GraphicsContext(recording: RBDisplayList(viewport: CGRect(origin: .zero, size: size)),
            environment: environment, inputs: .init(sceneResources: resources,
                viewport: CGRect(origin: .zero, size: size * scale),
                contentScaleFactor: scale, resourceCommandQueue: queue))
    }

    private func device() throws -> GraphicsDeviceContext {
        #if canImport(Metal)
        return try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        #else
        throw XCTSkip("Metal is required for resource rasterization and readback")
        #endif
    }

    private func live(_ queue: CommandQueue, environment: EnvironmentValues = .init(),
                      scale: CGFloat = 1, offset: CGPoint = .zero) throws -> GraphicsContext {
        try XCTUnwrap(GraphicsContext(sceneResources: SceneResources(), environment: environment,
            viewport: CGRect(origin: CGPoint(x: 2, y: 3), size: size * scale),
            contentOffset: offset, contentScaleFactor: scale,
            resolution: CGSize(width: size.width * scale + 2, height: size.height * scale + 3),
            commandBuffer: XCTUnwrap(queue.makeCommandBuffer())))
    }

    private func pixels(_ texture: Texture, device: GraphicsDeviceContext) throws -> [UInt8] {
        let data = try XCTUnwrap(device.makeCPUAccessible(texture: texture))
        return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(data.contents()),
            count: texture.width * texture.height * 4))
    }

    private func render(_ contents: RBDisplayListContents, device: GraphicsDeviceContext,
                        queue: CommandQueue) throws -> [UInt8] {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(sceneResources: SceneResources(),
            environment: .init(), viewport: CGRect(origin: .zero, size: size),
            contentOffset: .zero, contentScaleFactor: 1, resolution: size, commandBuffer: commands))
        context.clear(with: .clear)
        contents.draw(in: context)
        let done = expectation(description: "independent recording replay")
        commands.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [done], timeout: 10)
        return try pixels(context.backdrop, device: device)
    }

    func testGeometryStylesLayersAndClipsRecordWithoutGraphicsResources() throws {
        // ASSERTIONS recordingContextOwner27Observed
        // ASSERTIONS recordedStyleProduction27Observed
        let root = recording(scale: 2)
        XCTAssertNil(root.storage.backend)
        XCTAssertNil(root.storage.inputs.resourceCommandQueue)
        var branch = root
        branch.addFilter(.shadow(color: .black, radius: 2, x: 3, y: 2))
        branch.fill(Path(CGRect(x: 10, y: 10, width: 8, height: 6)),
            with: .color(.sRGBLinear, red: 1, green: 0, blue: 0))
        XCTAssertTrue(branch.storage.shared === root.storage.shared)
        XCTAssertNotEqual(branch.storage.state, root.storage.state)
        XCTAssertNil(root.storage.state.pointee.style)
        let styled = try XCTUnwrap(root.recording).moveContents()
        let predicate = RBDisplayListPredicate()
        predicate.addCondition(fillColor: SIMD4(1, 0, 0, -32768), colorSpace: .linearSRGB)
        XCTAssertFalse(predicate.copyFilteredDisplayList(styled).isEmpty)

        root.drawLayer { layer in
            XCTAssertNil(layer.storage.backend)
            layer.clip(to: Path(CGRect(x: 2, y: 3, width: 5, height: 4)))
            layer.fill(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), with: .color(.blue))
        }
        let layers = try XCTUnwrap(root.recording).moveContents()
        XCTAssertEqual(layers.boundingRect, CGRect(x: 2, y: 3, width: 5, height: 4))
        guard case let .layer(children, _) = layers.items.first?.contents else {
            return XCTFail("The ordinary layer must retain its own contents")
        }
        XCTAssertEqual(children.items.count, 1)
        XCTAssertEqual(children.items[0].state.clips.count, 1)
        let destination = recording(scale: 3)
        layers.draw(in: destination)
        XCTAssertEqual(destination.recording?.boundingRect, layers.boundingRect)
    }

    func testRecordingCopiesKeepInputsAfterTheLiveFrameIsReleased() throws {
        // ASSERTIONS recordingContextOwner27Observed
        // ASSERTIONS recordingResourceInputs27Observed
        let device = try device()
        let queue = try XCTUnwrap(device.renderQueue())
        weak var backend: GraphicsContext.DrawingBackend?
        weak var liveStorage: GraphicsContext.Storage?
        weak var targets: GraphicsContext.RenderTargets?
        var result: GraphicsContext!
        func produce() throws {
            let source = try live(queue, scale: 2, offset: CGPoint(x: 7, y: -5))
            backend = source.drawingBackend
            liveStorage = source.storage
            targets = source.renderTargets
            result = source.recordingContext(size: CGSize(width: 20, height: 12))
            XCTAssertEqual(result.viewport, source.viewport)
            XCTAssertEqual(result.contentScaleFactor, 2)
            XCTAssertEqual(result.contentOffset, source.contentOffset)
            XCTAssertEqual(result.viewTransform, source.viewTransform)
            XCTAssertTrue(result.sceneResources === source.sceneResources)
        }
        try produce()
        XCTAssertNil(backend)
        XCTAssertNil(liveStorage)
        XCTAssertNil(targets)
        var copy = result!
        copy.opacity = 0.25
        XCTAssertNil(copy.storage.backend)
        XCTAssertEqual(copy.contentOffset, CGPoint(x: 7, y: -5))
        copy.fill(Path(CGRect(x: 1, y: 2, width: 3, height: 4)), with: .color(.red))
        XCTAssertEqual(result.recording?.items.count, 1)
        XCTAssertEqual(result.recording?.items.first?.state.opacity, 0.25)
    }

    func testMovedPrimitiveContentsReleaseRecordingInputsAndOwners() throws {
        // ASSERTIONS recordingContextOwner27Observed
        weak var storage: GraphicsContext.Storage?
        weak var shared: GraphicsContext.Storage.Shared?
        weak var list: RBDisplayList?
        weak var resources: SceneResources?
        func produce() -> RBMovedDisplayListContents {
            let source = recording()
            storage = source.storage
            shared = source.storage.shared
            list = source.recording
            resources = source.sceneResources
            source.fill(Path(CGRect(x: 1, y: 2, width: 3, height: 4)), with: .color(.red))
            return source.recording!.moveContents()
        }
        let contents = produce()
        XCTAssertNil(storage)
        XCTAssertNil(shared)
        XCTAssertNil(list)
        XCTAssertNil(resources)
        XCTAssertEqual(contents.boundingRect, CGRect(x: 1, y: 2, width: 3, height: 4))
        contents.draw(in: recording())
    }

    func testVectorTextResolvesAndRecordsWithoutADeviceOrFrame() throws {
        // ASSERTIONS recordingResourceInputs27Observed
        let previous = appContext
        appContext = StyleTestAppContext()
        defer { appContext = previous }
        for scale: CGFloat in [1, 2, 3] {
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            environment.font = .system(size: 16)
            environment.displayScale = scale
            let context = recording(scale: scale, environment: environment)
            let text = context.resolve(Text(verbatim: "Abc").foregroundColor(.red))
            XCTAssertGreaterThan(text.measure(in: size).width, 20)
            XCTAssertEqual(text.resolved.resolvedText?.scaleFactor, scale)
            context.draw(text, in: CGRect(x: 4, y: 4, width: 56, height: 40))
            let contents = try XCTUnwrap(context.recording).moveContents()
            XCTAssertFalse(contents.isEmpty)
            XCTAssertGreaterThan(contents.boundingRect.width, 0)
            XCTAssertTrue(contents.items.contains { item in
                if case .text(let drawing, _) = item.contents,
                   case .vectorGlyphs = drawing.contents { return true }
                return false
            })
        }
    }

    func testGeneratedImagesResolveAtDisplayScaleAndReplayAfterTheirCallbackIsReleased() throws {
        // ASSERTIONS recordingResourceInputs27Observed
        let device = try device()
        let queue = try XCTUnwrap(device.renderQueue())
        for scale: CGFloat in [1, 2, 3] {
            var environment = EnvironmentValues()
            environment.displayScale = scale
            environment.colorScheme = .dark
            let context = recording(scale: 0.5, environment: environment, queue: queue)
            var calls = 0
            final class Token {}
            weak var token: Token?
            weak var callbackStorage: GraphicsContext.Storage?
            weak var texture: AnyObject?
            func produce() throws -> RBMovedDisplayListContents {
                let retained = Token()
                token = retained
                let image = VUI.Image(size: CGSize(width: 12, height: 8)) { child in
                    withExtendedLifetime(retained) {}
                    calls += 1
                    callbackStorage = child.storage
                    XCTAssertNil(child.storage.backend)
                    XCTAssertNotNil(child.recording)
                    XCTAssertEqual(child.contentScaleFactor, scale)
                    XCTAssertEqual(child.clipBoundingRect, CGRect(x: 0, y: 0, width: 12, height: 8))
                    let nested = VUI.Image(size: CGSize(width: 4, height: 3)) { nested in
                        calls += 1
                        nested.fill(Path(CGRect(x: 0, y: 0, width: 4, height: 3)),
                            with: .color(.sRGBLinear, red: 0, green: 1, blue: 0))
                    }
                    child.fill(Path(CGRect(x: 0, y: 0, width: 12, height: 8)),
                        with: .color(.sRGBLinear,
                            red: child.environment.colorScheme == .dark ? 0 : 1, green: 0,
                            blue: child.environment.colorScheme == .dark ? 1 : 0))
                    child.draw(nested, in: CGRect(x: 2, y: 2, width: 4, height: 3))
                }
                let resolved = context.resolve(image)
                XCTAssertEqual(calls, 2)
                XCTAssertEqual(resolved.size, CGSize(width: 12, height: 8))
                let resource = try XCTUnwrap(resolved.texture)
                texture = resource as AnyObject
                XCTAssertEqual(resource.width, Int(12 * scale))
                XCTAssertEqual(resource.height, Int(8 * scale))
                let bytes = try pixels(resource, device: device)
                XCTAssertEqual(Array(bytes.prefix(4)), [0, 0, 255, 255])
                let green = (Int(3 * scale) * resource.width + Int(3 * scale)) * 4
                XCTAssertEqual(Array(bytes[green..<(green + 4)]), [0, 255, 0, 255])
                context.draw(resolved, in: CGRect(x: 4, y: 4, width: 24, height: 16))
                return context.recording!.moveContents()
            }
            var contents: RBMovedDisplayListContents? = try produce()
            XCTAssertNil(token)
            XCTAssertNil(callbackStorage)
            XCTAssertNotNil(texture)
            // New command buffers follow production on the host's resource queue.
            let first = try render(contents!, device: device, queue: queue)
            XCTAssertTrue(try render(contents!, device: device, queue: queue) == first)
            XCTAssertEqual(calls, 2)
            contents = nil
            XCTAssertNil(texture)
        }
    }

    func testNamedImageUploadAndReplayUseTheResourceQueueWithoutAFrame() throws {
        // ASSERTIONS recordingResourceInputs27Observed
        let device = try device()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255])
        let source = VVD.Image(width: 2, height: 2, pixelFormat: .rgba8, data: bytes)
        try XCTUnwrap(source.encode(format: .png)).write(to: directory.appendingPathComponent("sample.png"))
        let bundle = try XCTUnwrap(Bundle(url: directory))
        let queue = try XCTUnwrap(device.renderQueue())
        let context = recording(queue: queue)
        let image = VUI.Image("sample.png", bundle: bundle)
        let resolved = context.resolve(image)
        let texture = try XCTUnwrap(resolved.texture)
        XCTAssertEqual(try pixels(texture, device: device), Array(bytes))
        XCTAssertTrue(try XCTUnwrap(context.resolve(image).texture) as AnyObject === texture as AnyObject)
        XCTAssertEqual(context.sceneResources.cachedTextures.count, 1)
        context.draw(resolved, in: CGRect(x: 4, y: 4, width: 24, height: 16))
        let contents = context.recording!.moveContents()
        context.sceneResources.cachedTextures.removeAll()
        let result = try render(contents, device: device, queue: queue)
        XCTAssertGreaterThan(result.reduce(0) { $0 + Int($1) }, 0)
    }

    func testLiveAndIndependentContextsProduceTheSameGeneratedImage() throws {
        // ASSERTIONS recordingResourceInputs27Observed
        let device = try device()
        let queue = try XCTUnwrap(device.renderQueue())
        var environment = EnvironmentValues()
        environment.displayScale = 2
        let direct = try live(queue, environment: environment, scale: 0.5,
            offset: CGPoint(x: 20, y: 20))
        let independent = recording(scale: 3, environment: environment, queue: queue)
        var calls = 0
        let image = VUI.Image(size: CGSize(width: 12, height: 8)) { child in
            calls += 1
            XCTAssertEqual(child.contentOffset, .zero)
            XCTAssertNil(child.storage.backend)
            child.fill(Path(CGRect(x: 2, y: 2, width: 6, height: 4)),
                with: .color(.sRGBLinear, red: 1, green: 0, blue: 0))
        }
        let first = direct.resolve(image)
        let second = independent.resolve(image)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(first.size, second.size)
        XCTAssertEqual(first.size, CGSize(width: 12, height: 8))
        XCTAssertEqual(try pixels(XCTUnwrap(first.texture), device: device),
                       try pixels(XCTUnwrap(second.texture), device: device))
        XCTAssertEqual(direct.commandBuffer.status, .ready)
    }

    func testExistingTextureCanBeRecordedWithoutAResourceQueue() throws {
        // ASSERTIONS recordingResourceInputs27Observed
        let device = try device()
        let bytes = Data(repeating: 255, count: 2 * 2 * 4)
        let source = VVD.Image(width: 2, height: 2, pixelFormat: .rgba8, data: bytes)
        let queue = try XCTUnwrap(device.renderQueue())
        let texture = try XCTUnwrap(source.makeTexture(commandQueue: queue))
        let context = recording()
        let resolved = context.resolve(VUI.Image(decorative: texture, scale: 2))
        XCTAssertEqual(resolved.size, CGSize(width: 1, height: 1))
        context.draw(resolved, in: CGRect(x: 1, y: 2, width: 3, height: 4))
        let contents = context.recording!.moveContents()
        XCTAssertEqual(contents.boundingRect, CGRect(x: 1, y: 2, width: 3, height: 4))
        guard case let .image(saved, _, _) = contents.items.first?.contents else {
            return XCTFail("The existing texture must survive in an image payload")
        }
        XCTAssertTrue(try XCTUnwrap(saved.texture) as AnyObject === texture as AnyObject)
        XCTAssertNil(context.storage.inputs.resourceCommandQueue)
    }

    func testGeneratedImageReturnsWhileTheGPUQueueIsStillBlocked() throws {
        let device = try device()
        let queue = try XCTUnwrap(device.renderQueue())
        _ = try XCTUnwrap(GraphicsPipelineStates.sharedInstance(commandQueue: queue))
        let gate = try XCTUnwrap(device.device.makeSemaphore())
        let unblockQueue = try XCTUnwrap(device.device.makeCommandQueue(flags: .render))
        let unblock = try XCTUnwrap(unblockQueue.makeCommandBuffer())
        unblock.encodeSignalSemaphore(gate, value: 1)
        let blocker = try XCTUnwrap(queue.makeCommandBuffer())
        blocker.encodeWaitSemaphore(gate, value: 1)
        let encoder = try XCTUnwrap(blocker.makeCopyCommandEncoder())
        encoder.endEncoding()
        XCTAssertTrue(blocker.commit())

        let returned = expectation(description: "image resolution returns before GPU completion")
        let resource = Mutex<Texture?>(nil)
        DispatchQueue.global().async {
            let size = CGSize(width: 12, height: 8)
            let bounds = CGRect(origin: .zero, size: size)
            let context = GraphicsContext(recording: RBDisplayList(viewport: bounds),
                environment: .init(), inputs: .init(sceneResources: SceneResources(),
                    viewport: bounds, contentScaleFactor: 1, resourceCommandQueue: queue))
            let image = VUI.Image(size: size) { child in
                child.fill(Path(bounds), with: .color(.sRGBLinear, red: 1, green: 0, blue: 0))
            }
            let resolved = context.resolve(image)
            resource.withLock { $0 = resolved.texture }
            returned.fulfill()
        }
        wait(for: [returned], timeout: 2)
        XCTAssertEqual(blocker.status, .committed)
        // Release the GPU even when the nonblocking assertion fails.
        XCTAssertTrue(unblock.commit())
        if let texture = resource.withLock({ $0 }) {
            XCTAssertEqual(Array(try pixels(texture, device: device).prefix(4)), [255, 0, 0, 255])
        } else {
            XCTFail("Resolution must publish the texture without waiting for GPU completion")
        }
    }
}
