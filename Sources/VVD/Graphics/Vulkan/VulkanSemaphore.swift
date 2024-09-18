//
//  File: VulkanSemaphore.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanSemaphore: GPUEvent {
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

    public var nextWaitValue: UInt64 { 0 }
    public var nextSignalValue: UInt64 { 0 }
}

public class VulkanSemaphoreAutoIncrementalTimeline: VulkanSemaphore {

    public let waitValue = AtomicNumber64(0)
    public let signalValue = AtomicNumber64(0)

    public override var nextWaitValue: UInt64 {
        UInt64(bitPattern: waitValue.increment())
    }
    public override var nextSignalValue: UInt64 {
        UInt64(bitPattern: signalValue.increment())
    }
}

#endif //if ENABLE_VULKAN
