import Foundation
import XCTest
import VVD
@testable import VUI

final class GraphicsContextTextureGeometryTests: XCTestCase {
    private final class CaptureEncoder: RenderCommandEncoder {
        var isCompleted = false
        var commandBuffer: CommandBuffer { fatalError("Only vertex uploads are captured") }
        private var buffer: GPUBuffer?
        private var offset = 0
        var vertices: [_Vertex] = []
        var drawCount = 0

        func endEncoding() { isCompleted = true }
        func waitEvent(_ event: GPUEvent) {}
        func signalEvent(_ event: GPUEvent) {}
        func waitSemaphoreValue(_ semaphore: GPUSemaphore, value: UInt64) {}
        func signalSemaphoreValue(_ semaphore: GPUSemaphore, value: UInt64) {}
        func setResource(_ resource: ShaderBindingSet, index: Int) {}
        func setViewport(_ viewport: Viewport) {}
        func setScissorRect(_ rect: ScissorRect) {}
        func setRenderPipelineState(_ state: RenderPipelineState) {}
        func setVertexBuffer(_ buffer: GPUBuffer, offset: Int, index: Int) {
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

    private func capture(
        context: GraphicsContext,
        texture: Texture,
        frame: CGRect,
        transform: CGAffineTransform,
        textureFrame: CGRect,
        textureTransform: CGAffineTransform,
        color: BackendColor,
        reference: Bool
    ) -> [UInt32] {
        let encoder = CaptureEncoder()
        let pass = GraphicsContext.RenderPass(
            encoder: encoder,
            descriptor: RenderPassDescriptor(colorAttachments: [
                .init(renderTarget: context.sourceTexture)
            ]), sampleCount: 1)
        if reference {
            context.referenceDrawTextureCommand(
                renderPass: pass, texture: texture, frame: frame, transform: transform,
                textureFrame: textureFrame, textureTransform: textureTransform,
                blendState: .opaque, color: color)
        } else {
            context.encodeDrawTextureCommand(
                renderPass: pass, texture: texture, frame: frame, transform: transform,
                textureFrame: textureFrame, textureTransform: textureTransform,
                blendState: .opaque, color: color)
        }
        pass.end()
        XCTAssertEqual(encoder.drawCount, 1)
        XCTAssertEqual(encoder.vertices.count, 6)
        XCTAssertEqual(MemoryLayout<_Vertex>.stride, 8 * MemoryLayout<Float>.stride)
        return encoder.vertices.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
    }

    func testTextureQuadPreservesVertexBitsAcrossRectsAndTransforms() throws {
        let device = try makeDeviceContext()
        var context = try makeContext(device)
        let texture = try XCTUnwrap(device.device.makeTexture(descriptor: .init(
            textureType: .type2D, pixelFormat: .rgba8Unorm,
            width: 7, height: 13, usage: .sampled)))
        let frames: [CGRect] = [
            CGRect(x: -3.5, y: 2.25, width: 37.75, height: 18.125),
            CGRect(x: 16, y: -7, width: -32, height: 9),
            CGRect(x: 8, y: 12, width: 3, height: -5),
            .zero, .null, .infinite
        ]
        let textureFrames: [CGRect] = [
            CGRect(x: 0, y: 0, width: 7, height: 13),
            CGRect(x: -2.5, y: 4.25, width: 11.75, height: 18.125),
            CGRect(x: 7, y: 13, width: -7, height: -13),
            .zero
        ]
        let transforms: [CGAffineTransform] = [
            .identity,
            .init(a: -0.75, b: 0.375, c: 0.125, d: 1.25, tx: 13, ty: -7),
            .init(a: 0.03125, b: -3.25, c: 1.625, d: 0.125,
                  tx: 10_000_000_000.25, ty: -10_000_000_000.75),
            .init(a: 0, b: 0, c: 0, d: 0, tx: -0.0, ty: 0)
        ]
        for contextTransform in transforms.prefix(3) {
            context.transform = contextTransform
            for transform in transforms {
                for textureTransform in transforms {
                    for frame in frames {
                        for textureFrame in textureFrames {
                            let expected = capture(
                                context: context, texture: texture, frame: frame, transform: transform,
                                textureFrame: textureFrame, textureTransform: textureTransform,
                                color: BackendColor(0.25, 0.5, 0.75, 0.375), reference: true)
                            let actual = capture(
                                context: context, texture: texture, frame: frame, transform: transform,
                                textureFrame: textureFrame, textureTransform: textureTransform,
                                color: BackendColor(0.25, 0.5, 0.75, 0.375), reference: false)
                            XCTAssertEqual(actual, expected)
                            XCTAssertEqual(Array(actual[8..<16]), Array(actual[32..<40]))
                            XCTAssertEqual(Array(actual[16..<24]), Array(actual[24..<32]))
                        }
                    }
                }
            }
        }
    }

    func testTextureQuadPreservesRawTintComponentBits() throws {
        let device = try makeDeviceContext()
        let context = try makeContext(device)
        let texture = try XCTUnwrap(device.device.makeTexture(descriptor: .init(
            textureType: .type2D, pixelFormat: .rgba8Unorm,
            width: 8, height: 8, usage: .sampled)))
        let colors: [BackendColor] = [
            .clear, .white, .init(-0.0, 1.5, -2.5, 0.125),
            .init(.nan, -.infinity, .infinity, -0.0)
        ]
        for color in colors {
            let frame = CGRect(x: 0, y: 0, width: 8, height: 8)
            let expected = capture(context: context, texture: texture, frame: frame,
                                   transform: .identity, textureFrame: frame,
                                   textureTransform: .identity, color: color, reference: true)
            let actual = capture(context: context, texture: texture, frame: frame,
                                 transform: .identity, textureFrame: frame,
                                 textureTransform: .identity, color: color, reference: false)
            XCTAssertEqual(actual, expected)
            let value = color.float4
            let words = [value.0.bitPattern, value.1.bitPattern, value.2.bitPattern, value.3.bitPattern]
            for index in 0..<6 {
                XCTAssertEqual(Array(actual[(index * 8 + 4)..<(index * 8 + 8)]), words)
            }
        }
    }

    func testTextureQuadReevaluatesCopiesAndLayerTransforms() throws {
        let device = try makeDeviceContext()
        let root = try makeContext(device)
        let textures = try [(8, 16), (17, 7)].map { width, height in
            try XCTUnwrap(device.device.makeTexture(descriptor: .init(
                textureType: .type2D, pixelFormat: .rgba8Unorm,
                width: width, height: height, usage: .sampled)))
        }
        var copy = root
        copy.transform = .init(a: -1, b: 0.25, c: 0.5, d: 1, tx: 15, ty: -7)
        let layer = try XCTUnwrap(root.makeLayerContext(CGSize(width: 24, height: 18)))
        var results: [[UInt32]] = []
        for context in [root, copy, layer, copy, root] {
            let texture = textures[results.count % 2]
            let frame = CGRect(x: 2.5, y: 3.75, width: 11, height: 9)
            let textureFrame = CGRect(x: 1, y: 2, width: 7, height: 5)
            let expected = capture(context: context, texture: texture, frame: frame,
                                   transform: .identity, textureFrame: textureFrame,
                                   textureTransform: .identity, color: .white, reference: true)
            let actual = capture(context: context, texture: texture, frame: frame,
                                 transform: .identity, textureFrame: textureFrame,
                                 textureTransform: .identity, color: .white, reference: false)
            XCTAssertEqual(actual, expected)
            results.append(actual)
        }
        XCTAssertEqual(results[0], results[4])
        XCTAssertEqual(results[1], results[3])
        XCTAssertNotEqual(results[0], results[1])
        XCTAssertNotEqual(results[0], results[2])
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
            [255, 0, 0, 255], [0, 255, 0, 255],
            [0, 0, 255, 255], [128, 128, 0, 128]
        ]
        var textures: [Texture] = []
        for index in 0..<2 {
            let texture = try XCTUnwrap(device.makeTexture(descriptor: .init(
                textureType: .type2D, pixelFormat: .rgba8Unorm,
                width: 4, height: 4, usage: [.sampled, .copyDestination])))
            let bytes = (0..<16).flatMap { pixel in
                palette[(pixel + pixel / 4 + index) % 4]
            }
            let buffer = try XCTUnwrap(device.makeBuffer(
                length: bytes.count, storageMode: .shared, cpuCacheMode: .writeCombined))
            let pointer = try XCTUnwrap(buffer.contents())
            bytes.withUnsafeBytes { pointer.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            buffer.flush()
            encoder.copy(from: buffer,
                         sourceOffset: BufferImageOrigin(offset: 0, imageWidth: 4, imageHeight: 4),
                         to: texture,
                         destinationOffset: TextureOrigin(layer: 0, level: 0, x: 0, y: 0, z: 0),
                         size: TextureSize(width: 4, height: 4, depth: 1))
            textures.append(texture)
        }
        encoder.endEncoding()
        try waitForCompletion(commands)
        return textures
    }

    private func renderTextureSequence(
        deviceContext: GraphicsDeviceContext,
        textures: [Texture],
        transformed: Bool,
        blended: Bool,
        msaa: Bool,
        reference: Bool
    ) throws -> [UInt8] {
        var context = try makeContext(deviceContext)
        if transformed {
            context.transform = .init(a: 0.875, b: 0.25, c: -0.125, d: 0.75, tx: 5, ty: 0)
        }
        let pass = try XCTUnwrap(context.beginRenderPass(
            viewport: context.viewport, renderTarget: context.sourceTexture,
            loadAction: .clear,
            clearColor: blended ? BackendColor(0.125, 0.25, 0.375, 0.5) : .clear,
            useStencil: false, useMSAA: msaa))
        let frames = [
            CGRect(x: 2.25, y: 4.75, width: 23.5, height: 20.25),
            CGRect(x: 28, y: 15, width: -12, height: -9),
            CGRect(x: -3, y: 20, width: 16, height: 7)
        ]
        for (index, frame) in frames.enumerated() {
            let local: CGAffineTransform = transformed
                ? .init(a: -0.875, b: 0.125, c: 0.25, d: 0.75, tx: 24, ty: 2)
                : .identity
            let uv: CGAffineTransform = index == 1
                ? .init(a: -1, b: 0.125, c: 0.25, d: 1, tx: 1, ty: -0.25)
                : .identity
            let textureFrame = index == 2
                ? CGRect(x: -1, y: 1, width: 6, height: 4)
                : CGRect(x: 0.25, y: 0.5, width: 3.5, height: 3)
            let color = index == 1 ? BackendColor(0.5, 0.375, 0.25, 0.5) : .white
            let blend: BlendState = blended ? .premultipliedAlphaBlend : .opaque
            if reference {
                context.referenceDrawTextureCommand(
                    renderPass: pass, texture: textures[index % 2], frame: frame,
                    transform: local, textureFrame: textureFrame, textureTransform: uv,
                    blendState: blend, color: color)
            } else {
                context.encodeDrawTextureCommand(
                    renderPass: pass, texture: textures[index % 2], frame: frame,
                    transform: local, textureFrame: textureFrame, textureTransform: uv,
                    blendState: blend, color: color)
            }
        }
        pass.end()
        try waitForCompletion(context.commandBuffer)
        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.sourceTexture))
        let pointer = try XCTUnwrap(staging.contents())
        return Array(UnsafeRawBufferPointer(start: pointer, count: 32 * 32 * 4))
    }

