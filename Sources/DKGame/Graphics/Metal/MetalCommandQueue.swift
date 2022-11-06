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

    @MainActor
    public func makeSwapChain(target: Window) -> SwapChain? {
        return MetalSwapChain(queue: self, window: target)
    }
}
#endif //if ENABLE_METAL
