import Vulkan
import Foundation

public class VulkanCommandQueue: CommandQueue {

    public let device: GraphicsDevice
    public let flags: CommandQueueFlags

    public init(device: VulkanGraphicsDevice, queueFamily: VulkanQueueFamily, queue: VkQueue) {

        let queueFlags = queueFamily.properties.queueFlags

        let copy = (queueFlags & UInt32(VK_QUEUE_TRANSFER_BIT.rawValue)) != 0
        let compute = (queueFlags & UInt32(VK_QUEUE_COMPUTE_BIT.rawValue)) != 0
        let graphics = (queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue)) != 0

        var flags: CommandQueueFlags = []
        if copy {
            flags.insert(.copy)
        }
        if graphics {
            flags.insert(.graphics)
        }
        if compute {
            flags.insert(.compute)
        }
        self.flags = flags
        self.device = device
    }

    public func makeCommandBuffer() -> CommandBuffer? { nil }
    public func makeSwapChain() -> SwapChain? { nil } 
}
