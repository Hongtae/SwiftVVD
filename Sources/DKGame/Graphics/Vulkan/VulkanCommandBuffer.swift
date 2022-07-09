//
//  File: VulkanCommandBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanCommandEncoder {
    public let initialNumberOfCommands = 128

    struct WaitTimelineSemaphoreStageValue {
        var stages: VkPipelineStageFlags
        var value: UInt64   // 0 for non-timeline semaphore (binary semaphore)
    }

    var waitSemaphores: [VkSemaphore: WaitTimelineSemaphoreStageValue] = [:]
    var signalSemaphores: [VkSemaphore: UInt64] = [:]

    public func encode(commandBuffer: VkCommandBuffer) -> Bool { false }

    public func addWaitSemaphore(_ semaphore: VkSemaphore, value: UInt64, flags: VkPipelineStageFlags) {
        if var p = self.waitSemaphores[semaphore] {
            if value > p.value {
                p.value = value
            }
            p.stages |= flags
            self.waitSemaphores[semaphore] = p
        } else {
            self.waitSemaphores[semaphore] = WaitTimelineSemaphoreStageValue(stages: flags, value: value)
        }
    }

    public func addSignalSemaphore(_ semaphore: VkSemaphore, value: UInt64) {
        if let p = self.signalSemaphores[semaphore] {
            if value > p {
                self.signalSemaphores[semaphore] = value
            }
        } else {
            self.signalSemaphores[semaphore] = value
        }
    }
}

public class VulkanCommandBuffer: CommandBuffer {

    public let commandQueue: CommandQueue
    public let device: GraphicsDevice   
    public let lock = NSLock()

    private let commandPool: VkCommandPool

    private var encoders: [VulkanCommandEncoder] = []
    private var submitInfos: [VkSubmitInfo] = []
    private var submitCommandBuffers: [VkCommandBuffer] = []

    private var bufferHolder: TemporaryBufferHolder?

    private var completedHandlers: [CommandBufferHandler] = []

    public init(pool: VkCommandPool, queue: VulkanCommandQueue) {
        self.commandQueue = queue
        self.device = queue.device
        self.commandPool = pool
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        if self.submitCommandBuffers.isEmpty == false {
            var tmp = self.submitCommandBuffers.map { Optional($0) }
            vkFreeCommandBuffers(device.device, commandPool, UInt32(tmp.count), &tmp)
        }
        vkDestroyCommandPool(device.device, commandPool, device.allocationCallbacks)
    }

