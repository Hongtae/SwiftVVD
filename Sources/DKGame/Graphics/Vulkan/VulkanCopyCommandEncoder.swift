#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanCopyCommandEncoder: VulkanCommandEncoder, CopyCommandEncoder {
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
    
    public func copy(from: Buffer, sourceOffset: UInt64, to: Buffer, destinationOffset: UInt64, size: UInt64) {}
    public func copy(from: Buffer, sourceOffset: BufferImageOrigin, to: Texture, destinationOffset: TextureOrigin, size: TextureSize) {}
    public func copy(from: Texture, sourceOffset: TextureOrigin, to: Buffer, destinationOffset: BufferImageOrigin, size: TextureSize) {}
    public func copy(from: Texture, sourceOffset: TextureOrigin, to: Texture, destinationOffset: TextureOrigin, size: TextureSize) {}

    public func fill(buffer: Buffer, offset: UInt64, length: UInt64, value: UInt8) {}
}

#endif //if ENABLE_VULKAN
