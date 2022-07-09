//
//  File: MetalRenderCommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalRenderCommandEncoder: RenderCommandEncoder {
    public let commandBuffer: CommandBuffer

    init(buffer: MetalCommandBuffer, descriptor: MTLRenderPassDescriptor) {
        self.commandBuffer = buffer
    }

    public func setResource(_: ShaderBindingSet, atIndex: Int) {

    }

    public func setViewport(_: Viewport) {

    }

    public func setRenderPipelineState(_: RenderPipelineState) {

    }

    public func setVertexBuffer(_: Buffer, offset: Int, index: Int) {

    }

    public func setVertexBuffers(_: [Buffer], offsets: [Int], index: Int) {

    }

    public func setIndexBuffer(_: Buffer, offset: Int, type: IndexType) {

    }

    public func pushConstant<D>(stages: ShaderStageFlags, offset: Int, data: D) where D : DataProtocol {

    }

    public func draw(numVertices: Int, numInstances: Int, baseVertex: Int, baseInstance: Int) {

    }

    public func drawIndexed(numIndices: Int, numInstances: Int, indexOffset: Int, vertexOffset: Int, baseInstance: Int) {

    }

    public func endEncoding() {

    }

    public var isCompleted: Bool {
        return false
    }
    
    public func waitEvent(_ event: Event) {

    }

    public func signalEvent(_ event: Event) {

    }

    public func waitSemaphoreValue(_ semaphore: Semaphore, value: UInt64) {

    }

    public func signalSemaphoreValue(_ semaphore: Semaphore, value: UInt64) {

    }
}
#endif //if ENABLE_METAL