    public func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder? {
        let queue = self.commandQueue as! VulkanCommandQueue
        if queue.family.properties.queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue) != 0 {
            return VulkanRenderCommandEncoder(buffer: self, descriptor: descriptor)
        }
        return nil
    }

    public func makeComputeCommandEncoder() -> ComputeCommandEncoder? {
         let queue = self.commandQueue as! VulkanCommandQueue
        if queue.family.properties.queueFlags & UInt32(VK_QUEUE_COMPUTE_BIT.rawValue) != 0 {
            return VulkanComputeCommandEncoder(buffer: self)
        }
        return nil
    }

    public func makeCopyCommandEncoder() -> CopyCommandEncoder? {
        return VulkanCopyCommandEncoder(buffer: self)
    }

    public func addCompletedHandler(_ handler: @escaping CommandBufferHandler) {
        completedHandlers.append(handler)
    }

    @discardableResult
    public func commit() -> Bool {
        let device = self.device as! VulkanGraphicsDevice

        self.lock.lock()
        defer { self.lock.unlock() }

        let cleanup = {
            if self.submitCommandBuffers.isEmpty == false {
                var tmp = self.submitCommandBuffers.map { Optional($0) }
                vkFreeCommandBuffers(device.device,
                                     self.commandPool,
                                     UInt32(tmp.count),
                                     &tmp)
            }

            self.submitInfos = []
            self.submitCommandBuffers = []
            self.bufferHolder = nil
        }

        if self.submitInfos.count != self.encoders.count {
            cleanup()

            self.bufferHolder = TemporaryBufferHolder(label: "VulkanCommandBuffer")
            let bufferHolder = self.bufferHolder!

            var submitWaitSemaphores: [VkSemaphore?] = []
            var submitWaitStageMasks: [VkPipelineStageFlags] = []
            var submitWaitTimelineSemaphoreValues: [UInt64] = []

            var submitSignalSemaphores: [VkSemaphore?] = []
            var submitSignalTimelineSemaphoreValues: [UInt64] = []

            // reserve storage for semaphores.
            var numWaitSemaphores = 0
            var numSignalSemaphores = 0
            for encoder in self.encoders {
                numWaitSemaphores = max(encoder.waitSemaphores.count, numWaitSemaphores)
                numSignalSemaphores = max(encoder.signalSemaphores.count, numSignalSemaphores)
            }
            submitWaitSemaphores.reserveCapacity(numWaitSemaphores)
            submitWaitStageMasks.reserveCapacity(numWaitSemaphores)
            submitWaitTimelineSemaphoreValues.reserveCapacity(numWaitSemaphores)

            submitSignalSemaphores.reserveCapacity(numSignalSemaphores)
            submitSignalTimelineSemaphoreValues.reserveCapacity(numSignalSemaphores)

            self.submitCommandBuffers.reserveCapacity(self.encoders.count)
            self.submitInfos.reserveCapacity(self.encoders.count)

            for encoder in self.encoders {

                submitWaitSemaphores.removeAll(keepingCapacity: true)
                submitWaitStageMasks.removeAll(keepingCapacity: true)
                submitSignalSemaphores.removeAll(keepingCapacity: true)
                submitWaitTimelineSemaphoreValues.removeAll(keepingCapacity: true)
                submitSignalTimelineSemaphoreValues.removeAll(keepingCapacity: true)

                let commandBuffersOffset = self.submitCommandBuffers.count

                var bufferInfo = VkCommandBufferAllocateInfo()
                bufferInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
                bufferInfo.commandPool = self.commandPool
                bufferInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
                bufferInfo.commandBufferCount = 1

                var commandBufferOpt: VkCommandBuffer? = nil
                let err = vkAllocateCommandBuffers(device.device, &bufferInfo, &commandBufferOpt)
                if err != VK_SUCCESS {
                    Log.err("vkAllocateCommandBuffers failed: \(err)")
                    cleanup()
                    return false
                }
                let commandBuffer = commandBufferOpt!
                self.submitCommandBuffers.append(commandBuffer)

                encoder.waitSemaphores.forEach { (key, value) in
                    let semaphore = key
                    let stages = value.stages
                    let value = value.value  // timeline-value

                    assert((stages & UInt32(VK_PIPELINE_STAGE_HOST_BIT.rawValue)) == 0)

                    submitWaitSemaphores.append(semaphore)
                    submitWaitStageMasks.append(stages)
                    submitWaitTimelineSemaphoreValues.append(value)
                }
                assert(submitWaitSemaphores.count <= numWaitSemaphores)
                assert(submitWaitStageMasks.count <= numWaitSemaphores)
                assert(submitWaitTimelineSemaphoreValues.count <= numWaitSemaphores)

                encoder.signalSemaphores.forEach { (key, value) in
                    submitSignalSemaphores.append(key)
                    submitSignalTimelineSemaphoreValues.append(value)
                }
                assert(submitSignalSemaphores.count <= numSignalSemaphores)
                assert(submitSignalTimelineSemaphoreValues.count <= numSignalSemaphores)

                var commandBufferBeginInfo = VkCommandBufferBeginInfo()
                commandBufferBeginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO

                vkBeginCommandBuffer(commandBuffer, &commandBufferBeginInfo)
                let result = encoder.encode(commandBuffer: commandBuffer)
                vkEndCommandBuffer(commandBuffer)

                if result == false {
                    cleanup()
                    return false
                }
                assert(submitWaitSemaphores.count == submitWaitStageMasks.count)
                
                var submitInfo = VkSubmitInfo()
                submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
                var timelineSemaphoreSubmitInfo = VkTimelineSemaphoreSubmitInfo()
                timelineSemaphoreSubmitInfo.sType = VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO

                if self.submitCommandBuffers.count > commandBuffersOffset {
                    let count = self.submitCommandBuffers.count - commandBuffersOffset
                    let commandBuffers = self.submitCommandBuffers[commandBuffersOffset ..< commandBuffersOffset + count].map { Optional($0) }
                    submitInfo.commandBufferCount = UInt32(count)
                    submitInfo.pCommandBuffers = unsafePointerCopy(collection: commandBuffers, holder: bufferHolder)                  
                }
                if submitWaitSemaphores.isEmpty == false {

                    let count = submitWaitSemaphores.count

                    assert(submitWaitStageMasks.count == count)
                    assert(submitWaitTimelineSemaphoreValues.count == count)

                    submitInfo.waitSemaphoreCount = UInt32(count)
                    submitInfo.pWaitSemaphores = unsafePointerCopy(collection: submitWaitSemaphores, holder: bufferHolder)
                    submitInfo.pWaitDstStageMask = unsafePointerCopy(collection: submitWaitStageMasks, holder: bufferHolder)

                    timelineSemaphoreSubmitInfo.waitSemaphoreValueCount = UInt32(count)
                    timelineSemaphoreSubmitInfo.pWaitSemaphoreValues = unsafePointerCopy(collection: submitWaitTimelineSemaphoreValues, holder: bufferHolder)
                }
                if submitSignalSemaphores.isEmpty == false {
                    let count = submitSignalSemaphores.count

                    assert(submitSignalTimelineSemaphoreValues.count == count)

                    submitInfo.signalSemaphoreCount = UInt32(count)
                    submitInfo.pSignalSemaphores = unsafePointerCopy(collection: submitSignalSemaphores, holder: bufferHolder)

                    timelineSemaphoreSubmitInfo.signalSemaphoreValueCount = UInt32(count)
                    timelineSemaphoreSubmitInfo.pSignalSemaphoreValues = unsafePointerCopy(collection: submitSignalTimelineSemaphoreValues, holder: bufferHolder)
                }
                submitInfo.pNext = UnsafeRawPointer(unsafePointerCopy(from: timelineSemaphoreSubmitInfo, holder: bufferHolder))
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

    public func endEncoder(_ encoder: VulkanCommandEncoder) {
        self.encoders.append(encoder)
    }

    public var queueFamily: VulkanQueueFamily {
        return (self.commandQueue as! VulkanCommandQueue).family
    }
}
#endif //if ENABLE_VULKAN