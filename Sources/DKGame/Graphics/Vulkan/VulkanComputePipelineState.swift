#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanComputePipelineState: ComputePipelineState {
    public let device: GraphicsDevice
    public let pipeline: VkPipeline
    public let pipelineLayout: VkPipelineLayout

    public init(device: VulkanGraphicsDevice, pipeline: VkPipeline, pipelineLayout: VkPipelineLayout) {
        self.device = device
        self.pipeline = pipeline
        self.pipelineLayout = pipelineLayout
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroyPipeline(device.device, pipeline, device.allocationCallbacks)
	    vkDestroyPipelineLayout(device.device, pipelineLayout, device.allocationCallbacks)
    }
}

#endif //if ENABLE_VULKAN
