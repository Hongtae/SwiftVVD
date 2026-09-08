import Foundation
import XCTest
import VVD
@testable import VUI

private typealias ProjectionTransform = VUI.ProjectionTransform

private func projectionConstantBytes(_ transform: ProjectionTransform) -> [UInt8] {
    // The shader matrix uses three 16-byte vectors, not the host CGFloat layout.
    let components: [Float32] = [
        Float32(transform.m11), Float32(transform.m12), Float32(transform.m13), 0,
        Float32(transform.m21), Float32(transform.m22), Float32(transform.m23), 0,
        Float32(transform.m31), Float32(transform.m32), Float32(transform.m33), 0,
    ]
    return components.withUnsafeBytes { Array($0) }
}

final class GraphicsContextFilterGeometryTests: XCTestCase {
    private final class CaptureEncoder: RenderCommandEncoder {
        var isCompleted = false
        var commandBuffer: CommandBuffer { fatalError("Only vertex uploads are captured") }
        private var buffer: GPUBuffer?
        private var offset = 0
        var vertices: [_Vertex] = []
        var drawCount = 0
        var constants: [[UInt8]] = []

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
        func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: Int, data: D) {
            XCTAssertEqual(stages, .fragment)
            XCTAssertEqual(offset, 0)
            constants.append(Array(data))
        }
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

    private enum Operation {
        case matrix(ColorMatrix)
        case projection(ProjectionTransform)
        case blur(CGFloat, Int)
    }

    private struct Snapshot: Equatable {
        var vertices: [UInt32]
        var constants: [[UInt8]]
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

    private func encode(
        _ operation: Operation, context: GraphicsContext, renderPass: GraphicsContext.RenderPass,
        texture: Texture, frame: CGRect, textureFrame: CGRect,
        blend: BlendState = .opaque, color: BackendColor, reference: Bool
    ) -> Bool {
        switch operation {
        case let .matrix(matrix):
            if reference {
                return context.referenceColorMatrixFilter(renderPass: renderPass,
                frame: frame, texture: texture, textureFrame: textureFrame,
                colorMatrix: matrix, blendState: blend, color: color)
            }
            return context.encodeColorMatrixFilter(renderPass: renderPass,
                frame: frame, texture: texture, textureFrame: textureFrame,
                colorMatrix: matrix, blendState: blend, color: color)
        case let .projection(projection):
            if reference {
                return context.referenceProjectionTransformFilter(renderPass: renderPass,
                texture: texture, textureFrame: textureFrame,
                projectionTransform: projection, blendState: blend, color: color)
            }
            return context.encodeProjectionTransformFilter(renderPass: renderPass,
                texture: texture, textureFrame: textureFrame,
                projectionTransform: projection, blendState: blend, color: color)
        case let .blur(radius, pass):
            if reference {
                return context.referenceBlurFilter(renderPass: renderPass,
                texture: texture, textureFrame: textureFrame,
                radius: radius, options: [], blurPass: pass, blendState: blend, color: color)
            }
            return context.encodeBlurFilter(renderPass: renderPass,
                texture: texture, textureFrame: textureFrame,
                radius: radius, options: [], blurPass: pass, blendState: blend, color: color)
        }
    }

