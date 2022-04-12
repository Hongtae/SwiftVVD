#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanComputeCommandEncoder: VulkanCommandEncoder, ComputeCommandEncoder {
    public let commandBuffer: CommandBuffer

    public init(buffer: VulkanCommandBuffer) {   
        self.commandBuffer = buffer
    }

    public func endEncoding() {}
    public var isCompleted: Bool { false }

    public func waitEvent(_ event: Event) {}
    public func signalEvent(_ event: Event) {}

    public func waitSemaphoreValue(_ semaphore: Semaphore, value: UInt64) {}
    public func signalSemaphoreValue(_ semaphore: Semaphore, value: UInt64) {}

    public func setResource(set: UInt32, _: ShaderBindingSet) {}
    public func setComputePipelineState(_: ComputePipelineState) {}

    public func pushConstant(stages: [ShaderStage], offset: UInt32, data: UnsafeRawPointer) {}

    public func dispatch(numGroupX: UInt32, numGroupY: UInt32, numGroupZ: UInt32) {}
}

#endif //if ENABLE_VULKAN
