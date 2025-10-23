//
//  File: VulkanImage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanImage {

    var image: VkImage?
    var imageType: VkImageType
    var format: VkFormat
    var extent: VkExtent3D
    var mipLevels: UInt32
    var arrayLayers: UInt32
    var samples: Int32
    var usage: VkImageUsageFlags
 
    let memory: VulkanMemoryBlock?
    let device: GraphicsDevice

    var isTransient: Bool {
        if let flags = memory?.propertyFlags, flags & UInt32(VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT.rawValue) != 0 {
            return true
        }
        return usage & UInt32(VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT.rawValue) != 0
    }

    private struct LayoutAccessInfo {
        var layout: VkImageLayout
        var accessMask: VkAccessFlags2
        var stageMaskBegin: VkPipelineStageFlags2
        var stageMaskEnd: VkPipelineStageFlags2
        var queueFamilyIndex: UInt32
        var lastUpdatedThread: Platform.ThreadID
    }
    private let layoutLock = NSLock()
    private var layoutInfo: LayoutAccessInfo

    init(device: VulkanGraphicsDevice, memory: VulkanMemoryBlock, image: VkImage, imageCreateInfo: VkImageCreateInfo) {
        self.device = device
        self.memory = memory

        self.image = image
        self.imageType = imageCreateInfo.imageType
        self.format = imageCreateInfo.format
        self.extent = imageCreateInfo.extent
        self.mipLevels = imageCreateInfo.mipLevels
        self.arrayLayers = imageCreateInfo.arrayLayers
        self.samples = Int32(imageCreateInfo.samples.rawValue)
        self.usage = imageCreateInfo.usage

        self.layoutInfo = LayoutAccessInfo(layout: imageCreateInfo.initialLayout,
                                           accessMask: VK_ACCESS_2_NONE,
                                           stageMaskBegin: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                                           stageMaskEnd: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                                           queueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
                                           lastUpdatedThread: 0)

        if layoutInfo.layout == VK_IMAGE_LAYOUT_UNDEFINED || layoutInfo.layout == VK_IMAGE_LAYOUT_PREINITIALIZED {
            layoutInfo.stageMaskEnd = VK_PIPELINE_STAGE_2_HOST_BIT
        }

        assert(extent.width > 0)
        assert(extent.height > 0)
        assert(extent.depth > 0)
        assert(mipLevels > 0)
        assert(arrayLayers > 0)
        assert(samples > 0)
        assert(format != VK_FORMAT_UNDEFINED)
    }

    init(device: VulkanGraphicsDevice, image: VkImage) {
        self.device = device
        self.memory = nil
        
        self.image = image

        self.imageType = VK_IMAGE_TYPE_1D
        self.format = VK_FORMAT_UNDEFINED
        self.extent = VkExtent3D(width: 0, height: 0, depth: 0)
        self.mipLevels = 1
        self.arrayLayers = 1
        self.samples = 1
        self.usage = 0

        self.layoutInfo = LayoutAccessInfo(layout: VK_IMAGE_LAYOUT_UNDEFINED,
                                           accessMask: VK_ACCESS_2_NONE,
                                           stageMaskBegin: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                                           stageMaskEnd: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                                           queueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
                                           lastUpdatedThread: 0)
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

    func makeImageView(format: PixelFormat, parent: VulkanImageView? = nil)-> VulkanImageView? {
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
    func setLayout(_ layout: VkImageLayout,
                   discardOldLayout: Bool,
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
        barrier.oldLayout = discardOldLayout ? VK_IMAGE_LAYOUT_UNDEFINED : layoutInfo.layout
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
            vkCmdPipelineBarrier2(commandBuffer, &dependencyInfo)
        }

        let oldLayoutInfo = self.layoutInfo
        self.layoutInfo.layout = layout
        self.layoutInfo.stageMaskBegin = stageBegin
        self.layoutInfo.stageMaskEnd = stageEnd
        self.layoutInfo.accessMask = accessMask
        self.layoutInfo.queueFamilyIndex = queueFamilyIndex
        self.layoutInfo.lastUpdatedThread = Platform.currentThreadID()

        if let recovery = VulkanCommandBuffer.recovery {
            recovery.addHandler { [weak self] in
                guard let self = self else { return }
                self.layoutLock.withLock {
                    if self.layoutInfo.lastUpdatedThread != Platform.currentThreadID() {
                        Log.err("VulkanImage layout recovery failed: accessed from different thread.")
                        return
                    }
                    self.layoutInfo = oldLayoutInfo
                }
            }
        }
        return oldLayoutInfo.layout
    }

    func layout() -> VkImageLayout {
        self.layoutLock.withLock { self.layoutInfo.layout }
    }

    var width: Int       { Int(self.extent.width) }
    var height: Int      { Int(self.extent.height) }
    var depth: Int       { Int(self.extent.depth) }
    var mipmapCount: Int { Int(self.mipLevels) }
    var arrayLength: Int { Int(self.arrayLayers) }
    var sampleCount: Int { Int(self.samples) }

    var type: TextureType {
        switch self.imageType {
        case VK_IMAGE_TYPE_1D:  .type1D
        case VK_IMAGE_TYPE_2D:  .type2D
        case VK_IMAGE_TYPE_3D:  .type3D
        default:                .unknown
        }
    }
    var pixelFormat: PixelFormat { .from(vkFormat: self.format) }

    static func commonAccessMask(forLayout layout: VkImageLayout) -> VkAccessFlags2 {
        switch layout {
        case VK_IMAGE_LAYOUT_UNDEFINED:
            return VK_ACCESS_2_NONE
        case VK_IMAGE_LAYOUT_GENERAL:
            return VK_ACCESS_2_SHADER_READ_BIT | VK_ACCESS_2_SHADER_WRITE_BIT
        case VK_IMAGE_LAYOUT_PREINITIALIZED:
            return VK_ACCESS_2_HOST_WRITE_BIT
        case VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL:
            return VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT
        case VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL:
            return VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT
        case VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
             VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_STENCIL_ATTACHMENT_OPTIMAL,
             VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_STENCIL_READ_ONLY_OPTIMAL:
            return VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT
        case VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL:
            return VK_ACCESS_2_SHADER_READ_BIT
        case VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL:
            return VK_ACCESS_2_TRANSFER_READ_BIT
        case VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL:
            return VK_ACCESS_2_TRANSFER_WRITE_BIT
        case VK_IMAGE_LAYOUT_PRESENT_SRC_KHR:
            return VK_ACCESS_2_NONE
        default:
            return VK_ACCESS_2_NONE
        }
    }
}
#endif //if ENABLE_VULKAN
