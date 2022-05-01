#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanDescriptorSet {
    public let device: VulkanGraphicsDevice
    public let descriptorSet: VkDescriptorSet
    public let descriptorPool: VulkanDescriptorPool

    struct Binding {
        let layoutBinding: VkDescriptorSetLayoutBinding

        var bufferViews: [VulkanBufferView] = []
        var imageViews: [VulkanImageView] = []
        var samplers: [VulkanSampler] = []

        var imageInfos: [VkDescriptorImageInfo] = []
        var bufferInfos: [VkDescriptorBufferInfo] = []
        var texelBufferViews: [VkBufferView] = []

        var write = VkWriteDescriptorSet()
        var valueSet = false
    }
    var bindings: [Binding] = []

    public init(device: VulkanGraphicsDevice, descriptorPool: VulkanDescriptorPool, descriptorSet: VkDescriptorSet) {
        self.device = device
        self.descriptorPool = descriptorPool
        self.descriptorSet = descriptorSet
    }

    deinit {
        device.releaseDescriptorSets([self.descriptorSet], from: self.descriptorPool)
    }

    public struct ImageLayoutInfo {
        public let image: VulkanImage
        public var layout: VkImageLayout
    }
    public struct ImageViewLayoutInfo {
        public let imageView: VulkanImageView
        public var layout: VkImageLayout
    }
    public typealias ImageLayoutMap = [VkImage: ImageLayoutInfo]
    public typealias ImageViewLayoutMap = [VkImageView: ImageViewLayoutInfo]

    public func collectImageViewLayouts(_ imageLayouts: inout ImageLayoutMap,
                                        _ imageViewLayouts: inout ImageViewLayoutMap) {
        var imageViewMap: [VkImageView: VulkanImageView] = [:]
        for binding in self.bindings {
            if binding.valueSet == false {
                continue
            }
            for view in binding.imageViews {
                imageViewMap[view.imageView] = view
            }
        }
        for binding in self.bindings {
            if binding.valueSet == false {
                continue
            }

            let write = binding.write
            let imageInfo = write.pImageInfo
            if let imageInfo = imageInfo?.pointee, imageInfo.imageView != nil {

                assert(imageViewMap[imageInfo.imageView] != nil)

                if let imageView = imageViewMap[imageInfo.imageView!] {
                    assert(imageView.imageView == imageInfo.imageView)

                    let image: VkImage = imageView.image!.image!
                    let layout: VkImageLayout = imageInfo.imageLayout

                    if var layoutInfo = imageLayouts[image] {
                        assert(layoutInfo.layout != VK_IMAGE_LAYOUT_UNDEFINED)
                        assert(imageInfo.imageLayout != VK_IMAGE_LAYOUT_UNDEFINED)

                        if layoutInfo.layout != imageInfo.imageLayout {
                            layoutInfo.layout = VK_IMAGE_LAYOUT_GENERAL
                            imageLayouts[image] = layoutInfo
                        }
                    } else {
                        imageLayouts[image] = ImageLayoutInfo(image: imageView.image!, layout: imageInfo.imageLayout)
                    }

                    imageViewLayouts[imageInfo.imageView] = ImageViewLayoutInfo(imageView: imageView, layout: layout)
                }
            }
        }
    }

    public func updateImageViewLayouts(_ imageLayouts: ImageViewLayoutMap) {
        var descriptorWrites: [VkWriteDescriptorSet] = []
        descriptorWrites.reserveCapacity(self.bindings.count)

        let tempHolder = TemporaryBufferHolder(label: "VulkanDescriptorSet.updateImageViewLayouts")

        for i in 0..<self.bindings.count {
            if self.bindings[i].valueSet == false {
                continue
            }

            var binding = self.bindings[i]
            var write = binding.write
            assert(write.dstSet == descriptorSet)
            assert(write.dstBinding == binding.layoutBinding.binding)

            if binding.imageInfos.isEmpty == false {
                var update = false
                for j in 0..<Int(write.descriptorCount) {
                    let imageInfo = binding.imageInfos[j]
                    if let imageView = imageInfo.imageView {
                        if let layoutInfo = imageLayouts[imageView] {
                            if imageInfo.imageLayout != layoutInfo.layout {
                                // update layout
                                binding.imageInfos[j].imageLayout = layoutInfo.layout
                                update = true
                            }
                        } else {
                            // imageInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL
                            Log.err("Cannot find proper image layout!")
                        }
                    }
                }
                if update {
                    self.bindings[i].imageInfos = binding.imageInfos
                    write.pImageInfo = unsafePointerCopy(collection: binding.imageInfos, holder: tempHolder)
                    descriptorWrites.append(write)
                }
            }
        }

        if descriptorWrites.count > 0 {
            let device = self.device
            vkUpdateDescriptorSets(device.device, UInt32(descriptorWrites.count), &descriptorWrites, 0, nil)
        }
    }
}

#endif //if ENABLE_VULKAN
