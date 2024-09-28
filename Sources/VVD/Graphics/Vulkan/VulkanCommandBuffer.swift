//
//  File: VulkanCommandBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

class VulkanCommandEncoder {
    let initialNumberOfCommands = 128

    struct TimelineSemaphoreStageValue {
        var stages: VkPipelineStageFlags2 // wait before or signal after
        var value: UInt64   // 0 for non-timeline semaphore (binary semaphore)
    }

    var waitSemaphores: [VkSemaphore: TimelineSemaphoreStageValue] = [:]
    var signalSemaphores: [VkSemaphore: TimelineSemaphoreStageValue] = [:]

    func encode(commandBuffer: VkCommandBuffer) -> Bool { false }

    func addWaitSemaphore(_ semaphore: VkSemaphore, value: UInt64, flags: VkPipelineStageFlags2) {
        if var p = self.waitSemaphores[semaphore] {
            p.value = max(p.value, value)
            p.stages |= flags
            self.waitSemaphores[semaphore] = p
        } else {
            self.waitSemaphores[semaphore] = TimelineSemaphoreStageValue(stages: flags, value: value)
        }
    }

    func addSignalSemaphore(_ semaphore: VkSemaphore, value: UInt64, flags: VkPipelineStageFlags2) {
        if var p = self.signalSemaphores[semaphore] {
            p.value = max(p.value, value)
            p.stages |= flags
            self.signalSemaphores[semaphore] = p
        } else {
            self.signalSemaphores[semaphore] = TimelineSemaphoreStageValue(stages: flags, value: value)
        }
    }
}

final class VulkanCommandBuffer: CommandBuffer, @unchecked Sendable {

    let commandQueue: CommandQueue
    let device: GraphicsDevice   
    let lock = NSLock()

    private let commandPool: VkCommandPool

    private var encoders: [VulkanCommandEncoder] = []
    private var submitInfos: [VkSubmitInfo2] = []
    private var commandBufferSubmitInfos: [VkCommandBufferSubmitInfo] = []

    private var bufferHolder: TemporaryBufferHolder?

    private var completedHandlers: [CommandBufferHandler] = []

    init(queue: VulkanCommandQueue, pool: VkCommandPool) {
        self.commandQueue = queue
        self.device = queue.device
        self.commandPool = pool
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        if self.commandBufferSubmitInfos.isEmpty == false {
            var tmp = self.commandBufferSubmitInfos.map { $0.commandBuffer }
            vkFreeCommandBuffers(device.device, commandPool, UInt32(tmp.count), &tmp)
        }
        vkDestroyCommandPool(device.device, commandPool, device.allocationCallbacks)
    }

