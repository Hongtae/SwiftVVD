import Foundation
import XCTest
import VVD
@testable import VUI

final class GraphicsContextSamplerBindingTests: XCTestCase {
    private func waitForCompletion(_ buffer: CommandBuffer) throws {
        let condition = NSCondition()
        var completed = false
        buffer.addCompletedHandler { _ in
            condition.lock()
            completed = true
            condition.broadcast()
            condition.unlock()
        }
        condition.lock()
        defer { condition.unlock() }
        XCTAssertTrue(buffer.commit())
        let timeout = Date(timeIntervalSinceNow: 5)
        while !completed {
            if !condition.wait(until: timeout) {
                XCTFail("GPU command buffer timed out")
                break
            }
        }
    }

    private func renderTextureChanges(
        deviceContext: GraphicsDeviceContext,
        dual: Bool,
        initializeOnce: Bool
    ) throws -> [UInt8] {
        let device = deviceContext.device
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let buffer = try XCTUnwrap(queue.makeCommandBuffer())
        let pipeline = try XCTUnwrap(GraphicsPipelineStates.sharedInstance(commandQueue: queue))
        let colors: [BackendColor] = [
            .init(0.5, 0.0, 0.0, 0.5), .init(0.0, 0.5, 0.0, 0.5),
            .init(0.0, 0.0, 1.0, 1.0), .init(1.0, 1.0, 0.0, 1.0)
        ]
        var textures: [Texture] = []
        for color in colors {
            let texture = try XCTUnwrap(device.makeTexture(descriptor: .init(
                textureType: .type2D, pixelFormat: .rgba8Unorm,
                width: 2, height: 2, usage: [.renderTarget, .sampled])))
            let clear = try XCTUnwrap(buffer.makeRenderCommandEncoder(descriptor: .init(
                colorAttachments: [.init(renderTarget: texture, loadAction: .clear,
                                         storeAction: .store, clearColor: color.anyColor)])))
            clear.endEncoding()
            textures.append(texture)
        }
        let target = try XCTUnwrap(device.makeTexture(descriptor: .init(
            textureType: .type2D, pixelFormat: .rgba8Unorm,
            width: 16, height: 4, usage: [.renderTarget, .copySource])))
        let encoder = try XCTUnwrap(buffer.makeRenderCommandEncoder(descriptor: .init(
            colorAttachments: [.init(renderTarget: target, loadAction: .clear,
                                     storeAction: .store)])))
        encoder.setViewport(Viewport(x: 0, y: 0, width: 16, height: 4, nearZ: 0, farZ: 1))
        encoder.setScissorRect(ScissorRect(x: 0, y: 0, width: 16, height: 4))
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.clockwise)
        let state = try XCTUnwrap(pipeline.renderState(
            shader: dual ? .blendNormal : .image,
            colorFormat: .rgba8Unorm, depthFormat: .invalid,
            blendState: .opaque, sampleCount: 1))
        encoder.setRenderPipelineState(state)
        encoder.setDepthStencilState(try XCTUnwrap(pipeline.depthStencilState(.ignore)))

        let bindings: ShaderBindingSet
        if initializeOnce {
            bindings = try XCTUnwrap(dual ? pipeline.makeBindingSet2() : pipeline.makeBindingSet1())
        } else {
            bindings = try XCTUnwrap(device.makeShaderBindingSet(
                layout: dual ? pipeline.bindingLayout2 : pipeline.bindingLayout1))
        }
        for index in 0..<4 {
            let left = Float(index) * 0.5 - 1
            let right = left + 0.5
            let vertices: [_Vertex] = [
                .init(position: (left, -1), texcoord: (0, 1), color: (1, 1, 1, 1)),
                .init(position: (left, 1), texcoord: (0, 0), color: (1, 1, 1, 1)),
                .init(position: (right, -1), texcoord: (1, 1), color: (1, 1, 1, 1)),
                .init(position: (right, -1), texcoord: (1, 1), color: (1, 1, 1, 1)),
                .init(position: (left, 1), texcoord: (0, 0), color: (1, 1, 1, 1)),
                .init(position: (right, 1), texcoord: (1, 0), color: (1, 1, 1, 1))
            ]
            let vertexBuffer = try XCTUnwrap(device.makeBuffer(
                length: vertices.count * MemoryLayout<_Vertex>.stride,
                storageMode: .shared, cpuCacheMode: .writeCombined))
            let contents = try XCTUnwrap(vertexBuffer.contents())
            vertices.withUnsafeBytes {
                contents.copyMemory(from: $0.baseAddress!, byteCount: $0.count)
            }
            vertexBuffer.flush()
            bindings.setTexture(textures[index], binding: 0)
            if dual { bindings.setTexture(textures[(index + 2) % 4], binding: 1) }
            if !initializeOnce {
                bindings.setSamplerState(pipeline.defaultSampler, binding: 0)
                if dual { bindings.setSamplerState(pipeline.defaultSampler, binding: 1) }
            }
            encoder.setResource(bindings, index: 0)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.draw(vertexStart: 0, vertexCount: vertices.count,
                         instanceCount: 1, baseInstance: 0)
        }
        encoder.endEncoding()
        // Deferred commands must retain each draw's resources, not these later bindings.
        bindings.setTexture(textures[3], binding: 0)
        if dual { bindings.setTexture(textures[0], binding: 1) }
        try waitForCompletion(buffer)
        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: target))
        let contents = try XCTUnwrap(staging.contents())
        return Array(UnsafeRawBufferPointer(start: contents, count: 16 * 4 * 4))
    }

    func testSingleTextureSamplerInitializationPreservesRecordedDrawsOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext() else {
            throw XCTSkip("Graphics device unavailable")
        }
        let reference = try renderTextureChanges(
            deviceContext: deviceContext, dual: false, initializeOnce: false)
        let actual = try renderTextureChanges(
            deviceContext: deviceContext, dual: false, initializeOnce: true)
        XCTAssertEqual(actual, reference)
        let stripeColors = (0..<4).map { index in
            Array(actual[((index * 4 + 2) * 4)..<((index * 4 + 2) * 4 + 4)])
        }
        XCTAssertEqual(Set(stripeColors).count, 4)
        XCTAssertTrue(stripeColors.allSatisfy { $0[3] > 0 })
    }

    func testTwoTextureSamplerInitializationPreservesRecordedDrawsOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext() else {
            throw XCTSkip("Graphics device unavailable")
        }
        let reference = try renderTextureChanges(
            deviceContext: deviceContext, dual: true, initializeOnce: false)
        let actual = try renderTextureChanges(
            deviceContext: deviceContext, dual: true, initializeOnce: true)
        XCTAssertEqual(actual, reference)
        let stripeColors = (0..<4).map { index in
            Array(actual[((index * 4 + 2) * 4)..<((index * 4 + 2) * 4 + 4)])
        }
        XCTAssertEqual(Set(stripeColors).count, 4)
        XCTAssertTrue(stripeColors.allSatisfy { $0[3] == 255 })
    }
}