    private func capture(
        _ operation: Operation, context: GraphicsContext, texture: Texture,
        frame: CGRect, textureFrame: CGRect, color: BackendColor, reference: Bool
    ) -> Snapshot {
        let encoder = CaptureEncoder()
        let pass = GraphicsContext.RenderPass(
            encoder: encoder,
            descriptor: RenderPassDescriptor(colorAttachments: [
                .init(renderTarget: context.sourceTexture)
            ]), sampleCount: 1)
        XCTAssertTrue(encode(
            operation, context: context, renderPass: pass, texture: texture,
            frame: frame, textureFrame: textureFrame, color: color, reference: reference))
        pass.end()
        XCTAssertEqual(encoder.drawCount, 1)
        XCTAssertEqual(encoder.vertices.count, 6)
        XCTAssertEqual(encoder.constants.count, 1)
        XCTAssertEqual(MemoryLayout<_Vertex>.stride, 8 * MemoryLayout<Float>.stride)
        return Snapshot(
            vertices: encoder.vertices.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) },
            constants: encoder.constants)
    }

    private var frames: [CGRect] {
        [
            CGRect(x: -3.5, y: 2.25, width: 37.75, height: 18.125),
            CGRect(x: 16, y: -7, width: -32, height: 9),
            CGRect(x: 8, y: 12, width: 3, height: -5),
            .zero, .null, .infinite
        ]
    }

    private var colors: [BackendColor] {
        [.clear, .white, .init(-0.0, 1.5, -2.5, 0.125),
         .init(.nan, -.infinity, .infinity, -0.0)]
    }

    private func makeTexture(_ device: GraphicsDevice, width: Int, height: Int) throws -> Texture {
        try XCTUnwrap(device.makeTexture(descriptor: .init(
            textureType: .type2D, pixelFormat: .rgba8Unorm,
            width: width, height: height, usage: .sampled)))
    }

    private func assertColorBits(_ snapshot: Snapshot, color: BackendColor) {
        let value = color.float4
        let words = [value.0.bitPattern, value.1.bitPattern, value.2.bitPattern, value.3.bitPattern]
        XCTAssertEqual(snapshot.vertices.count, 48)
        guard snapshot.vertices.count == 48 else { return }
        for index in 0..<6 {
            XCTAssertEqual(Array(snapshot.vertices[(index * 8 + 4)..<(index * 8 + 8)]), words)
        }
        XCTAssertEqual(Array(snapshot.vertices[8..<16]), Array(snapshot.vertices[32..<40]))
        XCTAssertEqual(Array(snapshot.vertices[16..<24]), Array(snapshot.vertices[24..<32]))
    }

    func testColorMatrixPreservesVertexAndConstantBitsAcrossFrames() throws {
        let device = try makeDeviceContext()
        var context = try makeContext(device)
        let texture = try makeTexture(device.device, width: 7, height: 13)
        let transforms: [CGAffineTransform] = [
            context.viewTransform,
            .init(a: -0.75, b: 0.375, c: 0.125, d: 1.25, tx: 13, ty: -7),
            .init(a: 0.03125, b: -3.25, c: 1.625, d: 0.125,
                  tx: 10_000_000_000.25, ty: -10_000_000_000.75),
            .init(a: 0, b: 0, c: 0, d: 0, tx: -0.0, ty: 0)
        ]
        var matrix = ColorMatrix.identity
        matrix.r1 = -0.5
        matrix.g3 = 0.75
        matrix.b5 = -0.0
        matrix.a4 = 0.375
        let constants = withUnsafeBytes(of: matrix) { Array($0) }
        for transform in transforms {
            context.viewTransform = transform
            for frame in frames {
                for textureFrame in frames {
                    for color in colors {
                        let expected = capture(.matrix(matrix), context: context, texture: texture,
                                               frame: frame, textureFrame: textureFrame,
                                               color: color, reference: true)
                        let actual = capture(.matrix(matrix), context: context, texture: texture,
                                             frame: frame, textureFrame: textureFrame,
                                             color: color, reference: false)
                        XCTAssertEqual(actual, expected)
                        XCTAssertEqual(actual.constants, [constants])
                        assertColorBits(actual, color: color)
                    }
                }
            }
        }
    }

    func testFullscreenFiltersPreserveVertexAndConstantBits() throws {
        let device = try makeDeviceContext()
        let context = try makeContext(device)
        let texture = try makeTexture(device.device, width: 17, height: 31)
        var projective = ProjectionTransform()
        projective.m13 = 0.125
        projective.m23 = -0.0625
        projective.m31 = -0.0
        let projections = [
            ProjectionTransform(),
            ProjectionTransform(CGAffineTransform(a: -0.75, b: 0.125, c: 0.25, d: 1.25, tx: 0.5, ty: -0.25)),
            projective
        ]
        var cases: [(Operation, [UInt8])] = projections.map { projection in
            let constants = projectionConstantBytes(projection)
            XCTAssertEqual(constants.count, 48)
            return (.projection(projection), constants)
        }
        for radius: CGFloat in [-0.0, 0.375, 2.5, .nan, .infinity] {
            for pass in 0..<6 {
                let parameters: [Float] = [17, 31, pass % 2 == 0 ? Float(radius) : 0,
                                          pass % 2 == 0 ? 0 : Float(radius)]
                cases.append((.blur(radius, pass), parameters.withUnsafeBytes { Array($0) }))
            }
        }
        for (operation, constants) in cases {
            for textureFrame in frames {
                for color in colors {
                    let expected = capture(operation, context: context, texture: texture,
                                           frame: .zero, textureFrame: textureFrame,
                                           color: color, reference: true)
                    let actual = capture(operation, context: context, texture: texture,
                                         frame: .zero, textureFrame: textureFrame,
                                         color: color, reference: false)
                    XCTAssertEqual(actual, expected)
                    XCTAssertEqual(actual.constants, [constants])
                    assertColorBits(actual, color: color)
                }
            }
        }
    }

    func testFilterGeometryReevaluatesCopiesLayersAndMixedDraws() throws {
        let device = try makeDeviceContext()
        let root = try makeContext(device)
        var copy = root
        copy.contentOffset = CGPoint(x: 5, y: -3)
        let layer = try XCTUnwrap(root.makeLayerContext(CGSize(width: 24, height: 18)))
        let textures = try [(8, 16), (17, 7)].map {
            try makeTexture(device.device, width: $0.0, height: $0.1)
        }
        var matrixResults: [Snapshot] = []
        for context in [root, copy, layer, copy, root] {
            let texture = textures[matrixResults.count % 2]
            let operations: [Operation] = [.matrix(.identity), .projection(ProjectionTransform()), .blur(1.25, 1)]
            for (index, operation) in operations.enumerated() {
                let frame = CGRect(x: 2.5, y: 3.75, width: 11, height: 9)
                let textureFrame = CGRect(x: 1, y: 2, width: 7, height: 5)
                let expected = capture(operation, context: context, texture: texture,
                                       frame: frame, textureFrame: textureFrame,
                                       color: .white, reference: true)
                let actual = capture(operation, context: context, texture: texture,
                                     frame: frame, textureFrame: textureFrame,
                                     color: .white, reference: false)
                XCTAssertEqual(actual, expected)
                if index == 0 { matrixResults.append(actual) }
            }
        }
        XCTAssertEqual(matrixResults[0], matrixResults[4])
        XCTAssertEqual(matrixResults[1], matrixResults[3])
        XCTAssertNotEqual(matrixResults[0], matrixResults[1])
        XCTAssertNotEqual(matrixResults[0], matrixResults[2])
    }

    private func renderFilterSequence(
        deviceContext: GraphicsDeviceContext, textures: [Texture],
        kind: Int, varied: Bool, blended: Bool, msaa: Bool, reference: Bool
    ) throws -> [UInt8] {
        var context = try makeContext(deviceContext)
        if varied { context.contentOffset = CGPoint(x: 1.25, y: -0.75) }
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
            let textureFrame = index == 2
                ? CGRect(x: -1, y: 1, width: 6, height: 4)
                : CGRect(x: 0.25, y: 0.5, width: 3.5, height: 3)
            let color: BackendColor = varied
                ? .init(0.375, 0.25, 0.5, 0.5)
                : (index == 1 ? .init(0.5, 0.375, 0.25, 0.5) : .white)
            let operation: Operation
            if kind == 0 {
                var matrix = ColorMatrix.identity
                matrix.r1 = 0.75
                matrix.g3 = Float(index) * 0.125
                matrix.b5 = 0.125
                matrix.a4 = varied ? 0.75 : 1
                operation = .matrix(matrix)
            } else if kind == 1 {
                var projection = ProjectionTransform()
                projection.m13 = varied ? 0.125 : 0
                projection.m23 = varied ? -0.0625 : 0
                operation = .projection(projection)
            } else {
                operation = .blur(CGFloat(index + 1) * 0.375, varied ? 1 : 0)
            }
            XCTAssertTrue(encode(
                operation, context: context, renderPass: pass,
                texture: textures[index % 2], frame: frame, textureFrame: textureFrame,
                blend: blended ? .premultipliedAlphaBlend : .opaque,
                color: color, reference: reference))
        }
        pass.end()
        try waitForCompletion(context.commandBuffer)
        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.sourceTexture))
        let pointer = try XCTUnwrap(staging.contents())
        return Array(UnsafeRawBufferPointer(start: pointer, count: 32 * 32 * 4))
    }

    func testFiltersPreserveSampledTintedBlendedAndMSAAOutputOnGPU() throws {
        let device = try makeDeviceContext()
        let textures = try makePatternTextures(device)
        for kind in 0..<3 {
            for msaa in [false, true] {
                for blended in [false, true] {
                    var outputs: [[UInt8]] = []
                    for varied in [false, true] {
                        let expected = try renderFilterSequence(
                            deviceContext: device, textures: textures, kind: kind, varied: varied,
                            blended: blended, msaa: msaa, reference: true)
                        let actual = try renderFilterSequence(
                            deviceContext: device, textures: textures, kind: kind, varied: varied,
                            blended: blended, msaa: msaa, reference: false)
                        XCTAssertEqual(actual, expected)
                        let colors = Set(stride(from: 0, to: actual.count, by: 4).map {
                            Array(actual[$0..<($0 + 4)])
                        })
                        XCTAssertTrue(colors.contains { $0[3] > 0 })
                        if kind != 1 { XCTAssertGreaterThan(colors.count, 4) }
                        outputs.append(actual)
                    }
                    XCTAssertNotEqual(outputs[0], outputs[1])
                }
            }
        }
    }
}

