//
//  File: MetalCommandQueue.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

final class MetalCommandQueue: CommandQueue, @unchecked Sendable {

    let flags: CommandQueueFlags
    let device: GraphicsDevice

    let queue: MTLCommandQueue

    init(device: MetalGraphicsDevice, queue: MTLCommandQueue) {
        self.device = device
        self.queue = queue
        self.flags = [.render, .compute, .copy]
    }

    func makeCommandBuffer() -> CommandBuffer? {
        return MetalCommandBuffer(queue: self)
    }

    @MainActor
    func makeSwapChain(target: Window) -> SwapChain? {
        return MetalSwapChain(queue: self, window: target)
    }
}
#endif //if ENABLE_METAL
