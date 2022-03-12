import Vulkan
import Foundation

public class VulkanCommandQueue: CommandQueue {

    public let device: GraphicsDevice
    public let queueTypeMask: CommandQueueTypeMask

    public init(device: VulkanGraphicsDevice, queueFamily: VulkanQueueFamily, queue: VkQueue) {

        let queueFlags = queueFamily.properties.queueFlags

        let copy = (queueFlags & UInt32(VK_QUEUE_TRANSFER_BIT.rawValue)) != 0
        let compute = (queueFlags & UInt32(VK_QUEUE_COMPUTE_BIT.rawValue)) != 0
        let graphics = (queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue)) != 0

        var typeMask: CommandQueueTypeMask = []
        if copy {
            typeMask.insert(.copy)
        }
        if graphics {
            typeMask.insert(.graphics)
        }
        if compute {
            typeMask.insert(.compute)
        }
        self.queueTypeMask = typeMask
        self.device = device
    }

    public func makeCommandBuffer() -> CommandBuffer? { nil }
    public func makeSwapChain() -> SwapChain? { nil } 
}
