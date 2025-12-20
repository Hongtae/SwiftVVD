//
//  File: VulkanCommandQueue.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanCommandQueue: CommandQueue, @unchecked Sendable {

    let device: GraphicsDevice
    let flags: CommandQueueFlags
    let family: VulkanQueueFamily

    private let queue: VkQueue
    private let lock = NSLock()

    init(device: VulkanGraphicsDevice, family: VulkanQueueFamily, queue: VkQueue) {

        let queueFlags = family.properties.queueFlags

        let copy = (queueFlags & UInt32(VK_QUEUE_TRANSFER_BIT.rawValue)) != 0
        let compute = (queueFlags & UInt32(VK_QUEUE_COMPUTE_BIT.rawValue)) != 0
        let render = (queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue)) != 0

        var flags: CommandQueueFlags = []
        if copy {
            flags.insert(.copy)
        }
        if render {
            flags.insert(.render)
        }
        if compute {
            flags.insert(.compute)
        }
        self.flags = flags
        self.device = device
        self.family = family
        self.queue = queue
    }

    deinit {
        vkQueueWaitIdle(self.queue)
        self.family.recycle(queue: self.queue)
    }

    func makeCommandBuffer() -> CommandBuffer? {
        let device = self.device as! VulkanGraphicsDevice
        var commandPoolCreateInfo = VkCommandPoolCreateInfo()
        commandPoolCreateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
        commandPoolCreateInfo.queueFamilyIndex = self.family.familyIndex
        commandPoolCreateInfo.flags = UInt32(VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT.rawValue)

        var commandPool: VkCommandPool? = nil
        let err = vkCreateCommandPool(device.device, &commandPoolCreateInfo, device.allocationCallbacks, &commandPool)
        if err == VK_SUCCESS {
            return VulkanCommandBuffer(queue: self, pool: commandPool!)
        }
        Log.err("vkCreateCommandPool failed: \(err)")
        return nil 
    }

    @MainActor
    func makeSwapChain(target: any Window) -> SwapChain? {
        guard self.family.supportPresentation else {
            Log.err("Vulkan WSI not supported with this queue family. Try to use other queue family!")
            return nil
        }
        if let swapchain = VulkanSwapChain(queue: self, window: target) {
            if swapchain.setup() {
                return swapchain
            } else {
                Log.err("VulkanSwapChain.setup() failed.")
            }
        }
        return nil 
    }

    func submit(_ submits: [VkSubmitInfo2], callback: (@Sendable ()->Void)?) -> Bool {
        let device = self.device as! VulkanGraphicsDevice
        var result: VkResult = VK_SUCCESS

        if let callback = callback {
            let fence: VkFence = device.fence()
            result = self.lock.withLock {
                vkQueueSubmit2(self.queue, UInt32(submits.count), submits, fence)
            }
            if result == VK_SUCCESS {
                device.addCompletionHandler(fence: fence, op: callback)
            }
        } else {
            result = self.lock.withLock {
                vkQueueSubmit2(self.queue, UInt32(submits.count), submits, nil)
            }
        }
        if result != VK_SUCCESS {
            Log.error("vkQueueSubmit2 failed: \(result)")
        }        
        return result == VK_SUCCESS 
    }

    @discardableResult
    func waitIdle() -> Bool { 
        self.lock.withLock { vkQueueWaitIdle(self.queue) } == VK_SUCCESS
    }

    func withVkQueue<T>(_ body: (VkQueue) throws -> T) rethrows -> T {
        try self.lock.withLock {
            try body(self.queue)
        }
    }
}
#endif //if ENABLE_VULKAN