private extension GraphicsContext {
    func referenceProjectionTransformFilter(renderPass: RenderPass,
                                         texture: Texture,
                                         textureFrame: CGRect,
                                         projectionTransform: ProjectionTransform,
                                         blendState: BlendState,
                                         color: BackendColor) -> Bool {

        let invW = 1.0 / CGFloat(texture.width)
        let invH = 1.0 / CGFloat(texture.height)
        let uvMinX = Float(textureFrame.minX * invW)
        let uvMaxX = Float(textureFrame.maxX * invW)
        let uvMinY = Float(textureFrame.minY * invH)
        let uvMaxY = Float(textureFrame.maxY * invH)

        let makeVertex = { x, y, u, v in
            _Vertex(position: (x, y), texcoord: (u, v), color: color.float4)
        }
        let vertices: [_Vertex] = [
            makeVertex(-1, -1, uvMinX, uvMaxY), // left bottom
            makeVertex(-1,  1, uvMinX, uvMinY), // left top
            makeVertex( 1, -1, uvMaxX, uvMaxY), // right bottom
            makeVertex( 1, -1, uvMaxX, uvMaxY), // right bottom
            makeVertex(-1,  1, uvMinX, uvMinY), // left top
            makeVertex( 1,  1, uvMaxX, uvMinY), // right top
        ]

        guard let renderState = pipeline.renderState(
            shader: .filterProjectionTransform,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: blendState,
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

        self.bindingSet1.setTexture(texture, binding: 0)
        encoder.setResource(self.bindingSet1, index: 0)

        encoder.pushConstant(
            stages: .fragment, offset: 0,
            data: projectionConstantBytes(projectionTransform)
        )
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

    func referenceColorMatrixFilter(renderPass: RenderPass,
                                 frame: CGRect,
                                 texture: Texture,
                                 textureFrame: CGRect,
                                 colorMatrix: ColorMatrix,
                                 blendState: BlendState,
                                 color: BackendColor) -> Bool {
        let invW = 1.0 / CGFloat(texture.width)
        let invH = 1.0 / CGFloat(texture.height)
        let uvMinX = Float(textureFrame.minX * invW)
        let uvMaxX = Float(textureFrame.maxX * invW)
        let uvMinY = Float(textureFrame.minY * invH)
        let uvMaxY = Float(textureFrame.maxY * invH)

        let makeVertex = { (x: Scalar, y: Scalar, u: Float, v: Float) in
            _Vertex(position: Vector2(x, y).applying(self.viewTransform).float2,
                    texcoord: (u, v), color: color.float4)
        }
        let frame = frame.standardized
        let vertices: [_Vertex] = [
            makeVertex(frame.minX, frame.maxY, uvMinX, uvMaxY), // left bottom
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY), // left top
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY), // right bottom
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY), // right bottom
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY), // left top
            makeVertex(frame.maxX, frame.minY, uvMaxX, uvMinY), // right top
        ]

        guard let renderState = pipeline.renderState(
            shader: .filterColorMatrix,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: blendState,
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

        self.bindingSet1.setTexture(texture, binding: 0)
        encoder.setResource(self.bindingSet1, index: 0)

        withUnsafeBytes(of: colorMatrix) {
            encoder.pushConstant(stages: .fragment, offset: 0, data: $0)
        }
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

    func referenceBlurFilter(renderPass: RenderPass,
                          texture: Texture,
                          textureFrame: CGRect,
                          radius: CGFloat,
                          options: BlurOptions,
                          blurPass: Int,
                          blendState: BlendState,
                          color: BackendColor) -> Bool {
        struct PushConstant {
            var resolution: Float2
            var direction: Float2
        }
        let radius = Float(radius)
        let blurDirection = blurPass % 2 == 0 ? (radius, 0) : (0, radius)
        let blurParameters = PushConstant(
                            resolution: (Float(texture.width),
                                         Float(texture.height)),
                            direction: blurDirection)

        let invW = 1.0 / CGFloat(texture.width)
        let invH = 1.0 / CGFloat(texture.height)
        let uvMinX = Float(textureFrame.minX * invW)
        let uvMaxX = Float(textureFrame.maxX * invW)
        let uvMinY = Float(textureFrame.minY * invH)
        let uvMaxY = Float(textureFrame.maxY * invH)
        let makeVertex = { x, y, u, v in
            _Vertex(position: (x, y), texcoord: (u, v), color: color.float4)
        }
        let vertices: [_Vertex] = [
            makeVertex(-1, -1, uvMinX, uvMaxY), // left bottom
            makeVertex(-1,  1, uvMinX, uvMinY), // left top
            makeVertex( 1, -1, uvMaxX, uvMaxY), // right bottom
            makeVertex( 1, -1, uvMaxX, uvMaxY), // right bottom
            makeVertex(-1,  1, uvMinX, uvMinY), // left top
            makeVertex( 1,  1, uvMaxX, uvMinY), // right top
        ]

        guard let renderState = pipeline.renderState(
            shader: .filterBlur,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: blendState,
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

        self.bindingSet1.setTexture(texture, binding: 0)
        encoder.setResource(self.bindingSet1, index: 0)

        withUnsafeBytes(of: blurParameters) {
            encoder.pushConstant(stages: .fragment, offset: 0, data: $0)
        }
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