    func testTextureQuadPreservesSamplingTintBlendAndMSAAOnGPU() throws {
        let device = try makeDeviceContext()
        let textures = try makePatternTextures(device)
        for msaa in [false, true] {
            for blended in [false, true] {
                var outputs: [[UInt8]] = []
                for transformed in [false, true] {
                    let expected = try renderTextureSequence(
                        deviceContext: device, textures: textures, transformed: transformed,
                        blended: blended, msaa: msaa, reference: true)
                    let actual = try renderTextureSequence(
                        deviceContext: device, textures: textures, transformed: transformed,
                        blended: blended, msaa: msaa, reference: false)
                    XCTAssertEqual(actual, expected)
                    let colors = Set(stride(from: 0, to: actual.count, by: 4).map {
                        Array(actual[$0..<($0 + 4)])
                    })
                    XCTAssertGreaterThan(colors.count, 4)
                    XCTAssertTrue(colors.contains { $0[3] > 0 })
                    outputs.append(actual)
                }
                XCTAssertNotEqual(outputs[0], outputs[1])
            }
        }
    }
}

private extension GraphicsContext {
    func referenceDrawTextureCommand(renderPass: RenderPass,
                                  texture: Texture,
                                  frame: CGRect,
                                  transform: CGAffineTransform = .identity,
                                  textureFrame: CGRect,
                                  textureTransform: CGAffineTransform = .identity,
                                  blendState: BlendState,
                                  color: BackendColor) {
        let trans = transform
            .concatenating(self.transform)
            .concatenating(self.viewTransform)
        let makeVertex = { (x: Scalar, y: Scalar, u: Scalar, v: Scalar) in
            _Vertex(position: Vector2(x, y).applying(trans).float2,
                    texcoord: Vector2(u, v).applying(textureTransform).float2,
                    color: color.float4)
        }

        let invW = 1.0 / CGFloat(texture.width)
        let invH = 1.0 / CGFloat(texture.height)

        let uvMinX = textureFrame.minX * invW
        let uvMaxX = textureFrame.maxX * invW
        let uvMinY = textureFrame.minY * invH
        let uvMaxY = textureFrame.maxY * invH

        let vertices: [_Vertex] = [
            makeVertex(frame.minX, frame.maxY, uvMinX, uvMaxY), // left bottom
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY), // left top
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY), // right bottom
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY), // right bottom
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY), // left top
            makeVertex(frame.maxX, frame.minY, uvMaxX, uvMinY), // right top
        ]

        self.encodeDrawCommand(renderPass: renderPass,
                               shader: .image,
                               stencil: .ignore,
                               vertices: vertices,
                               texture: texture,
                               blendState: blendState)
    }
}
