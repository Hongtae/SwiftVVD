import Foundation
import XCTest
import VVD
@testable import VUI

final class GraphicsContextBlendGeometryTests: XCTestCase {
    private final class CaptureEncoder: RenderCommandEncoder {
        var isCompleted = false
        var commandBuffer: CommandBuffer { fatalError("Only vertex uploads are captured") }
        private var buffer: GPUBuffer?
        private var offset = 0
        var vertices: [_Vertex] = []
        var drawCount = 0
        var resourceCount = 0
        var pipelineCount = 0
        var uploadCount = 0

        func endEncoding() { isCompleted = true }
        func waitEvent(_ event: GPUEvent) {}
        func signalEvent(_ event: GPUEvent) {}
        func waitSemaphoreValue(_ semaphore: GPUSemaphore, value: UInt64) {}
        func signalSemaphoreValue(_ semaphore: GPUSemaphore, value: UInt64) {}
        func setResource(_ resource: ShaderBindingSet, index: Int) { resourceCount += 1 }
        func setViewport(_ viewport: Viewport) {}
        func setScissorRect(_ rect: ScissorRect) {}
        func setRenderPipelineState(_ state: RenderPipelineState) { pipelineCount += 1 }
        func setVertexBuffer(_ buffer: GPUBuffer, offset: Int, index: Int) {
            uploadCount += 1
            XCTAssertEqual(index, 0)
            self.buffer = buffer
            self.offset = offset
        }
        func setVertexBuffers(_ buffers: [GPUBuffer], offsets: [Int], index: Int) {}
        func setDepthStencilState(_ state: DepthStencilState?) {}
        func setDepthClipMode(_ mode: DepthClipMode) {}
        func setCullMode(_ mode: CullMode) {}
        func setFrontFacing(_ winding: Winding) {}
        func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) {}
        func setStencilReferenceValue(_ value: UInt32) {}
        func setStencilReferenceValues(front: UInt32, back: UInt32) {}
        func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {}
        func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: Int, data: D) {}
        func memoryBarrier(after: RenderStages, before: RenderStages) {}
        func draw(vertexStart: Int, vertexCount: Int, instanceCount: Int, baseInstance: Int) {
            drawCount += 1
            XCTAssertEqual(vertexCount, 6)
            guard let buffer, let contents = buffer.contents() else {
                XCTFail("Missing uploaded vertices")
                return
            }
            XCTAssertEqual(vertexStart, 0)
            XCTAssertEqual(instanceCount, 1)
            XCTAssertEqual(baseInstance, 0)
            XCTAssertLessThanOrEqual(offset + vertexCount * MemoryLayout<_Vertex>.stride,
                                     buffer.length)
            vertices = Array(UnsafeBufferPointer(
                start: contents.advanced(by: offset).assumingMemoryBound(to: _Vertex.self),
                count: vertexCount
            ))
        }
        func drawIndexed(indexCount: Int, indexType: IndexType, indexBuffer: GPUBuffer,
                         indexBufferOffset: Int, instanceCount: Int, baseVertex: Int,
                         baseInstance: Int) {
            XCTFail("Texture quads must use the non-indexed vertex draw")
        }
    }

    private func makeDeviceContext() throws -> GraphicsDeviceContext {
        guard let context = makeGraphicsDeviceContext() else {
            throw XCTSkip("Graphics device unavailable")
        }
        return context
    }

    private func makeContext(_ deviceContext: GraphicsDeviceContext) throws -> GraphicsContext {
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        return try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(), environment: EnvironmentValues(),
            viewport: CGRect(x: 0, y: 0, width: 32, height: 32),
            contentOffset: .zero, contentScaleFactor: 1,
            resolution: CGSize(width: 32, height: 32), commandBuffer: commands))
    }


    private final class DimensionTexture: Texture {
        let base: Texture
        let size: (Int, Int, Int)
        private(set) var reads = [0, 0, 0]
        init(base: Texture, size: (Int, Int, Int)) { self.base = base; self.size = size }
        var width: Int { reads[0] += 1; return size.0 }
        var height: Int { reads[1] += 1; return size.1 }
        var depth: Int { reads[2] += 1; return size.2 }
        var device: GraphicsDevice { base.device }
        var mipmapCount: Int { base.mipmapCount }
        var arrayLength: Int { base.arrayLength }
        var sampleCount: Int { base.sampleCount }
        var type: TextureType { base.type }
        var pixelFormat: PixelFormat { base.pixelFormat }
        var isTransient: Bool { base.isTransient }
        func makeTextureView(pixelFormat: PixelFormat) -> Texture? { nil }
    }

    private func capture(
        context: GraphicsContext, source: Texture, backdrop: Texture,
        textureFrame: CGRect, blendMode: GraphicsContext.BlendMode,
        color: BackendColor, reference: Bool
    ) -> [UInt32] {
        let encoder = CaptureEncoder()
        let pass = GraphicsContext.RenderPass(
            encoder: encoder, descriptor: RenderPassDescriptor(colorAttachments: [
                .init(renderTarget: context.sourceTexture)
            ]), sampleCount: 1)
        let result = reference
            ? context.referenceBlendTexturesCommand(
                renderPass: pass, source: source, backdrop: backdrop,
                textureFrame: textureFrame, blendMode: blendMode, color: color)
            : context.encodeBlendTexturesCommand(
                renderPass: pass, source: source, backdrop: backdrop,
                textureFrame: textureFrame, blendMode: blendMode, color: color)
        pass.end()
        XCTAssertTrue(result)
        XCTAssertEqual(encoder.drawCount, 1)
        XCTAssertEqual(encoder.vertices.count, 6)
        XCTAssertEqual(MemoryLayout<_Vertex>.stride, 8 * MemoryLayout<Float>.stride)
        return encoder.vertices.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
    }

    private func makeTexturePair(
        _ device: GraphicsDevice, width: Int, height: Int
    ) throws -> [Texture] {
        try (0..<2).map { _ in
            try XCTUnwrap(device.makeTexture(descriptor: .init(
                textureType: .type2D, pixelFormat: .rgba8Unorm,
                width: width, height: height, usage: .sampled)))
        }
    }

    func testBlendQuadPreservesVertexBitsAcrossDimensionsFramesAndModes() throws {
        let device = try makeDeviceContext()
        let context = try makeContext(device)
        let pairs = try [(7, 13), (32, 16), (17, 31)].map {
            try makeTexturePair(device.device, width: $0.0, height: $0.1)
        }
        let frames: [CGRect] = [
            .init(x: 0, y: 0, width: 7, height: 13),
            .init(x: -2.5, y: 4.25, width: 11.75, height: 18.125),
            .init(x: 7, y: 13, width: -7, height: -13),
            .zero, .null, .infinite
        ]
        let colors: [BackendColor] = [
            .white, .init(0.25, 0.5, 0.75, 0.375),
            .init(-0.0, 1.5, -2.5, 0.125), .init(.nan, -.infinity, .infinity, -0.0)
        ]
        for pair in pairs {
            for frame in frames {
                for color in colors {
                    for rawValue in Int32(0)...28 {
                        let expected = capture(
                            context: context, source: pair[0], backdrop: pair[1],
                            textureFrame: frame, blendMode: .init(rawValue: rawValue),
                            color: color, reference: true)
                        let actual = capture(
                            context: context, source: pair[0], backdrop: pair[1],
                            textureFrame: frame, blendMode: .init(rawValue: rawValue),
                            color: color, reference: false)
                        XCTAssertEqual(actual, expected)
                    }
                }
            }
        }
    }

    func testBlendQuadReadsCurrentDimensionsAcrossCopiesAndLayers() throws {
        let device = try makeDeviceContext()
        let root = try makeContext(device)
        let pairA = try makeTexturePair(device.device, width: 8, height: 16)
        let pairB = try makeTexturePair(device.device, width: 17, height: 7)
        var copy = root
        copy.transform = .init(a: -1, b: 0.25, c: 0.5, d: 1, tx: 15, ty: -7)
        let layer = try XCTUnwrap(root.makeLayerContext(CGSize(width: 24, height: 18)))
        var results: [[UInt32]] = []
        for (index, context) in [root, copy, layer, copy, root].enumerated() {
            let pair = index % 2 == 0 ? pairA : pairB
            let frame = CGRect(x: 1, y: 2, width: 7, height: 5)
            let expected = capture(
                context: context, source: pair[0], backdrop: pair[1],
                textureFrame: frame, blendMode: .multiply, color: .white, reference: true)
            let actual = capture(
                context: context, source: pair[0], backdrop: pair[1],
                textureFrame: frame, blendMode: .multiply, color: .white, reference: false)
            XCTAssertEqual(actual, expected)
            results.append(actual)
        }
        // Composition uses fixed clip-space positions, independent of context transforms.
        XCTAssertEqual(results[0], results[2])
        XCTAssertEqual(results[0], results[4])
        XCTAssertEqual(results[1], results[3])
        XCTAssertNotEqual(results[0], results[1])
    }

    func testBlendRejectsEveryDimensionMismatchBeforeRecording() throws {
        let device = try makeDeviceContext()
        let context = try makeContext(device)
        for size in [(4, 7, 1), (3, 8, 1), (3, 7, 2)] {
            for reference in [true, false] {
                let source = DimensionTexture(base: context.sourceTexture, size: (3, 7, 1))
                let backdrop = DimensionTexture(base: context.sourceTexture, size: size)
                let encoder = CaptureEncoder()
                let pass = GraphicsContext.RenderPass(
                    encoder: encoder, descriptor: RenderPassDescriptor(colorAttachments: [
                        .init(renderTarget: context.sourceTexture)
                    ]), sampleCount: 1)
                let result = reference
                    ? context.referenceBlendTexturesCommand(
                        renderPass: pass, source: source, backdrop: backdrop,
                        textureFrame: .zero, blendMode: .normal, color: .white)
                    : context.encodeBlendTexturesCommand(
                        renderPass: pass, source: source, backdrop: backdrop,
                        textureFrame: .zero, blendMode: .normal, color: .white)
                pass.end()
                XCTAssertFalse(result)
                XCTAssertEqual(source.reads, [1, 1, 1])
                XCTAssertEqual(backdrop.reads, [1, 1, 1])
                XCTAssertEqual(encoder.drawCount, 0)
                XCTAssertEqual(encoder.uploadCount, 0)
                XCTAssertEqual(encoder.pipelineCount, 0)
                XCTAssertEqual(encoder.resourceCount, 0)
            }
        }
    }

    private func waitForCompletion(_ commands: CommandBuffer) throws {
        let condition = NSCondition()
        var completed = false
        commands.addCompletedHandler { _ in
            condition.lock()
            completed = true
            condition.broadcast()
            condition.unlock()
        }
        condition.lock()
        defer { condition.unlock() }
        XCTAssertTrue(commands.commit())
        let timeout = Date(timeIntervalSinceNow: 5)
        while !completed {
            if !condition.wait(until: timeout) {
                XCTFail("GPU command buffer timed out")
                break
            }
        }
    }


    private func makePatternTextures(_ deviceContext: GraphicsDeviceContext) throws -> [Texture] {
        let device = deviceContext.device
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commands.makeCopyCommandEncoder())
        let palette: [[UInt8]] = [
            [192, 0, 0, 192], [0, 128, 0, 128],
            [0, 0, 255, 255], [64, 64, 0, 64]
        ]
        var textures: [Texture] = []
        for (index, size) in [(4, 4), (4, 4), (7, 5), (7, 5)].enumerated() {
            let texture = try XCTUnwrap(device.makeTexture(descriptor: .init(
                textureType: .type2D, pixelFormat: .rgba8Unorm,
                width: size.0, height: size.1, usage: [.sampled, .copyDestination])))
            let bytes = (0..<(size.0 * size.1)).flatMap { pixel in
                palette[(pixel + pixel / size.0 + index) % 4]
            }
            let buffer = try XCTUnwrap(device.makeBuffer(
                length: bytes.count, storageMode: .shared, cpuCacheMode: .writeCombined))
            let pointer = try XCTUnwrap(buffer.contents())
            bytes.withUnsafeBytes { pointer.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            buffer.flush()
            encoder.copy(
                from: buffer,
                sourceOffset: BufferImageOrigin(offset: 0, imageWidth: size.0, imageHeight: size.1),
                to: texture, destinationOffset: TextureOrigin(layer: 0, level: 0, x: 0, y: 0, z: 0),
                size: TextureSize(width: size.0, height: size.1, depth: 1))
            textures.append(texture)
        }
        encoder.endEncoding()
        try waitForCompletion(commands)
        return textures
    }

    private func renderBlendSequence(
        deviceContext: GraphicsDeviceContext, textures: [Texture],
        blendMode: GraphicsContext.BlendMode, varied: Bool,
        msaa: Bool, reference: Bool
    ) throws -> [UInt8] {
        let context = try makeContext(deviceContext)
        let pass = try XCTUnwrap(context.beginRenderPass(
            viewport: context.viewport, renderTarget: context.sourceTexture,
            loadAction: .clear, clearColor: .clear, useStencil: false, useMSAA: msaa))
        for index in 0..<4 {
            let pair = (index & 1) * 2
            let source = textures[pair + (varied ? 1 : 0)]
            let backdrop = textures[pair + (varied ? 0 : 1)]
            let frame = index < 2
                ? CGRect(x: 0.25, y: 0.5,
                         width: CGFloat(source.width) - 0.5, height: CGFloat(source.height) - 1)
                : CGRect(x: CGFloat(source.width) + 1, y: -1.5,
                         width: -CGFloat(source.width) - 2, height: CGFloat(source.height) + 3)
            let tint = varied ? BackendColor(white: 0.375, opacity: 0.375) : .white
            pass.encoder.setScissorRect(ScissorRect(x: index * 8, y: 0, width: 8, height: 32))
            let result = reference
                ? context.referenceBlendTexturesCommand(
                    renderPass: pass, source: source, backdrop: backdrop,
                    textureFrame: frame, blendMode: blendMode, color: tint)
                : context.encodeBlendTexturesCommand(
                    renderPass: pass, source: source, backdrop: backdrop,
                    textureFrame: frame, blendMode: blendMode, color: tint)
            XCTAssertTrue(result)
        }
        pass.end()
        // Later mutations must not change the resources of already recorded draws.
        context.bindingSet2.setTexture(textures[0], binding: 0)
        context.bindingSet2.setTexture(textures[0], binding: 1)
        try waitForCompletion(context.commandBuffer)
        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.sourceTexture))
        let pointer = try XCTUnwrap(staging.contents())
        return Array(UnsafeRawBufferPointer(start: pointer, count: 32 * 32 * 4))
    }

    func testBlendPreservesModesSamplingOpacityAndMSAAOnGPU() throws {
        let device = try makeDeviceContext()
        let textures = try makePatternTextures(device)
        for msaa in [false, true] {
            var normalOutputs: [[UInt8]] = []
            for rawValue in Int32(0)...28 {
                var outputs: [[UInt8]] = []
                for varied in [false, true] {
                    let expected = try renderBlendSequence(
                        deviceContext: device, textures: textures, blendMode: .init(rawValue: rawValue),
                        varied: varied, msaa: msaa, reference: true)
                    let actual = try renderBlendSequence(
                        deviceContext: device, textures: textures, blendMode: .init(rawValue: rawValue),
                        varied: varied, msaa: msaa, reference: false)
                    XCTAssertEqual(actual, expected)
                    if rawValue == 0 || rawValue == 17 || rawValue == 28 {
                        let colors = Set(stride(from: 0, to: actual.count, by: 4).map {
                            Array(actual[$0..<($0 + 4)])
                        })
                        XCTAssertGreaterThan(colors.count, 4)
                        XCTAssertTrue(colors.contains { $0[3] > 0 })
                    }
                    outputs.append(actual)
                }
                if rawValue == 0 { normalOutputs = outputs }
                if rawValue == 28 { XCTAssertEqual(outputs, normalOutputs) }
                if rawValue == 0 || rawValue == 17 {
                    XCTAssertNotEqual(outputs[0], outputs[1])
                }
            }
        }
    }
}

