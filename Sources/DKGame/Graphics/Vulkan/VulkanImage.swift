#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanImage {

    public var image: VkImage?
    public var imageType: VkImageType
    public var format: VkFormat
    public var extent: VkExtent3D
    public var mipLevels: UInt32
    public var arrayLayers: UInt32
    public var usage: VkImageUsageFlags
 
    public let deviceMemory: VulkanDeviceMemory?
    public let device: GraphicsDevice

    private struct LayoutAccessInfo {
        var layout: VkImageLayout = VkImageLayout(0)
        var accessMask: VkAccessFlags = VkAccessFlags(0)
        var stageMaskBegin: VkPipelineStageFlags = VkPipelineStageFlags(0)
        var stageMaskEnd: VkPipelineStageFlags = 0
        var queueFamilyIndex: UInt32 = 0
    }
    private let layoutLock = SpinLock()
    private var layoutInfo: LayoutAccessInfo

    public init(memory: VulkanDeviceMemory, image: VkImage, imageCreateInfo: VkImageCreateInfo) {
        self.device = memory.device
        self.deviceMemory = memory

        self.image = image
        self.imageType = imageCreateInfo.imageType
        self.format = imageCreateInfo.format
        self.extent = imageCreateInfo.extent
        self.mipLevels = imageCreateInfo.mipLevels
        self.arrayLayers = imageCreateInfo.arrayLayers
        self.usage = imageCreateInfo.usage

        self.layoutInfo = LayoutAccessInfo()
        self.layoutInfo.layout = imageCreateInfo.initialLayout
        self.layoutInfo.accessMask = 0
        self.layoutInfo.stageMaskBegin = VkPipelineStageFlags(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT.rawValue)
        self.layoutInfo.stageMaskEnd = VkPipelineStageFlags(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT.rawValue)
        self.layoutInfo.queueFamilyIndex = VK_QUEUE_FAMILY_IGNORED

        if layoutInfo.layout == VK_IMAGE_LAYOUT_UNDEFINED || layoutInfo.layout == VK_IMAGE_LAYOUT_PREINITIALIZED {
            layoutInfo.stageMaskEnd = VkPipelineStageFlags(VK_PIPELINE_STAGE_HOST_BIT.rawValue)
        }

        assert(extent.width > 0)
        assert(extent.height > 0)
        assert(extent.depth > 0)
        assert(mipLevels > 0)
        assert(arrayLayers > 0)
        assert(format != VK_FORMAT_UNDEFINED)
    }

    public init(device: VulkanGraphicsDevice, image: VkImage) {
        self.device = device
        self.deviceMemory = nil
        
        self.image = image

        self.imageType = VK_IMAGE_TYPE_1D
        self.format = VK_FORMAT_UNDEFINED
        self.extent = VkExtent3D(width: 0, height: 0, depth: 0)
        self.mipLevels = 1
        self.arrayLayers = 1
        self.usage = 0

        self.layoutInfo = LayoutAccessInfo()
        self.layoutInfo.layout = VK_IMAGE_LAYOUT_UNDEFINED
        self.layoutInfo.accessMask = 0
        self.layoutInfo.stageMaskBegin = VkPipelineStageFlags(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT.rawValue)
        self.layoutInfo.stageMaskEnd = VkPipelineStageFlags(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT.rawValue)
        self.layoutInfo.queueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        if let image = self.image {
            vkDestroyImage(device.device, image, device.allocationCallbacks)
        }
    }

    @discardableResult
    public func setLayout(layout: VkImageLayout,
                          accessMask: VkAccessFlags,
                          stageBegin: UInt32,
                          stageEnd: UInt32,
                          queueFamilyIndex: UInt32 = VK_QUEUE_FAMILY_IGNORED,
                          commandBuffer: VkCommandBuffer? = nil) -> VkImageLayout {
        assert(layout != VK_IMAGE_LAYOUT_UNDEFINED)
        assert(layout != VK_IMAGE_LAYOUT_PREINITIALIZED)

        self.layoutLock.lock()
        defer { self.layoutLock.unlock() }

        if let commandBuffer = commandBuffer {
            var barrier = VkImageMemoryBarrier()
            barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
            barrier.srcAccessMask = layoutInfo.accessMask
            barrier.dstAccessMask = accessMask
            barrier.oldLayout = layoutInfo.layout
            barrier.newLayout = layout
            barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
            barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
            barrier.image = image

            let pixelFormat = self.pixelFormat
            if pixelFormat.isColorFormat() {
                barrier.subresourceRange.aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
            } else {
                if pixelFormat.isDepthFormat() {
                    barrier.subresourceRange.aspectMask |= UInt32(VK_IMAGE_ASPECT_DEPTH_BIT.rawValue)
                }
                if pixelFormat.isStencilFormat() {
                    barrier.subresourceRange.aspectMask |= UInt32(VK_IMAGE_ASPECT_STENCIL_BIT.rawValue)
                }
            }
            barrier.subresourceRange.baseMipLevel = 0
            barrier.subresourceRange.levelCount = VK_REMAINING_MIP_LEVELS
            barrier.subresourceRange.baseArrayLayer = 0
            barrier.subresourceRange.layerCount = VK_REMAINING_ARRAY_LAYERS

            var srcStageMask:VkPipelineStageFlags = self.layoutInfo.stageMaskEnd

            if self.layoutInfo.queueFamilyIndex != queueFamilyIndex {
                srcStageMask = VkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue)
                barrier.srcAccessMask = 0
            }
            if srcStageMask == VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT.rawValue {
                srcStageMask = VkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue)
                barrier.srcAccessMask = 0
            }

            vkCmdPipelineBarrier(commandBuffer,
                                 srcStageMask,
                                 stageBegin,
                                 0,         //dependencyFlags
                                 0,         //pMemoryBarriers
                                 nil,       //pMemoryBarriers
                                 0,         //bufferMemoryBarrierCount
                                 nil,       //pBufferMemoryBarriers
                                 1,         //imageMemoryBarrierCount
                                 &barrier)  //pImageMemoryBarriers
        }

        let oldLayout = self.layoutInfo.layout
        self.layoutInfo.layout = layout
        self.layoutInfo.stageMaskBegin = stageBegin
        self.layoutInfo.stageMaskEnd = stageEnd
        self.layoutInfo.accessMask = accessMask
        self.layoutInfo.queueFamilyIndex = queueFamilyIndex
        return oldLayout
    }

    public func layout() -> VkImageLayout {
        return VkImageLayout(VK_IMAGE_LAYOUT_UNDEFINED.rawValue)
    }

    public var width: UInt32    { self.extent.width }
    public var height: UInt32   { self.extent.height }
    public var depth: UInt32    { self.extent.depth }
    public var mipmapCount: UInt32 { self.mipLevels }
    public var arrayLength: UInt32 { self.arrayLayers }

    public var type: TextureType {
        switch (self.imageType) {
            case VK_IMAGE_TYPE_1D:  return .type1D
            case VK_IMAGE_TYPE_2D:  return .type2D
            case VK_IMAGE_TYPE_3D:  return .type3D
            default:
                return .unknown
        }
    }
    public var pixelFormat: PixelFormat { .from(format: self.format) }    
}

#endif //if ENABLE_VULKAN
