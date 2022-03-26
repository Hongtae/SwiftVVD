#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanRenderPipelineState: RenderPipelineState {
    public let device: GraphicsDevice
    public let pipeline: VkPipeline
    public let pipelineLayout: VkPipelineLayout
    public let renderPass: VkRenderPass

    public init(device: VulkanGraphicsDevice, pipeline: VkPipeline, pipelineLayout: VkPipelineLayout, renderPass: VkRenderPass) {
        self.device = device
        self.pipeline = pipeline
        self.pipelineLayout = pipelineLayout
        self.renderPass = renderPass
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroyPipeline(device.device, pipeline, device.allocationCallbacks)
	    vkDestroyPipelineLayout(device.device, pipelineLayout, device.allocationCallbacks)
    	vkDestroyRenderPass(device.device, renderPass, device.allocationCallbacks)
    }
}

#endif //if ENABLE_VULKAN
