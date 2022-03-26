#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanSampler: SamplerState {
    public let device: GraphicsDevice
    public let sampler: VkSampler

    public init(device: VulkanGraphicsDevice, sampler: VkSampler) {
        self.device = device
        self.sampler = sampler
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroySampler(device.device, sampler, device.allocationCallbacks)
    }
}

#endif //if ENABLE_VULKAN
