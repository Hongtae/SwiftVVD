#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanBufferView: Buffer {
    public let bufferView: VkBufferView
    public let device: GraphicsDevice
    public let buffer: VulkanBuffer?

    public init(buffer: VulkanBuffer, bufferView: VkBufferView) {
        self.device = buffer.device
        self.bufferView = bufferView
        self.buffer = buffer
    }

    public init(device: VulkanGraphicsDevice, bufferView: VkBufferView) {
        self.device = device
        self.bufferView = bufferView
        self.buffer = nil
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroyBufferView(device.device, bufferView, device.allocationCallbacks)
    }

    public func contents() -> UnsafeMutableRawPointer? {
        return self.buffer!.contents()
    }

    public func flush() {
        self.buffer!.flush(offset: 0, size: UInt(VK_WHOLE_SIZE))
    }

    public var length: UInt { self.buffer!.length }
}

#endif //if ENABLE_VULKAN