    func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder? {
        let queue = self.commandQueue as! VulkanCommandQueue
        if queue.family.properties.queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue) != 0 {
            return VulkanRenderCommandEncoder(buffer: self, descriptor: descriptor)
        }
        return nil
    }

    func makeComputeCommandEncoder() -> ComputeCommandEncoder? {
         let queue = self.commandQueue as! VulkanCommandQueue
        if queue.family.properties.queueFlags & UInt32(VK_QUEUE_COMPUTE_BIT.rawValue) != 0 {
            return VulkanComputeCommandEncoder(buffer: self)
        }
        return nil
    }

    func makeCopyCommandEncoder() -> CopyCommandEncoder? {
        return VulkanCopyCommandEncoder(buffer: self)
    }

    func addCompletedHandler(_ handler: @escaping CommandBufferHandler) {
        completedHandlers.append(handler)
    }

    @discardableResult
    func commit() -> Bool {
        let device = self.device as! VulkanGraphicsDevice

        self.lock.lock()
        defer { self.lock.unlock() }

        let cleanup = {
            if self.commandBufferSubmitInfos.isEmpty == false {
                var tmp = self.commandBufferSubmitInfos.map { $0.commandBuffer }
                vkFreeCommandBuffers(device.device,
                                     self.commandPool,
                                     UInt32(tmp.count),
                                     &tmp)
            }

            self.submitInfos = []
            self.commandBufferSubmitInfos = []
            self.bufferHolder = nil
        }

        if self.submitInfos.count != self.encoders.count {
            cleanup()

            let bufferHolder = TemporaryBufferHolder(label: "VulkanCommandBuffer")
            self.bufferHolder = bufferHolder

            var waitSemaphores: [VkSemaphoreSubmitInfo] = []
            var signalSemaphores: [VkSemaphoreSubmitInfo] = []

            // reserve storage for semaphores.
            let numWaitSemaphores = self.encoders.reduce(0) { max($0, $1.waitSemaphores.count) }
            let numSignalSemaphores = self.encoders.reduce(0) { max($0, $1.signalSemaphores.count) }
            waitSemaphores.reserveCapacity(numWaitSemaphores)
            signalSemaphores.reserveCapacity(numSignalSemaphores)

            self.commandBufferSubmitInfos.reserveCapacity(self.encoders.count)
            self.submitInfos.reserveCapacity(self.encoders.count)

            for encoder in self.encoders {
                waitSemaphores.removeAll(keepingCapacity: true)
                signalSemaphores.removeAll(keepingCapacity: true)

                let commandBuffersOffset = self.commandBufferSubmitInfos.count

                var bufferInfo = VkCommandBufferAllocateInfo()
                bufferInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
                bufferInfo.commandPool = self.commandPool
                bufferInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
                bufferInfo.commandBufferCount = 1

                var commandBuffer: VkCommandBuffer? = nil
                let err = vkAllocateCommandBuffers(device.device, &bufferInfo, &commandBuffer)
                if err != VK_SUCCESS {
                    Log.err("vkAllocateCommandBuffers failed: \(err)")
                    cleanup()
                    return false
                }
                var cbufferSubmitInfo = VkCommandBufferSubmitInfo()
                cbufferSubmitInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO
                cbufferSubmitInfo.commandBuffer = commandBuffer
                cbufferSubmitInfo.deviceMask = 0
                self.commandBufferSubmitInfos.append(cbufferSubmitInfo)

                let transformSemaphoreSubmitInfo = {
                   (semaphore: VkSemaphore, stageValue: VulkanCommandEncoder.TimelineSemaphoreStageValue) in
                    let stages = stageValue.stages
                    let value = stageValue.value // timeline-value

                    assert((stages & VK_PIPELINE_STAGE_2_HOST_BIT) == 0)

                    var semaphoreSubmitInfo = VkSemaphoreSubmitInfo()
                    semaphoreSubmitInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO
                    semaphoreSubmitInfo.semaphore = semaphore
                    semaphoreSubmitInfo.value = value
                    semaphoreSubmitInfo.stageMask = stages
                    semaphoreSubmitInfo.deviceIndex = 0
                    return semaphoreSubmitInfo
                }
                waitSemaphores.append(contentsOf: encoder.waitSemaphores.map(transformSemaphoreSubmitInfo))
                signalSemaphores.append(contentsOf: encoder.signalSemaphores.map(transformSemaphoreSubmitInfo))

                // encode all commands.
                var commandBufferBeginInfo = VkCommandBufferBeginInfo()
                commandBufferBeginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO

                vkBeginCommandBuffer(commandBuffer, &commandBufferBeginInfo)
                let result = encoder.encode(commandBuffer: commandBuffer!)
                vkEndCommandBuffer(commandBuffer)

                if result == false {
                    cleanup()
                    return false
                }

                var submitInfo = VkSubmitInfo2()
                submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO_2

                if self.commandBufferSubmitInfos.count > commandBuffersOffset {
                    let count = self.commandBufferSubmitInfos.count - commandBuffersOffset
                    let commandBufferInfos = self.commandBufferSubmitInfos[commandBuffersOffset ..< commandBuffersOffset + count]
                    submitInfo.commandBufferInfoCount = UInt32(count)
                    submitInfo.pCommandBufferInfos = unsafePointerCopy(collection: commandBufferInfos, holder: bufferHolder)                  
                }

                if waitSemaphores.isEmpty == false {
                    submitInfo.waitSemaphoreInfoCount = UInt32(waitSemaphores.count)
                    submitInfo.pWaitSemaphoreInfos = unsafePointerCopy(collection: waitSemaphores, holder: bufferHolder)
                }
                if signalSemaphores.isEmpty == false {
                    submitInfo.signalSemaphoreInfoCount = UInt32(signalSemaphores.count)
                    submitInfo.pSignalSemaphoreInfos = unsafePointerCopy(collection: signalSemaphores, holder: bufferHolder)
                }
                self.submitInfos.append(submitInfo)
            }
        }

        if self.submitInfos.isEmpty == false {
            assert(self.submitInfos.count == self.encoders.count)

            let commandQueue = self.commandQueue as! VulkanCommandQueue
            return commandQueue.submit(self.submitInfos) {
                self.completedHandlers.forEach { $0(self) }
            }
        }

        return false
    }

    func endEncoder(_ encoder: VulkanCommandEncoder) {
        self.encoders.append(encoder)
    }

    var queueFamily: VulkanQueueFamily {
        return (self.commandQueue as! VulkanCommandQueue).family
    }
}

#endif //if ENABLE_VULKAN
