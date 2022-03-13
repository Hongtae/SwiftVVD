#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanCommandBuffer: CommandBuffer {

    public let commandQueue: CommandQueue
    public let device: GraphicsDevice   

    public init(pool: VkCommandPool, queue: VulkanCommandQueue) {
        self.commandQueue = queue
        self.device = queue.device
    }

    public func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder? {
        nil
    }

    public func makeComputeCommandEncoder() -> ComputeCommandEncoder? {
        nil
    }

    public func makeCopyCommandEncoder() -> CopyCommandEncoder? {
        nil
    }

    public func addCompletedHandler(_ handler: CommandBufferHandler) {

    }
}
#endif //if ENABLE_VULKAN