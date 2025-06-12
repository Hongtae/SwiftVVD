//
//  File: VulkanQueueFamily.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanQueueFamily {

    let familyIndex: UInt32
    let supportPresentation: Bool

    let properties: VkQueueFamilyProperties
    var freeQueues: [VkQueue] = []

    private let lock = NSLock()

    init(device: VkDevice, familyIndex: UInt32, count: UInt32, properties: VkQueueFamilyProperties, presentationSupport: Bool) {
        self.familyIndex = familyIndex
        self.supportPresentation = presentationSupport
        self.properties = properties

        self.freeQueues.reserveCapacity(Int(count))
        for queueIndex in 0 ..< count {
            var queue: VkQueue?
            vkGetDeviceQueue(device, familyIndex, queueIndex, &queue)
            if let queue = queue {
                self.freeQueues.append(queue)
            }
        }
    }

    func makeCommandQueue(device: VulkanGraphicsDevice) -> CommandQueue? {
        self.lock.withLock {
            if self.freeQueues.count > 0 {
                let queue = self.freeQueues.removeLast()
                let commandQueue = VulkanCommandQueue(device: device, family: self, queue: queue)
                Log.verbose("Vulkan Command-Queue with family-index: \(self.familyIndex) has been created.")
                return commandQueue as CommandQueue
            }
            return nil
        }
    }

    func recycle(queue: VkQueue) {
        self.lock.withLock {
            Log.verbose("Vulkan Command-Queue with family-index: \(self.familyIndex) was reclaimed for recycling.")
            self.freeQueues.append(queue)
        }
    }
}
#endif //if ENABLE_VULKAN
