import XCTest
import VVD
@testable import VUI

final class GraphicsContextRenderPassTests: XCTestCase {
    private final class TestTexture: Texture, @unchecked Sendable {
        let format: PixelFormat
        var formatReads = 0

        init(_ format: PixelFormat) { self.format = format }

        var pixelFormat: PixelFormat {
            formatReads += 1
            return format
        }

        var width: Int { 8 }
        var height: Int { 8 }
        var depth: Int { 1 }
        var mipmapCount: Int { 1 }
        var arrayLength: Int { 1 }
        var sampleCount: Int { 1 }
        var type: TextureType { .type2D }
        var isTransient: Bool { false }
        var device: GraphicsDevice { fatalError("No device is needed for format queries") }
        func makeTextureView(pixelFormat: PixelFormat) -> Texture? { nil }
    }

    private final class TestEncoder: RenderCommandEncoder {
        var endCount = 0
        var frontFacings: [Winding] = []
        var stencilReferences: [UInt32] = []
        var cullModes: [CullMode] = []
        var drawStates: [(Winding, UInt32, CullMode)] = []
        private var frontFacing: Winding = .counterClockwise
        private var stencilReference: UInt32 = 37
        private var cullMode: CullMode = .front
        var isCompleted: Bool { endCount > 0 }
        var commandBuffer: CommandBuffer { fatalError("No command buffer is needed for metadata tests") }
        func endEncoding() { endCount += 1 }
        func waitEvent(_ event: GPUEvent) {}
        func signalEvent(_ event: GPUEvent) {}
        func waitSemaphoreValue(_ semaphore: GPUSemaphore, value: UInt64) {}
        func signalSemaphoreValue(_ semaphore: GPUSemaphore, value: UInt64) {}
        func setResource(_ resource: ShaderBindingSet, index: Int) {}
        func setViewport(_ viewport: Viewport) {}
        func setScissorRect(_ rect: ScissorRect) {}
        func setRenderPipelineState(_ state: RenderPipelineState) {}
        func setVertexBuffer(_ buffer: GPUBuffer, offset: Int, index: Int) {}
        func setVertexBuffers(_ buffers: [GPUBuffer], offsets: [Int], index: Int) {}
        func setDepthStencilState(_ state: DepthStencilState?) {}
        func setDepthClipMode(_ mode: DepthClipMode) {}
        func setCullMode(_ mode: CullMode) {
            cullModes.append(mode)
            cullMode = mode
        }
        func setFrontFacing(_ winding: Winding) {
            frontFacings.append(winding)
            frontFacing = winding
        }
        func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) {}
        func setStencilReferenceValue(_ value: UInt32) {
            stencilReferences.append(value)
            stencilReference = value
        }
        func setStencilReferenceValues(front: UInt32, back: UInt32) {}
        func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {}
        func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: Int, data: D) {}
        func memoryBarrier(after: RenderStages, before: RenderStages) {}
        func draw(vertexStart: Int, vertexCount: Int, instanceCount: Int, baseInstance: Int) {
            drawStates.append((frontFacing, stencilReference, cullMode))
        }
        func drawIndexed(indexCount: Int, indexType: IndexType, indexBuffer: GPUBuffer,
                         indexBufferOffset: Int, instanceCount: Int, baseVertex: Int,
                         baseInstance: Int) {
            drawStates.append((frontFacing, stencilReference, cullMode))
        }
    }

    func testFormatsUseFirstColorAndDepthRenderTargets() {
        let descriptor = RenderPassDescriptor(
            colorAttachments: [
                .init(renderTarget: TestTexture(.rgba8Unorm), resolveTarget: TestTexture(.bgra8Unorm)),
                .init(renderTarget: TestTexture(.r8Unorm))
            ],
            depthStencilAttachment: .init(
                renderTarget: TestTexture(.stencil8), resolveTarget: TestTexture(.depth32Float))
        )
        let pass = GraphicsContext.RenderPass(
            encoder: TestEncoder(), descriptor: descriptor, sampleCount: 4)

        XCTAssertEqual(pass.colorFormat, .rgba8Unorm)
        XCTAssertEqual(pass.depthFormat, .stencil8)
        XCTAssertEqual(pass.sampleCount, 4)
    }

    func testMissingRenderTargetsUseInvalidFormats() {
        for descriptor in [
            RenderPassDescriptor(),
            RenderPassDescriptor(colorAttachments: [
                .init(resolveTarget: TestTexture(.rgba8Unorm)),
                .init(renderTarget: TestTexture(.r8Unorm))
            ], depthStencilAttachment: .init(resolveTarget: TestTexture(.stencil8)))
        ] {
            let pass = GraphicsContext.RenderPass(
                encoder: TestEncoder(), descriptor: descriptor, sampleCount: 1)
            XCTAssertEqual(pass.colorFormat, .invalid)
            XCTAssertEqual(pass.depthFormat, .invalid)
        }
    }

    func testDescriptorCopyChangesDoNotChangePassFormats() {
        var descriptor = RenderPassDescriptor(
            colorAttachments: [.init(renderTarget: TestTexture(.rgba8Unorm))],
            depthStencilAttachment: .init(renderTarget: TestTexture(.stencil8)))
        let pass = GraphicsContext.RenderPass(
            encoder: TestEncoder(), descriptor: descriptor, sampleCount: 4)

        descriptor.colorAttachments[0].renderTarget = TestTexture(.bgra8Unorm)
        descriptor.depthStencilAttachment.renderTarget = nil

        XCTAssertEqual(pass.colorFormat, .rgba8Unorm)
        XCTAssertEqual(pass.depthFormat, .stencil8)
        XCTAssertEqual(pass.sampleCount, 4)
    }

    func testFormatsAreResolvedOnlyOncePerPass() {
        let color = TestTexture(.rgba8Unorm)
        let depth = TestTexture(.stencil8)
        let unused = TestTexture(.r8Unorm)
        let descriptor = RenderPassDescriptor(
            colorAttachments: [
                .init(renderTarget: color, resolveTarget: unused),
                .init(renderTarget: unused)
            ],
            depthStencilAttachment: .init(renderTarget: depth, resolveTarget: unused))
        let pass = GraphicsContext.RenderPass(
            encoder: TestEncoder(), descriptor: descriptor, sampleCount: 1)

        for _ in 0..<8 {
            XCTAssertEqual(pass.colorFormat, .rgba8Unorm)
            XCTAssertEqual(pass.depthFormat, .stencil8)
        }
        XCTAssertEqual(color.formatReads, 1)
        XCTAssertEqual(depth.formatReads, 1)
        XCTAssertEqual(unused.formatReads, 0)
    }

    func testEndCompletesEncoderOnlyOnce() {
        let encoder = TestEncoder()
        let pass = GraphicsContext.RenderPass(
            encoder: encoder, descriptor: RenderPassDescriptor(), sampleCount: 1)
        pass.end()
        pass.end()
        XCTAssertEqual(encoder.endCount, 1)
    }

    func testFixedRasterStateIsInitializedForEachPass() {
        let formats: [(PixelFormat, Bool)] = [
            (.invalid, false), (.depth32Float, false),
            (.stencil8, true), (.depth24Unorm_stencil8, true),
            (.depth32Float_stencil8, true)
        ]
        for (format, hasStencil) in formats {
            for _ in 0..<2 {
                let encoder = TestEncoder()
                let pass = GraphicsContext.RenderPass(
                    encoder: encoder,
                    descriptor: RenderPassDescriptor(depthStencilAttachment: .init(
                        renderTarget: format == .invalid ? nil : TestTexture(format))),
                    sampleCount: 1)
                XCTAssertEqual(encoder.frontFacings, [.clockwise])
                XCTAssertEqual(encoder.stencilReferences, hasStencil ? [0] : [])
                XCTAssertTrue(encoder.cullModes.isEmpty)
                let copy = pass
                copy.end()
                pass.end()
                XCTAssertEqual(encoder.frontFacings.count, 1)
                XCTAssertEqual(encoder.stencilReferences.count, hasStencil ? 1 : 0)
                XCTAssertEqual(encoder.endCount, 1)
            }
        }
    }

    func testResolveTargetDoesNotEnableStencilReferenceSetup() {
        let encoder = TestEncoder()
        let pass = GraphicsContext.RenderPass(
            encoder: encoder,
            descriptor: RenderPassDescriptor(depthStencilAttachment: .init(
                resolveTarget: TestTexture(.stencil8))),
            sampleCount: 4)
        XCTAssertEqual(encoder.frontFacings, [.clockwise])
        XCTAssertTrue(encoder.stencilReferences.isEmpty)
        pass.end()
    }

    func testMixedDrawsKeepFixedStateAndPreserveCullTransitions() throws {
        guard let deviceContext = makeGraphicsDeviceContext() else {
            throw XCTSkip("Graphics device unavailable")
        }
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(), environment: EnvironmentValues(),
            viewport: CGRect(x: 0, y: 0, width: 8, height: 8),
            contentOffset: .zero, contentScaleFactor: 1,
            resolution: CGSize(width: 8, height: 8), commandBuffer: commandBuffer))
        let encoder = TestEncoder()
        let pass = GraphicsContext.RenderPass(
            encoder: encoder,
            descriptor: RenderPassDescriptor(
                colorAttachments: [.init(renderTarget: context.sourceTexture)],
                depthStencilAttachment: .init(renderTarget: context.stencilBuffer)),
            sampleCount: 1)
        let copy = pass
        let bounds = CGRect(x: 1, y: 1, width: 6, height: 6)
        let path = Path(bounds)
        XCTAssertTrue(context.encodeStencilPathStrokeCommand(
            renderPass: pass, path: path, style: StrokeStyle(lineWidth: 1)))
        context.encodeShadingBoxCommand(renderPass: copy, shading: .color(.red),
                                       stencil: .testNonZero, blendState: .opaque, bounds: bounds)
        XCTAssertTrue(context.encodeStencilPathFillCommand(renderPass: copy, path: path))
        context.encodeShadingBoxCommand(renderPass: pass, shading: .color(.green),
                                       stencil: .testEven, blendState: .opaque, bounds: bounds)
        let vertices: [_Vertex] = [
            .init(position: (-1, -1), texcoord: (0, 0), color: (1, 1, 1, 1)),
            .init(position: (-1, 1), texcoord: (0, 0), color: (1, 1, 1, 1)),
            .init(position: (1, -1), texcoord: (0, 0), color: (1, 1, 1, 1))
        ]
        context.encodeDrawCommand(renderPass: copy, shader: .vertexColor, stencil: .ignore,
                                  vertices: vertices, texture: nil, blendState: .opaque)
        // Keep the fixed winding while each stroke selects its surviving face.
        let orientations: [(CGAffineTransform, Bool, CullMode)] = [
            (.init(scaleX: -1, y: 1), false, .front),
            (.init(scaleX: 1, y: -1), false, .front),
            (.init(a: 0, b: 1, c: -1, d: 0, tx: 8, ty: 0), false, .back),
            (.init(a: 1, b: 0.5, c: 0, d: 1, tx: 0, ty: 0), false, .back),
            (.identity, true, .front),
            (.init(scaleX: -1, y: 1), true, .back),
            (.identity, false, .back)
        ]
        for (transform, reflectView, _) in orientations {
            var oriented = context
            oriented.transform = transform
            if reflectView {
                oriented.viewTransform = oriented.viewTransform.concatenating(.init(scaleX: -1, y: 1))
            }
            XCTAssertTrue(oriented.encodeStencilPathStrokeCommand(
                renderPass: pass, path: path, style: StrokeStyle(lineWidth: 1)))
        }
        XCTAssertEqual(encoder.frontFacings, [.clockwise])
        XCTAssertEqual(encoder.stencilReferences, [0])
        XCTAssertEqual(encoder.cullModes, [.back, .none, .none, .none, .none] + orientations.map { $0.2 })
        XCTAssertEqual(encoder.drawStates.count, 5 + orientations.count)
        for state in encoder.drawStates {
            XCTAssertEqual(state.0, .clockwise)
            XCTAssertEqual(state.1, 0)
        }
        XCTAssertEqual(encoder.drawStates.map { $0.2 }, encoder.cullModes)
        copy.end()
        pass.end()
        XCTAssertEqual(encoder.endCount, 1)
    }

    func testBeginRenderPassUsesSelectedFormatsAndSampleCount() throws {
        guard let deviceContext = makeGraphicsDeviceContext() else {
            throw XCTSkip("Graphics device unavailable")
        }
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(),
            environment: EnvironmentValues(),
            viewport: CGRect(x: 0, y: 0, width: 8, height: 8),
            contentOffset: .zero,
            contentScaleFactor: 1,
            resolution: CGSize(width: 8, height: 8),
            commandBuffer: commandBuffer))

        for stencil in [false, true] {
            for msaa in [false, true] {
                let pass = try XCTUnwrap(context.beginRenderPass(
                    enableStencil: stencil, enableMSAA: msaa))
                XCTAssertEqual(pass.colorFormat, .rgba8Unorm)
                XCTAssertEqual(pass.depthFormat, stencil ? .stencil8 : .invalid)
                XCTAssertEqual(pass.sampleCount, msaa ? 4 : 1)
                pass.end()
            }
        }
        let loadedPass = try XCTUnwrap(context.beginRenderPass(
            viewport: context.viewport,
            renderTarget: context.renderTargets.source,
            loadAction: .load,
            clearColor: .clear,
            useStencil: true,
            useMSAA: true))
        XCTAssertEqual(loadedPass.colorFormat, .rgba8Unorm)
        XCTAssertEqual(loadedPass.depthFormat, .stencil8)
        XCTAssertEqual(loadedPass.sampleCount, 1)
        loadedPass.end()
    }

    private func renderFixedStateSequence(
        deviceContext: GraphicsDeviceContext,
        msaa: Bool,
        evenOdd: Bool,
        repeatStatePerDraw: Bool
    ) throws -> [UInt8] {
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(), environment: EnvironmentValues(),
            viewport: CGRect(x: 0, y: 0, width: 32, height: 32),
            contentOffset: .zero, contentScaleFactor: 1,
            resolution: CGSize(width: 32, height: 32), commandBuffer: commands))
        let targets = context.renderTargets
        let descriptor = RenderPassDescriptor(
            colorAttachments: [.init(
                renderTarget: msaa ? targets.renderTargetMSAA : targets.source,
                loadAction: .clear, storeAction: msaa ? .dontCare : .store,
                resolveTarget: msaa ? targets.source : nil)],
            depthStencilAttachment: .init(
                renderTarget: msaa ? targets.stencilBufferMSAA : targets.stencilBuffer,
                loadAction: .clear, storeAction: .dontCare))
        let encoder = try XCTUnwrap(commands.makeRenderCommandEncoder(descriptor: descriptor))
        encoder.setViewport(.init(x: 0, y: 0, width: 32, height: 32, nearZ: 0, farZ: 1))
        encoder.setScissorRect(.init(x: 0, y: 0, width: 32, height: 32))
        // Do not let native defaults conceal missing pass initialization.
        encoder.setFrontFacing(.counterClockwise)
        encoder.setStencilReferenceValues(front: 37, back: 91)
        let pass = GraphicsContext.RenderPass(
            encoder: encoder, descriptor: descriptor,
            sampleCount: msaa ? targets.msaaSampleCount : 1)
        let prepareDraw = {
            if repeatStatePerDraw {
                encoder.setFrontFacing(.clockwise)
                encoder.setStencilReferenceValue(0)
            }
        }
        let strokeBounds = CGRect(x: 3.25, y: 4.5, width: 9, height: 21)
        prepareDraw()
        XCTAssertTrue(context.encodeStencilPathStrokeCommand(
            renderPass: pass, path: Path(strokeBounds),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)))
        prepareDraw()
        context.encodeShadingBoxCommand(
            renderPass: pass, shading: .color(.sRGB, red: 1, green: 0, blue: 0),
            stencil: .testNonZero,
            blendState: .opaque, bounds: strokeBounds.insetBy(dx: -2, dy: -2))
        // Shading covers the viewport and earlier stencil values persist.
        // Keep the later fill from repainting the stroke's stencil region.
        encoder.setScissorRect(.init(x: 16, y: 0, width: 16, height: 32))
        let fillBounds = CGRect(x: 18.25, y: 5.5, width: 11, height: 19)
        let path = Path { path in
            path.addRect(fillBounds)
            path.addRect(fillBounds.insetBy(dx: 3, dy: 4))
        }
        prepareDraw()
        XCTAssertTrue(context.encodeStencilPathFillCommand(renderPass: pass, path: path))
        prepareDraw()
        context.encodeShadingBoxCommand(
            renderPass: pass, shading: .color(.sRGB, red: 0, green: 1, blue: 0),
            stencil: evenOdd ? .testEven : .testNonZero,
            blendState: .opaque, bounds: fillBounds)
        pass.end()

        let condition = NSCondition()
        var completed = false
        commands.addCompletedHandler { _ in
            condition.lock()
            completed = true
            condition.broadcast()
            condition.unlock()
        }
        condition.lock()
        XCTAssertTrue(commands.commit())
        let timeout = Date(timeIntervalSinceNow: 5)
        while !completed {
            if !condition.wait(until: timeout) {
                XCTFail("GPU command buffer timed out")
                break
            }
        }
        condition.unlock()
        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: targets.source))
        let pointer = try XCTUnwrap(staging.contents())
        return Array(UnsafeRawBufferPointer(start: pointer, count: 32 * 32 * 4))
    }

    func testFixedRasterStatePreservesStrokeFillAndMSAAOutputOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext() else {
            throw XCTSkip("Graphics device unavailable")
        }
        for msaa in [false, true] {
            var outputs: [[UInt8]] = []
            for evenOdd in [false, true] {
                let reference = try renderFixedStateSequence(
                    deviceContext: deviceContext, msaa: msaa, evenOdd: evenOdd,
                    repeatStatePerDraw: true)
                let actual = try renderFixedStateSequence(
                    deviceContext: deviceContext, msaa: msaa, evenOdd: evenOdd,
                    repeatStatePerDraw: false)
                XCTAssertEqual(actual, reference, "MSAA: \(msaa), even-odd: \(evenOdd)")
                let pixels = stride(from: 0, to: actual.count, by: 4)
                XCTAssertTrue(pixels.contains { actual[$0] > 0 && actual[$0 + 1] == 0 })
                XCTAssertTrue(pixels.contains { actual[$0] == 0 && actual[$0 + 1] > 0 })
                XCTAssertTrue(pixels.contains { actual[$0 + 3] == 0 })
                outputs.append(actual)
            }
            XCTAssertNotEqual(outputs[0], outputs[1])
        }
    }
}
