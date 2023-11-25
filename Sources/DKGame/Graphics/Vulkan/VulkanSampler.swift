//
//  File: VulkanSampler.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanSampler: SamplerState {
    public let device: GraphicsDevice
    public let sampler: VkSampler

    public init(device: VulkanGraphicsDevice, sampler: VkSampler) {
        self.device = device
        self.sampler = sampler
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroySampler(device.device, sampler, device.allocationCallbacks)
    }

    public var gpuResourceID: GPUResourceID { 
        let device = self.device as! VulkanGraphicsDevice
        let size = device.physicalDevice.descriptorBufferProperties.samplerDescriptorSize

        var descriptorGetInfo = VkDescriptorGetInfoEXT()
        descriptorGetInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT
        descriptorGetInfo.type = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
        let data = withUnsafePointer(to: Optional(sampler)) {
            descriptorGetInfo.data.pSampler = $0
            return Array<UInt8>(unsafeUninitializedCapacity: size) { ptr, count in
                vkGetDescriptorEXT(device.device, &descriptorGetInfo, size, ptr.baseAddress)
                count = size
            }
        }
        return GPUResourceID(size: size, data: data)
    }
}

#endif //if ENABLE_VULKAN