private extension GraphicsContext {
    func referenceBlendTexturesCommand(renderPass: RenderPass,
                                    source: Texture,
                                    backdrop: Texture,
                                    textureFrame: CGRect,
                                    blendMode: BlendMode,
                                    color: BackendColor) -> Bool {
        if source.dimensions != backdrop.dimensions {
            Log.error("GraphicsContext.encodeBlendTexturesCommand failed.")
            return false
        }

        let shader: _Shader
        switch blendMode {
        case .normal:           shader = .blendNormal
        case .multiply:         shader = .blendMultiply
        case .screen:           shader = .blendScreen
        case .overlay:          shader = .blendOverlay
        case .darken:           shader = .blendDarken
        case .lighten:          shader = .blendLighten
        case .colorDodge:       shader = .blendColorDodge
        case .colorBurn:        shader = .blendColorBurn
        case .softLight:        shader = .blendSoftLight
        case .hardLight:        shader = .blendHardLight
        case .difference:       shader = .blendDifference
        case .exclusion:        shader = .blendExclusion
        case .hue:              shader = .blendHue
        case .saturation:       shader = .blendSaturation
        case .color:            shader = .blendColor
        case .luminosity:       shader = .blendLuminosity
        case .clear:            shader = .blendClear
        case .copy:             shader = .blendCopy
        case .sourceIn:         shader = .blendSourceIn
        case .sourceOut:        shader = .blendSourceOut
        case .sourceAtop:       shader = .blendSourceAtop
        case .destinationOver:  shader = .blendDestinationOver
        case .destinationIn:    shader = .blendDestinationIn
        case .destinationOut:   shader = .blendDestinationOut
        case .destinationAtop:  shader = .blendDestinationAtop
        case .xor:              shader = .blendXor
        case .plusDarker:       shader = .blendPlusDarker
        case .plusLighter:      shader = .blendPlusLighter
        default:                shader = .blendNormal
        }

        let color = color.float4
        let makeVertex = { (x: Scalar, y: Scalar, u: Scalar, v: Scalar) in
            _Vertex(position: Vector2(x, y).float2,
                    texcoord: Vector2(u, v).float2,
                    color: color)
        }

        let invW = 1.0 / CGFloat(source.width)
        let invH = 1.0 / CGFloat(source.height)
        let u1 = textureFrame.minX * invW
        let u2 = textureFrame.maxX * invW
        let v1 = textureFrame.minY * invH
        let v2 = textureFrame.maxY * invH
        let vertices = [
            makeVertex(-1, -1, u1, v2),
            makeVertex(-1,  1, u1, v1),
            makeVertex( 1, -1, u2, v2),
            makeVertex( 1, -1, u2, v2),
            makeVertex(-1,  1, u1, v1),
            makeVertex( 1,  1, u2, v1)
        ]

        guard let renderState = pipeline.renderState(
            shader: shader,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: .opaque,
            sampleCount: renderPass.sampleCount) else {
            Log.err("GraphicsContext error: pipeline.renderState failed.")
            return false
        }
        guard let depthState = pipeline.depthStencilState(.ignore) else {
            Log.err("GraphicsContext error: pipeline.depthStencilState failed.")
            return false
        }
        guard let vertexBuffer = self.makeBuffer(vertices) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return false
        }

        let encoder = renderPass.encoder
        encoder.setRenderPipelineState(renderState)
        encoder.setDepthStencilState(depthState)
        self.bindingSet2.setTexture(source, binding: 0)
        self.bindingSet2.setTexture(backdrop, binding: 1)
        encoder.setResource(self.bindingSet2, index: 0)

        encoder.setCullMode(.none)
        encoder.setVertexBuffer(
            vertexBuffer.buffer,
            offset: vertexBuffer.offset,
            index: 0
        )

        encoder.draw(vertexStart: 0,
                     vertexCount: vertices.count,
                     instanceCount: 1,
                     baseInstance: 0)
        return true
    }
}
