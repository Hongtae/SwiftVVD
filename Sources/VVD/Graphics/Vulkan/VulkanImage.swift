//
//  File: VulkanImage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
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
 
    public let memory: VulkanMemoryBlock?
    public let device: GraphicsDevice

    private struct LayoutAccessInfo {
        var layout: VkImageLayout
        var accessMask: VkAccessFlags2
        var stageMaskBegin: VkPipelineStageFlags2
        var stageMaskEnd: VkPipelineStageFlags2
        var queueFamilyIndex: UInt32
    }
    private let layoutLock = SpinLock()
    private var layoutInfo: LayoutAccessInfo

    public init(device: VulkanGraphicsDevice, memory: VulkanMemoryBlock, image: VkImage, imageCreateInfo: VkImageCreateInfo) {
        self.device = device
        self.memory = memory

        self.image = image
        self.imageType = imageCreateInfo.imageType
        self.format = imageCreateInfo.format
        self.extent = imageCreateInfo.extent
        self.mipLevels = imageCreateInfo.mipLevels
        self.arrayLayers = imageCreateInfo.arrayLayers
        self.usage = imageCreateInfo.usage

        self.layoutInfo = LayoutAccessInfo(layout: imageCreateInfo.initialLayout,
                                           accessMask: VK_ACCESS_2_NONE,
                                           stageMaskBegin: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                                           stageMaskEnd: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                                           queueFamilyIndex: VK_QUEUE_FAMILY_IGNORED)

        if layoutInfo.layout == VK_IMAGE_LAYOUT_UNDEFINED || layoutInfo.layout == VK_IMAGE_LAYOUT_PREINITIALIZED {
            layoutInfo.stageMaskEnd = VK_PIPELINE_STAGE_2_HOST_BIT
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
        self.memory = nil
        
        self.image = image

        self.imageType = VK_IMAGE_TYPE_1D
        self.format = VK_FORMAT_UNDEFINED
        self.extent = VkExtent3D(width: 0, height: 0, depth: 0)
        self.mipLevels = 1
        self.arrayLayers = 1
        self.usage = 0

        self.layoutInfo = LayoutAccessInfo(layout: VK_IMAGE_LAYOUT_UNDEFINED,
                                           accessMask: VK_ACCESS_2_NONE,
                                           stageMaskBegin: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                                           stageMaskEnd: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                                           queueFamilyIndex: VK_QUEUE_FAMILY_IGNORED)
    }

    deinit {
        if let image = self.image {
            let device = self.device as! VulkanGraphicsDevice
            vkDestroyImage(device.device, image, device.allocationCallbacks)
        }
        if var memory = self.memory {
            memory.chunk!.pool.dealloc(&memory)
        }
    }

    public func makeImageView(format: PixelFormat, parent: VulkanImageView? = nil)-> VulkanImageView? {
        if self.usage & (UInt32(VK_IMAGE_USAGE_SAMPLED_BIT.rawValue) |
                         UInt32(VK_IMAGE_USAGE_STORAGE_BIT.rawValue) |
                         UInt32(VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT.rawValue) |
                         UInt32(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue) |
                         UInt32(VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue)) != 0 {

            var imageViewCreateInfo = VkImageViewCreateInfo()
            imageViewCreateInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
            imageViewCreateInfo.image = self.image

            switch self.type {
            case .type1D:
                if self.arrayLayers > 1 {
                    imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_1D_ARRAY
                } else {
                    imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_1D
                }
            case .type2D:
                if self.arrayLayers > 1 {
                    imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_2D_ARRAY
                } else {
                    imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
                }
            case .type3D:
                imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_3D
            case .typeCube:
                if self.arrayLayers > 1 {
                    imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_CUBE_ARRAY
                } else {
                    imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_CUBE
                }
            default:
                assertionFailure("Unknown texture type!")
                return nil
            }

            imageViewCreateInfo.format = format.vkFormat()
            imageViewCreateInfo.components = VkComponentMapping(
                r: VK_COMPONENT_SWIZZLE_R,
                g: VK_COMPONENT_SWIZZLE_G,
                b: VK_COMPONENT_SWIZZLE_B,
                a: VK_COMPONENT_SWIZZLE_A)

            let pixelFormat = self.pixelFormat
            if pixelFormat.isColorFormat {
                imageViewCreateInfo.subresourceRange.aspectMask |= UInt32(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
            }
            if pixelFormat.isDepthFormat {
                imageViewCreateInfo.subresourceRange.aspectMask |= UInt32(VK_IMAGE_ASPECT_DEPTH_BIT.rawValue)
            }
            if pixelFormat.isStencilFormat {
                imageViewCreateInfo.subresourceRange.aspectMask |= UInt32(VK_IMAGE_ASPECT_STENCIL_BIT.rawValue)
            }

            imageViewCreateInfo.subresourceRange.baseMipLevel = 0
            imageViewCreateInfo.subresourceRange.baseArrayLayer = 0
            imageViewCreateInfo.subresourceRange.layerCount = self.arrayLayers
            imageViewCreateInfo.subresourceRange.levelCount = self.mipLevels

            var imageView: VkImageView? = nil
            let device = self.device as! VulkanGraphicsDevice
            let result = vkCreateImageView(device.device, &imageViewCreateInfo, device.allocationCallbacks, &imageView)
            if result != VK_SUCCESS {
               Log.err("vkCreateImageView failed: \(result)")
               return nil
            }
            return VulkanImageView(image: self, imageView: imageView!, parent: parent)
        }
        return nil
    }

    @discardableResult
    public func setLayout(_ layout: VkImageLayout,
                          accessMask: VkAccessFlags2,
                          stageBegin: VkPipelineStageFlags2, // this barrier's dst-stage
                          stageEnd: VkPipelineStageFlags2,   // next barrier's src-stage
                          queueFamilyIndex: UInt32 = VK_QUEUE_FAMILY_IGNORED,
                          commandBuffer: VkCommandBuffer) -> VkImageLayout {
        assert(layout != VK_IMAGE_LAYOUT_UNDEFINED)
        assert(layout != VK_IMAGE_LAYOUT_PREINITIALIZED)

        self.layoutLock.lock()
        defer { self.layoutLock.unlock() }

        var barrier = VkImageMemoryBarrier2()
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2
        barrier.srcAccessMask = layoutInfo.accessMask
        barrier.dstAccessMask = accessMask
        barrier.oldLayout = layoutInfo.layout
        barrier.newLayout = layout
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.image = image

        let pixelFormat = self.pixelFormat
        if pixelFormat.isColorFormat {
            barrier.subresourceRange.aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
        } else {
            if pixelFormat.isDepthFormat {
                barrier.subresourceRange.aspectMask |= UInt32(VK_IMAGE_ASPECT_DEPTH_BIT.rawValue)
            }
            if pixelFormat.isStencilFormat {
                barrier.subresourceRange.aspectMask |= UInt32(VK_IMAGE_ASPECT_STENCIL_BIT.rawValue)
            }
        }
        barrier.subresourceRange.baseMipLevel = 0
        barrier.subresourceRange.levelCount = VK_REMAINING_MIP_LEVELS
        barrier.subresourceRange.baseArrayLayer = 0
        barrier.subresourceRange.layerCount = VK_REMAINING_ARRAY_LAYERS

        barrier.srcStageMask = self.layoutInfo.stageMaskEnd

        if self.layoutInfo.queueFamilyIndex != queueFamilyIndex {
            if self.layoutInfo.queueFamilyIndex == VK_QUEUE_FAMILY_IGNORED || queueFamilyIndex == VK_QUEUE_FAMILY_IGNORED {
                barrier.srcStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
            } else {
                barrier.srcQueueFamilyIndex = self.layoutInfo.queueFamilyIndex
                barrier.dstQueueFamilyIndex = queueFamilyIndex
            }
        }
        if barrier.srcStageMask == VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT  {
            barrier.srcStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
        }
        barrier.dstStageMask = stageBegin

        withUnsafePointer(to: barrier) { pImageMemoryBarriers in
            var dependencyInfo = VkDependencyInfo()
            dependencyInfo.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO
            dependencyInfo.imageMemoryBarrierCount = 1
            dependencyInfo.pImageMemoryBarriers = pImageMemoryBarriers

            withUnsafePointer(to: dependencyInfo) { pDependencyInfo in
                vkCmdPipelineBarrier2(commandBuffer, pDependencyInfo)
            }
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
        synchronizedBy(locking: self.layoutLock) { self.layoutInfo.layout }
    }

    public var width: Int       { Int(self.extent.width) }
    public var height: Int      { Int(self.extent.height) }
    public var depth: Int       { Int(self.extent.depth) }
    public var mipmapCount: Int { Int(self.mipLevels) }
    public var arrayLength: Int { Int(self.arrayLayers) }

    public var type: TextureType {
        switch self.imageType {
            case VK_IMAGE_TYPE_1D:  return .type1D
            case VK_IMAGE_TYPE_2D:  return .type2D
            case VK_IMAGE_TYPE_3D:  return .type3D
            default:                return .unknown
        }
    }
    public var pixelFormat: PixelFormat { .from(vkFormat: self.format) }

    public static func commonAccessMask(forLayout layout: VkImageLayout) -> VkAccessFlags2 {
        var accessMask = VK_ACCESS_2_NONE 
        switch layout {
        case VK_IMAGE_LAYOUT_UNDEFINED:
            accessMask = VK_ACCESS_2_NONE
        case VK_IMAGE_LAYOUT_GENERAL:
            accessMask = VK_ACCESS_2_SHADER_READ_BIT | VK_ACCESS_2_SHADER_WRITE_BIT
        case VK_IMAGE_LAYOUT_PREINITIALIZED:
            accessMask = VK_ACCESS_2_HOST_WRITE_BIT
        case VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL:
            accessMask = VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT
        case VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL:
            accessMask = VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT
        case VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
             VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_STENCIL_ATTACHMENT_OPTIMAL,
             VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_STENCIL_READ_ONLY_OPTIMAL:
            accessMask = VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT
        case VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL:
            accessMask = VK_ACCESS_2_SHADER_READ_BIT
        case VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL:
            accessMask = VK_ACCESS_2_TRANSFER_READ_BIT
        case VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL:
            accessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT
        case VK_IMAGE_LAYOUT_PRESENT_SRC_KHR:
            accessMask = VK_ACCESS_2_NONE
        default:
            accessMask = VK_ACCESS_2_NONE
        }
        return accessMask
    }
}

#endif //if ENABLE_VULKAN
