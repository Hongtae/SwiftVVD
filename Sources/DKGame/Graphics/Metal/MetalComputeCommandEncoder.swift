//
//  File: MetalComputeCommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalComputeCommandEncoder: ComputeCommandEncoder {
    public let commandBuffer: CommandBuffer

    init(buffer: MetalCommandBuffer) {
        self.commandBuffer = buffer
    }

    public func setResource(_: ShaderBindingSet, atIndex: Int) {

    }

    public func setComputePipelineState(_: ComputePipelineState) {

    }

    public func pushConstant<D>(stages: ShaderStageFlags, offset: Int, data: D) where D : DataProtocol {

    }

    public func dispatch(numGroupX: Int, numGroupY: Int, numGroupZ: Int) {

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
