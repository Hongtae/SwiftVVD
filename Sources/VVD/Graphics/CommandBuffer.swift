//
//  File: CommandBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public typealias CommandBufferHandler = (CommandBuffer) -> Void

public protocol CommandBuffer {
    func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder?
    func makeComputeCommandEncoder() -> ComputeCommandEncoder?
    func makeCopyCommandEncoder() -> CopyCommandEncoder?

    // Encodes a command that blocks all subsequent passes until the event is signaled.
    // The command buffer state must be ready.
    func encodeWaitEvent(_ event: GPUEvent)
    func encodeSignalEvent(_ event: GPUEvent)

    // Encodes a command that blocks all subsequent passes until the semaphore equals or exceeds a value.
    // The command buffer state must be ready.
    func encodeWaitSemaphore(_ semaphore: GPUSemaphore, value: UInt64)
    func encodeSignalSemaphore(_ semaphore: GPUSemaphore, value: UInt64)

    func addCompletedHandler(_ handler: @escaping CommandBufferHandler)
    
    @discardableResult func commit() -> Bool

    var status: CommandBufferStatus { get }
    var commandQueue: CommandQueue { get }
    var device: GraphicsDevice { get }
}

public enum CommandBufferStatus {
    case ready
    case encoding
    case committed
}
