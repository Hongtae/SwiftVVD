#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanDeviceMemory {

    public let memory: VkDeviceMemory
    public let type: VkMemoryType
    public let length: UInt

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

    @discardableResult
    public func invalidate(offset: UInt, size: UInt) -> Bool {
        if self.mapped != nil &&
           (type.propertyFlags & UInt32(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue)) == 0 {

            if offset < length {
                let device = self.device as! VulkanGraphicsDevice

                var range = VkMappedMemoryRange()
                range.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE
                range.memory = memory
                range.offset = VkDeviceSize(offset)

                if size == VK_WHOLE_SIZE {
                    range.size = VkDeviceSize(size)
                } else {
                    range.size = VkDeviceSize(min(size, length - offset))
                }
                let result = vkInvalidateMappedMemoryRanges(device.device, 1, &range)
                if result == VK_SUCCESS {
                    return true
                } else {
                    Log.err("vkInvalidateMappedMemoryRanges failed: \(result)")
                }
            } else {
                Log.err("VulkanDeviceMemory.invalidate() failed: Out of range")
            }
        }
        return false
    }

    @discardableResult
    public func flush(offset: UInt, size: UInt) -> Bool {
        if self.mapped != nil &&
           (type.propertyFlags & UInt32(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue)) == 0 {
           
            if offset < length {
                let device = self.device as! VulkanGraphicsDevice

                var range = VkMappedMemoryRange()
                range.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE
                range.memory = memory
                range.offset = VkDeviceSize(offset)

                if size == VK_WHOLE_SIZE {
                    range.size = VkDeviceSize(size)
                } else {
                    range.size = VkDeviceSize(min(size, length - offset))
                }
                let result = vkFlushMappedMemoryRanges(device.device, 1, &range)
                if result == VK_SUCCESS {
                    return true
                } else {
                    Log.err("vkFlushMappedMemoryRanges failed: \(result)")
                }
            } else {
                Log.err("VulkanDeviceMemory.flush() failed: Out of range")
            }
        }
        return false
    }
}

#endif //if ENABLE_VULKAN