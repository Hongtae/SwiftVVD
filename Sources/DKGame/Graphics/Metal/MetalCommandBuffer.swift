//
//  File: MetalCommandBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalCommandBuffer: CommandBuffer {
    public let commandQueue: CommandQueue
    public var device: GraphicsDevice   { commandQueue.device }

    init(queue: MetalCommandQueue) {
        self.commandQueue = queue
    }

    public func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder? {
        return nil
    }

    public func makeComputeCommandEncoder() -> ComputeCommandEncoder? {
        return nil
    }

    public func makeCopyCommandEncoder() -> CopyCommandEncoder? {
        return nil
    }

    public func addCompletedHandler(_ handler: @escaping CommandBufferHandler) {

    }

    public func commit() -> Bool {
        return false
    }

}
#endif //if ENABLE_METAL
