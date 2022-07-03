//
//  File: VulkanImage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

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
        if let image = self.image {
            let device = self.device as! VulkanGraphicsDevice
            vkDestroyImage(device.device, image, device.allocationCallbacks)
        }
    }

    @discardableResult
    public func setLayout(_ layout: VkImageLayout,
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

    public var width: Int       { Int(self.extent.width) }
    public var height: Int      { Int(self.extent.height) }
    public var depth: Int       { Int(self.extent.depth) }
    public var mipmapCount: Int { Int(self.mipLevels) }
    public var arrayLength: Int { Int(self.arrayLayers) }

    public var type: TextureType {
        switch (self.imageType) {
            case VK_IMAGE_TYPE_1D:  return .type1D
            case VK_IMAGE_TYPE_2D:  return .type2D
            case VK_IMAGE_TYPE_3D:  return .type3D
            default:
                return .unknown
        }
    }
    public var pixelFormat: PixelFormat { .from(vkFormat: self.format) }

    public static func commonAccessMask(forLayout layout: VkImageLayout) -> VkAccessFlags {
        var accessMask: VkAccessFlags = 0
        switch (layout) {
        case VK_IMAGE_LAYOUT_UNDEFINED:
            accessMask = 0
        case VK_IMAGE_LAYOUT_GENERAL:
            accessMask = UInt32(VK_ACCESS_SHADER_READ_BIT.rawValue) | UInt32(VK_ACCESS_SHADER_WRITE_BIT.rawValue)
        case VK_IMAGE_LAYOUT_PREINITIALIZED:
            accessMask = UInt32(VK_ACCESS_HOST_WRITE_BIT.rawValue)
        case VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL:
            accessMask = UInt32(VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue)
        case VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL:
            accessMask = UInt32(VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT.rawValue)
        case VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
             VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_STENCIL_ATTACHMENT_OPTIMAL,
             VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_STENCIL_READ_ONLY_OPTIMAL:
            accessMask = UInt32(VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT.rawValue)
        case VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL:
            accessMask = UInt32(VK_ACCESS_SHADER_READ_BIT.rawValue)
        case VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL:
            accessMask = UInt32(VK_ACCESS_TRANSFER_READ_BIT.rawValue)
        case VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL:
            accessMask = UInt32(VK_ACCESS_TRANSFER_WRITE_BIT.rawValue)
        case VK_IMAGE_LAYOUT_PRESENT_SRC_KHR:
            accessMask = 0
        default:
            accessMask = 0
        }
        return accessMask
    }
}

#endif //if ENABLE_VULKAN
