//
//  File: VulkanTimelineSemaphore.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Vulkan

final class VulkanTimelineSemaphore: GPUSemaphore {
    let device: GraphicsDevice
    let semaphore: VkSemaphore

    init(device: VulkanGraphicsDevice, semaphore: VkSemaphore) {
        self.device = device
        self.semaphore = semaphore
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroySemaphore(device.device, semaphore, device.allocationCallbacks)
    }

    func signal(_ value: UInt64) {
        let device = self.device as! VulkanGraphicsDevice
        var signalInfo = VkSemaphoreSignalInfo()
        signalInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO
        signalInfo.semaphore = semaphore
        signalInfo.value = value
        vkSignalSemaphore(device.device, &signalInfo)
    }

    func wait(_ value: UInt64, timeout: UInt64 = UInt64.max) -> Bool {
        withUnsafePointer(to: Optional(semaphore)) { pSemaphore in
            withUnsafePointer(to: value) { pValue in

                let device = self.device as! VulkanGraphicsDevice

                var waitInfo = VkSemaphoreWaitInfo()
                waitInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO
                waitInfo.flags = 0;
                waitInfo.semaphoreCount = 1
                waitInfo.pSemaphores = pSemaphore
                waitInfo.pValues = pValue

                return vkWaitSemaphores(device.device, &waitInfo, timeout) == VK_SUCCESS
            }
        }
    }

    var value: UInt64 {
        let device = self.device as! VulkanGraphicsDevice
        var value: UInt64 = 0
        vkGetSemaphoreCounterValue(device.device, semaphore, &value)
        return value
    }
}

#endif //if ENABLE_VULKAN
