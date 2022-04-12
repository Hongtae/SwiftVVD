#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanShaderBindingSet: ShaderBindingSet {
    public let device: GraphicsDevice
    public let descriptorSetLayout: VkDescriptorSetLayout
    public let layoutFlags: VkDescriptorSetLayoutCreateFlags
    public let poolID: VulkanDescriptorPoolID

    public var descriptorSet: VulkanDescriptorSet? = nil
    struct DescriptorBinding {
        let layoutBinding: VkDescriptorSetLayoutBinding

        // hold resource object ownership
        var bufferViews: [VulkanBufferView] = []
        var imageViews: [VulkanImageView] = []
        var samplers: [VulkanSampler] = []

        // descriptor infos (for storage of VkWriteDescriptorSets)
        var imageInfos: [VkDescriptorImageInfo] = []
        var bufferInfos: [VkDescriptorBufferInfo] = []
        var texelBufferViews: [VkBufferView] = []

        // pending updates (vkUpdateDescriptorSets)
        var descriptorWrites: [VkWriteDescriptorSet] = []

        var dirty: Bool = false
    }
    var bindings: [DescriptorBinding]

    public init(device: VulkanGraphicsDevice,
                layout: VkDescriptorSetLayout,
                poolID: VulkanDescriptorPoolID,
                layoutCreateInfo: VkDescriptorSetLayoutCreateInfo) {
        self.device = device
        self.descriptorSetLayout = layout
        self.poolID = poolID
        self.layoutFlags = layoutCreateInfo.flags

        self.bindings = []
        for i in 0..<Int(layoutCreateInfo.bindingCount) {
            let binding = layoutCreateInfo.pBindings[i]

            self.bindings.append(DescriptorBinding(layoutBinding: binding))
        }
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroyDescriptorSetLayout(device.device, descriptorSetLayout, device.allocationCallbacks)
    }

    public typealias ImageLayoutMap = [VkImage: VkImageLayout]
    public typealias ImageViewLayoutMap = [VkImageView: VkImageLayout]

    public func collectImageViewLayouts(imageLayouts: inout ImageLayoutMap, imageViewLayouts: inout ImageViewLayoutMap) {
        var imageViewMap: [VkImageView: VulkanImageView] = [:]
        for binding in self.bindings {
            for view in binding.imageViews {
                imageViewMap[view.imageView] = view
            }
        }
        for binding in self.bindings {
            for write in binding.descriptorWrites {
                let imageInfo = write.pImageInfo
                if let imageInfo = imageInfo?.pointee, imageInfo.imageView != nil {
                    if let imageView = imageViewMap[imageInfo.imageView!] {
                        assert(imageView.imageView == imageInfo.imageView)

                        let image: VkImage = imageView.image!.image!
                        var layout: VkImageLayout = imageInfo.imageLayout

                        if let p = imageLayouts[image] {
                            assert(p != VK_IMAGE_LAYOUT_UNDEFINED)
                            assert(imageInfo.imageLayout != VK_IMAGE_LAYOUT_UNDEFINED)

                            if p != imageInfo.imageLayout {
                                layout = VK_IMAGE_LAYOUT_GENERAL
                                imageLayouts[image] = layout
                            }
                        } else {
                            imageLayouts[image] = imageInfo.imageLayout
                        }

                        imageViewLayouts[imageInfo.imageView] = layout
                    }
                }
            }
        }
    }

    public func makeDescriptorSet(imageLayouts: ImageViewLayoutMap) -> VulkanDescriptorSet? {
        return nil
    }

    public func setBuffer(binding: UInt32, buffer: Buffer, offset: UInt64, length: UInt64) {

    }

    public func setBufferArray(binding: UInt32, buffers: [GPUBufferBindingInfo]) {

    }

    public func setTexture(binding: UInt32, texture: Texture) {

    }
    public func setTextureArray(binding: UInt32, textures: [Texture]) {

    }

    public func setSamplerState(binding: UInt32, sampler: SamplerState) {

    }
    public func setSamplerStateArray(binding: UInt32, samplers: [SamplerState]){
        
    }
}

#endif //if ENABLE_VULKAN
