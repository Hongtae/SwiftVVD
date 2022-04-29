#if ENABLE_VULKAN
import Vulkan
import Foundation

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

            var submitWaitSemaphores: [VkSemaphore] = []
            var submitWaitStageMasks: [VkPipelineStageFlags] = []
            var submitSignalSemaphores: [VkSemaphore] = []

            var submitWaitTimelineSemaphoreValues: [UInt64] = []
            var submitSignalTimelineSemaphoreValues: [UInt64] = []

            // reserve storage for semaphores.
            var numWaitSemaphores = 0
            var numSignalSemaphores = 0
            for encoder in self.encoders {
                numWaitSemaphores += encoder.waitSemaphores.count
                numSignalSemaphores += encoder.signalSemaphores.count
            }
            submitWaitSemaphores.reserveCapacity(numWaitSemaphores)
            submitWaitStageMasks.reserveCapacity(numWaitSemaphores)
            submitSignalSemaphores.reserveCapacity(numSignalSemaphores)

            submitWaitTimelineSemaphoreValues.reserveCapacity(numWaitSemaphores)
            submitSignalTimelineSemaphoreValues.reserveCapacity(numSignalSemaphores)

            self.submitCommandBuffers.reserveCapacity(self.encoders.count)
            self.submitInfos.reserveCapacity(self.encoders.count)

            for encoder in self.encoders {
                let commandBuffersOffset = submitCommandBuffers.count
                let waitSemaphoresOffset = submitWaitSemaphores.count
                let signalSemaphoresOffset = submitSignalSemaphores.count

                assert(submitWaitStageMasks.count == waitSemaphoresOffset)
                assert(submitWaitTimelineSemaphoreValues.count == waitSemaphoresOffset)
                assert(submitSignalTimelineSemaphoreValues.count == signalSemaphoresOffset)

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
                if submitWaitSemaphores.count > waitSemaphoresOffset {
                    let count = submitWaitSemaphores.count - waitSemaphoresOffset
                    let range = waitSemaphoresOffset ..< (waitSemaphoresOffset + count)
                    let semaphores = submitWaitSemaphores[range].map { Optional($0) }
                    let stages = submitWaitStageMasks[range]
                    let timelineValues = submitWaitTimelineSemaphoreValues[range]

                    submitInfo.waitSemaphoreCount = UInt32(count)
                    submitInfo.pWaitSemaphores = unsafePointerCopy(collection: semaphores, holder: bufferHolder)
                    submitInfo.pWaitDstStageMask = unsafePointerCopy(collection: stages, holder: bufferHolder)

                    timelineSemaphoreSubmitInfo.pWaitSemaphoreValues = unsafePointerCopy(collection: timelineValues, holder: bufferHolder)
                    timelineSemaphoreSubmitInfo.waitSemaphoreValueCount = UInt32(count)
                }
                if submitSignalSemaphores.count > signalSemaphoresOffset {
                    let count = submitSignalSemaphores.count - signalSemaphoresOffset
                    let range = signalSemaphoresOffset ..< (signalSemaphoresOffset + count)
                    let semaphores = submitSignalSemaphores[range].map { Optional($0) }
                    let timelineValues = submitSignalTimelineSemaphoreValues[range]

                    submitInfo.signalSemaphoreCount = UInt32(count)
                    submitInfo.pSignalSemaphores = unsafePointerCopy(collection: semaphores, holder: bufferHolder)

                    timelineSemaphoreSubmitInfo.pSignalSemaphoreValues = unsafePointerCopy(collection: timelineValues, holder: bufferHolder)
                    timelineSemaphoreSubmitInfo.signalSemaphoreValueCount = UInt32(count)
                }
                submitInfo.pNext = UnsafeRawPointer(unsafePointerCopy(from: timelineSemaphoreSubmitInfo, holder: bufferHolder))
                self.submitInfos.append(submitInfo)
            }
        }

        if self.submitInfos.isEmpty == false {
            assert(self.submitInfos.count == self.encoders.count)

            let commandQueue = self.commandQueue as! VulkanCommandQueue
            return commandQueue.submit(self.submitInfos) {
                for op in self.completedHandlers {
                    op(self)
                }
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