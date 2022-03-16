#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanDeviceMemory {

    let memory: VkDeviceMemory
    let type: VkMemoryType
    let length: UInt

    var mapped: UnsafeMutableRawPointer?

    let device: GraphicsDevice

    public init(device: VulkanGraphicsDevice, mem: VkDeviceMemory, type: VkMemoryType, size: UInt) {
        self.device = device
        self.memory = mem
        self.type = type
        self.length = size

        if type.propertyFlags & UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue) != 0 {
            let offset: VkDeviceSize = 0
            let size: VkDeviceSize = VK_WHOLE_SIZE

            let result = vkMapMemory(device.device, memory, offset, size, 0, &mapped);
            if result != VK_SUCCESS {
                Log.err("vkMapMemory failed: \(result)")
            }
        }
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        if self.mapped != nil {
            vkUnmapMemory(device.device, self.memory)
            self.mapped = nil
        }

        vkFreeMemory(device.device, self.memory, device.allocationCallbacks)
    }

    public func invalidate(offset: UInt, size: UInt) -> Bool {
        false
    }

    public func flush(offset: UInt, size: UInt) -> Bool {
        false
    }
}

#endif //if ENABLE_VULKAN
