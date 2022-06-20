//
//  File: VulkanTimelineSemaphore.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Vulkan

public class VulkanTimelineSemaphore: Semaphore {
    public let device: GraphicsDevice
    public let semaphore: VkSemaphore

    public init(device: VulkanGraphicsDevice, semaphore: VkSemaphore) {
        self.device = device
        self.semaphore = semaphore
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroySemaphore(device.device, semaphore, device.allocationCallbacks)
    }
}

#endif //if ENABLE_VULKAN
