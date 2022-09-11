//
//  File: MetalCommandQueue.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalCommandQueue: CommandQueue {

    public let flags: CommandQueueFlags
    public let device: GraphicsDevice

    let queue: MTLCommandQueue

    init(device: MetalGraphicsDevice, queue: MTLCommandQueue) {
        self.device = device
        self.queue = queue
        self.flags = [.render, .compute, .copy]
    }

    public func makeCommandBuffer() -> CommandBuffer? {
        return MetalCommandBuffer(queue: self)
    }

    public func makeSwapChain(target: Window) async -> SwapChain? {
        return await MetalSwapChain(queue: self, window: target)
    }
}
#endif //if ENABLE_METAL
