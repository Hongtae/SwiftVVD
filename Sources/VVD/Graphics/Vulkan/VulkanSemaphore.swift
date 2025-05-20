//
//  File: VulkanSemaphore.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Synchronization
import Vulkan

class VulkanSemaphore: GPUEvent {
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

    var nextWaitValue: UInt64 { 0 }
    var nextSignalValue: UInt64 { 0 }
}

final class VulkanSemaphoreAutoIncrementalTimeline: VulkanSemaphore {
    let waitValue = Atomic<UInt64>(0)
    let signalValue = Atomic<UInt64>(0)

    override var nextWaitValue: UInt64 {
        waitValue.add(1, ordering: .sequentiallyConsistent).newValue
    }
    
    override var nextSignalValue: UInt64 {
        signalValue.add(1, ordering: .sequentiallyConsistent).newValue
    }
}
#endif //if ENABLE_VULKAN
