#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanDescriptorSet {
    public let device: VulkanGraphicsDevice
    public let descriptorSet: VkDescriptorSet
    public let descriptorPool: VulkanDescriptorPool

    public var bufferViews: [VulkanBufferView]
    public var imageViews: [VulkanImageView]
    public var samplers: [VulkanSampler]

    public init(device: VulkanGraphicsDevice, descriptorPool: VulkanDescriptorPool, descriptorSet: VkDescriptorSet) {
        self.device = device
        self.descriptorPool = descriptorPool
        self.descriptorSet = descriptorSet
        self.bufferViews = []
        self.imageViews = []
        self.samplers = []
    }

    deinit {
        device.releaseDescriptorSets([self.descriptorSet], from: self.descriptorPool)
    }
}

#endif //if ENABLE_VULKAN
