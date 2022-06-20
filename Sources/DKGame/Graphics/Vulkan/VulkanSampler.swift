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
}

#endif //if ENABLE_VULKAN
