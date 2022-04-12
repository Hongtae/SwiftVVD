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

    public func encode(buffer: VkCommandBuffer) -> Bool { false }

    public func addWaitSemaphore(semaphore: VkSemaphore, value: UInt64, flags: VkPipelineStageFlags) {
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

    public func addSignalSemaphore(semaphore: VkSemaphore, value: UInt64) {
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
    private var submitWaitSemaphores: [VkSemaphore] = []
    private var submitSignalSemaphores: [VkSemaphore] = []

    private var submitWaitTimelineSemaphoreValues: [UInt64] = []
    private var submitSignalTimelineSemaphoreValues: [UInt64] = []
    private var submitTimelineSemaphoreInfos: [VkTimelineSemaphoreSubmitInfo] = []

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
        false
    }

    public func endEncoder(_ encoder: VulkanCommandEncoder) {
        self.encoders.append(encoder)
    }

    public var queueFamily: VulkanQueueFamily {
        return (self.commandQueue as! VulkanCommandQueue).family
    }
}
#endif //if ENABLE_VULKAN