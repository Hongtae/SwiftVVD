//
//  File: VulkanImageView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanImageView: Texture {

    public let imageView: VkImageView
    
    public var waitSemaphore: VkSemaphore?
    public var signalSemaphore: VkSemaphore?

    public var image: VulkanImage?
    public let device: GraphicsDevice

    public init(image: VulkanImage, imageView: VkImageView, imageViewCreateInfo: VkImageViewCreateInfo) {
        self.image = image
        self.imageView = imageView
        self.device = image.device
    }

    public init(device: VulkanGraphicsDevice, imageView: VkImageView) {
        self.imageView = imageView
        self.device = device
    }

    deinit {
        let device = device as! VulkanGraphicsDevice

        vkDestroyImageView(device.device, imageView, device.allocationCallbacks)
        if let signalSemaphore = self.signalSemaphore {
            vkDestroySemaphore(device.device, signalSemaphore, device.allocationCallbacks)
        }
        if let waitSemaphore = self.waitSemaphore {
            vkDestroySemaphore(device.device, waitSemaphore, device.allocationCallbacks)
        }
    }

    public var width: Int       { self.image!.width }
    public var height: Int      { self.image!.height }
    public var depth: Int       { self.image!.depth }
    public var mipmapCount: Int { self.image!.mipmapCount }
    public var arrayLength: Int { self.image!.arrayLength }

    public var type: TextureType    { self.image!.type }
    public var pixelFormat: PixelFormat { self.image!.pixelFormat }

    public var gpuResourceID: GPUResourceID {
        let device = self.device as! VulkanGraphicsDevice
        let size = device.physicalDevice.descriptorBufferProperties.sampledImageDescriptorSize

        var descriptorImageInfo = VkDescriptorImageInfo()
        descriptorImageInfo.imageView = imageView
        descriptorImageInfo.imageLayout = self.image!.layout()

        var descriptorGetInfo = VkDescriptorGetInfoEXT()
        descriptorGetInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT
        descriptorGetInfo.type = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
        let data = withUnsafePointer(to: descriptorImageInfo) {
            descriptorGetInfo.data.pSampledImage = $0
            return Array<UInt8>(unsafeUninitializedCapacity: size) { ptr, count in
                vkGetDescriptorEXT(device.device, &descriptorGetInfo, size, ptr.baseAddress)
                count = size
            }
        }
        return GPUResourceID(size: size, data: data)
    }

    public var gpuStorageResourceID: GPUResourceID {
        let device = self.device as! VulkanGraphicsDevice
        let size = device.physicalDevice.descriptorBufferProperties.storageImageDescriptorSize

        var descriptorImageInfo = VkDescriptorImageInfo()
        descriptorImageInfo.imageView = imageView
        descriptorImageInfo.imageLayout = self.image!.layout()

        var descriptorGetInfo = VkDescriptorGetInfoEXT()
        descriptorGetInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT
        descriptorGetInfo.type = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE
        let data = withUnsafePointer(to: descriptorImageInfo) {
            descriptorGetInfo.data.pStorageImage = $0
            return Array<UInt8>(unsafeUninitializedCapacity: size) { ptr, count in
                vkGetDescriptorEXT(device.device, &descriptorGetInfo, size, ptr.baseAddress)
                count = size
            }
        }
        return GPUResourceID(size: size, data: data)
    }

    public func gpuResourceID(withSampler sampler: SamplerState) -> GPUResourceID {
        let device = self.device as! VulkanGraphicsDevice
        let sampler = sampler as! VulkanSampler
        let size = device.physicalDevice.descriptorBufferProperties.combinedImageSamplerDescriptorSize

        var descriptorImageInfo = VkDescriptorImageInfo()
        descriptorImageInfo.imageView = imageView
        descriptorImageInfo.imageLayout = self.image!.layout()
        descriptorImageInfo.sampler = sampler.sampler

        var descriptorGetInfo = VkDescriptorGetInfoEXT()
        descriptorGetInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT
        descriptorGetInfo.type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
        let data = withUnsafePointer(to: descriptorImageInfo) {
            descriptorGetInfo.data.pCombinedImageSampler = $0
            return Array<UInt8>(unsafeUninitializedCapacity: size) { ptr, count in
                vkGetDescriptorEXT(device.device, &descriptorGetInfo, size, ptr.baseAddress)
                count = size
            }
        }
        return GPUResourceID(size: size, data: data)
    }
}

#endif //if ENABLE_VULKAN
