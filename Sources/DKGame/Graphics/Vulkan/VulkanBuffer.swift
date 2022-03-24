#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanBuffer {
    public var buffer: VkBuffer?
    public var usage: VkBufferUsageFlags
    public var sharingMode: VkSharingMode

    public let deviceMemory: VulkanDeviceMemory?
    public let device: GraphicsDevice

    public init(memory: VulkanDeviceMemory, buffer: VkBuffer, bufferCreateInfo: VkBufferCreateInfo) {
        self.device = memory.device
        self.deviceMemory = memory
        self.buffer = buffer
        self.usage = bufferCreateInfo.usage
        self.sharingMode = bufferCreateInfo.sharingMode

        assert(self.deviceMemory!.length > 0)
    }

    public init(device: VulkanGraphicsDevice, buffer: VkBuffer) {
        self.device = device
        self.deviceMemory = nil
        self.buffer = buffer
        self.usage = 0
        self.sharingMode = VK_SHARING_MODE_EXCLUSIVE
    }

    deinit {
        if let buffer = self.buffer {
            let device = self.device as! VulkanGraphicsDevice
            vkDestroyBuffer(device.device, buffer, device.allocationCallbacks)
        }
    }

    public var length: UInt { self.deviceMemory!.length }

    public func contents() -> UnsafeMutableRawPointer? {
        return self.deviceMemory!.mapped
    }

    public func flush(offset: UInt, size: UInt) {
        let length = self.deviceMemory!.length
        if offset < length {
            if size > 0 {
                self.deviceMemory!.flush(offset: offset, size: size)
            }
        }
        self.deviceMemory!.invalidate(offset: 0, size: UInt(VK_WHOLE_SIZE))
    }

    public func makeBufferView(pixelFormat: PixelFormat, offset: UInt, range: UInt) -> VulkanBufferView? {
        if self.usage & UInt32(VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT.rawValue) != 0 ||
           self.usage & UInt32(VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT.rawValue) != 0 {

            let format = pixelFormat.vkFormat()
            if format != VK_FORMAT_UNDEFINED {
                let device = self.device as! VulkanGraphicsDevice
                let alignment = device.properties.limits.minTexelBufferOffsetAlignment

                assert(offset & UInt(alignment) == 0)

                var bufferViewCreateInfo = VkBufferViewCreateInfo()
                bufferViewCreateInfo.sType = VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO
                bufferViewCreateInfo.buffer = buffer
                bufferViewCreateInfo.format = format
                bufferViewCreateInfo.offset = VkDeviceSize(offset)
                bufferViewCreateInfo.range = VkDeviceSize(range)

                var bufferView: VkBufferView? = nil
                let result = vkCreateBufferView(device.device, &bufferViewCreateInfo, device.allocationCallbacks, &bufferView)
                if result == VK_SUCCESS {
                    return VulkanBufferView(buffer: self, bufferView: bufferView!)
                } else {
                    Log.err("vkCreateBufferView failed: \(result)")
                }
            } else {
                Log.err("VulkanBuffer::makeBufferView failed: Invalid pixel format!")
            }
        } else {
            Log.err("VulkanBuffer::makeBufferView failed: Invalid buffer object (Not intended for texel buffer creation)")
        }
        return nil
    }
}

#endif //if ENABLE_VULKAN
