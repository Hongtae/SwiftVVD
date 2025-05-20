//
//  File: VulkanDescriptorSet.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanDescriptorSet {
    let device: VulkanGraphicsDevice
    let descriptorSet: VkDescriptorSet
    let descriptorPool: VulkanDescriptorPool

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

    init(device: VulkanGraphicsDevice, descriptorPool: VulkanDescriptorPool, descriptorSet: VkDescriptorSet) {
        self.device = device
        self.descriptorPool = descriptorPool
        self.descriptorSet = descriptorSet
    }

    deinit {
        device.releaseDescriptorSets([self.descriptorSet], pool: self.descriptorPool)
    }

    struct ImageLayoutInfo {
        let image: VulkanImage
        var layout: VkImageLayout
    }
    struct ImageViewLayoutInfo {
        let imageView: VulkanImageView
        var layout: VkImageLayout
    }
    typealias ImageLayoutMap = [VkImage: ImageLayoutInfo]
    typealias ImageViewLayoutMap = [VkImageView: ImageViewLayoutInfo]

    func collectImageViewLayouts(_ imageLayouts: inout ImageLayoutMap,
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

            for imageInfo in binding.imageInfos {
                if imageInfo.imageView == nil { continue }

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

    func updateImageViewLayouts(_ imageLayouts: ImageViewLayoutMap) {
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
                assert(write.descriptorCount == binding.imageInfos.count)
                for j in 0..<Int(binding.imageInfos.count) {
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
