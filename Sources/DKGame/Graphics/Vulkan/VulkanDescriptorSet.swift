#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanDescriptorSet {
    public let device: VulkanGraphicsDevice
    public let descriptorSet: VkDescriptorSet
    public let descriptorPool: VulkanDescriptorPool

    public init(device: VulkanGraphicsDevice, descriptorPool: VulkanDescriptorPool, descriptorSet: VkDescriptorSet) {
        self.device = device
        self.descriptorPool = descriptorPool
        self.descriptorSet = descriptorSet
    }

    deinit {
        // device.destroyDescriptorSet(self.descriptorPool, self.descriptorSet)
    }
}

#endif //if ENABLE_VULKAN
