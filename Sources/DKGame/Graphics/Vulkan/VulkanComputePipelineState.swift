#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanComputePipelineState: ComputePipelineState {
    public let device: GraphicsDevice
    public let pipeline: VkPipeline
    public let layout: VkPipelineLayout

    public init(device: VulkanGraphicsDevice, pipeline: VkPipeline, layout: VkPipelineLayout) {
        self.device = device
        self.pipeline = pipeline
        self.layout = layout
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroyPipeline(device.device, pipeline, device.allocationCallbacks)
	    vkDestroyPipelineLayout(device.device, layout, device.allocationCallbacks)
    }
}

#endif //if ENABLE_VULKAN
