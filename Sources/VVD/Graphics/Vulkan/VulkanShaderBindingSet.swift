//
//  File: VulkanShaderBindingSet.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanShaderBindingSet: ShaderBindingSet {
    let device: GraphicsDevice
    let descriptorSetLayout: VkDescriptorSetLayout
    let layoutFlags: VkDescriptorSetLayoutCreateFlags

    private let poolID: VulkanDescriptorPoolID
    
    typealias DescriptorBinding = VulkanDescriptorSet.Binding    
    var bindings: [DescriptorBinding]

    init(device: VulkanGraphicsDevice,
         layout: VkDescriptorSetLayout,
         poolID: VulkanDescriptorPoolID,
         layoutCreateInfo: VkDescriptorSetLayoutCreateInfo) {
        self.device = device
        self.descriptorSetLayout = layout
        self.poolID = poolID
        self.layoutFlags = layoutCreateInfo.flags

        self.bindings = (0..<Int(layoutCreateInfo.bindingCount)).map {
            let binding = layoutCreateInfo.pBindings[$0]
            return DescriptorBinding(layoutBinding: binding)
        }
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroyDescriptorSetLayout(device.device, descriptorSetLayout, device.allocationCallbacks)
    }

    func setBuffer(_ buffer: GPUBuffer, offset: Int, length: Int, binding: Int) {
        self.setBufferArray([BufferBindingInfo(buffer: buffer,
                                               offset: offset,
                                               length: length)],
                            binding:binding)
    }

    func setBufferArray(_ buffers: [BufferBindingInfo], binding: Int) {
        if var descriptorBinding = self.findDescriptorBinding(binding) {
            descriptorBinding.valueSet = false
            descriptorBinding.bufferInfos = []
            descriptorBinding.imageInfos = []
            descriptorBinding.texelBufferViews = []
            descriptorBinding.bufferViews = []
            descriptorBinding.imageViews = []
            descriptorBinding.samplers = []

            let descriptor = descriptorBinding.layoutBinding

            let startingIndex = 0
            let availableItems = min(buffers.count, Int(descriptor.descriptorCount) - startingIndex)
            assert(availableItems <= buffers.count)

            var write = VkWriteDescriptorSet()
            write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
            write.dstSet = nil
            write.dstBinding = descriptor.binding
            write.dstArrayElement = UInt32(startingIndex)
            write.descriptorCount = UInt32(availableItems)
            write.descriptorType = descriptor.descriptorType

            assert(descriptorBinding.bufferInfos.isEmpty)
            assert(descriptorBinding.texelBufferViews.isEmpty)

            switch descriptor.descriptorType {
            case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
                 VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
                // bufferView (pTexelBufferView)
                descriptorBinding.texelBufferViews.reserveCapacity(availableItems)
                for i in 0..<availableItems {
                    let bufferView = buffers[i].buffer as? VulkanBufferView
                    assert(bufferView != nil) 
                    if let bufferView = bufferView {
                        descriptorBinding.texelBufferViews.append(bufferView.bufferView!)
                    }
                }
            case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                 VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                 VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
                 VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
                // buffer (pBufferInfo)
                descriptorBinding.bufferInfos.reserveCapacity(availableItems)
                for i in 0..<availableItems {
                    let bufferView = buffers[i].buffer as? VulkanBufferView
                    let buffer = bufferView?.buffer
                    assert(buffer != nil)
                    if let buffer = buffer {
                        var bufferInfo = VkDescriptorBufferInfo()
                        bufferInfo.buffer = buffer.buffer
                        bufferInfo.offset = VkDeviceSize(buffers[i].offset)
                        bufferInfo.range = VkDeviceSize(buffers[i].length)

                        descriptorBinding.bufferInfos.append(bufferInfo)
                    }
                }
            default:
                Log.err("Invalid descriptor type!")
                assertionFailure("Invalid descriptor type!")
                return
            }

            // take ownership of resource.
            descriptorBinding.bufferViews.reserveCapacity(availableItems)
            for i in 0..<availableItems {
                if let bufferView = buffers[i].buffer as? VulkanBufferView {
                    descriptorBinding.bufferViews.append(bufferView)
                }
            }

            // update binding!
            descriptorBinding.write = write
            descriptorBinding.valueSet = true
            self.updateDescriptorBinding(descriptorBinding, binding: binding)
        }
    }

    // bind textures
    func setTexture(_ texture: Texture, binding: Int) {
        self.setTextureArray([texture], binding: binding)
    }

    func setTextureArray(_ textures: [Texture], binding: Int) {
        if var descriptorBinding = self.findDescriptorBinding(binding) {

            descriptorBinding.bufferInfos = []
            descriptorBinding.texelBufferViews = []
            descriptorBinding.bufferViews = []
            descriptorBinding.imageViews = []

            let descriptor = descriptorBinding.layoutBinding

            let startingIndex = 0
            let availableItems = min(textures.count, Int(descriptor.descriptorCount) - startingIndex)
            assert(availableItems <= textures.count)

            var write = descriptorBinding.write
            if descriptorBinding.valueSet == false {
                write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
                write.dstSet = nil
                write.dstBinding = descriptor.binding
                write.dstArrayElement = UInt32(startingIndex)
                write.descriptorCount = UInt32(availableItems)  // number of descriptors to update.
                write.descriptorType = descriptor.descriptorType
                descriptorBinding.write = write
                descriptorBinding.valueSet = true
                descriptorBinding.imageInfos = []
                descriptorBinding.samplers = []  // clear samplers
            }
            write.dstArrayElement = UInt32(startingIndex)
            write.descriptorCount = UInt32(availableItems)

            let getImageLayout = { (type: VkDescriptorType, pixelFormat: PixelFormat) -> VkImageLayout in
                var imageLayout: VkImageLayout = VK_IMAGE_LAYOUT_UNDEFINED
                switch type {
                case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                     VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
                    imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
                case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
                    imageLayout = VK_IMAGE_LAYOUT_GENERAL
                case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
                    imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
                default:
                    imageLayout = VK_IMAGE_LAYOUT_GENERAL
                }
                return imageLayout
            }

            switch descriptor.descriptorType {
                // pImageInfo
            case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                 VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
                 VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
                 VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
                    descriptorBinding.imageViews.reserveCapacity(availableItems)
                    for i in 0..<availableItems {
                        if i >= descriptorBinding.imageInfos.count {
                            descriptorBinding.imageInfos.append(VkDescriptorImageInfo())
                        }
                        assert(descriptorBinding.imageInfos.count > i)

                        let imageView = textures[i] as? VulkanImageView
                        assert(imageView != nil)

                        if let imageView = imageView {
                            let image = imageView.image!
                            if (descriptor.descriptorType == VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT) {
                                if (image.usage & UInt32(VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT.rawValue)) == 0 {
                                    Log.err("ImageView image does not have usage flag:VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT")
                                }
                            }

                            var imageInfo = descriptorBinding.imageInfos[i]
                            imageInfo.imageView = imageView.imageView
                            imageInfo.imageLayout = getImageLayout(descriptor.descriptorType, image.pixelFormat)
                            descriptorBinding.imageInfos[i] = imageInfo
                            descriptorBinding.imageViews.append(imageView)
                        }
                    }
            default:
                Log.err("Invalid descriptor type!")
                assertionFailure("Invalid descriptor type!")
                return
            }

            // update binding!
            descriptorBinding.write = write
            descriptorBinding.valueSet = true
            self.updateDescriptorBinding(descriptorBinding, binding: binding)
        }
    }

    // bind samplers
    func setSamplerState(_ sampler: SamplerState, binding: Int) {
        self.setSamplerStateArray([sampler], binding: binding)
    }

    func setSamplerStateArray(_ samplers: [SamplerState], binding: Int) {
        if var descriptorBinding = self.findDescriptorBinding(binding) {

            descriptorBinding.bufferInfos = []
            descriptorBinding.texelBufferViews = []
            descriptorBinding.bufferViews = []
            descriptorBinding.samplers = []

            let descriptor = descriptorBinding.layoutBinding

            let startingIndex = 0
            let availableItems = min(samplers.count, Int(descriptor.descriptorCount) - startingIndex)
            assert(availableItems <= samplers.count)

            var write = descriptorBinding.write
            if descriptorBinding.valueSet == false {
                write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
                write.dstSet = nil
                write.dstBinding = descriptor.binding
                write.dstArrayElement = UInt32(startingIndex)
                write.descriptorCount = UInt32(availableItems)  // number of descriptors to update.
                write.descriptorType = descriptor.descriptorType
                descriptorBinding.write = write
                descriptorBinding.valueSet = true
                descriptorBinding.imageInfos = []
                descriptorBinding.imageViews = []  // clear imageViews
            }
            write.dstArrayElement = UInt32(startingIndex)
            write.descriptorCount = UInt32(availableItems)

            switch descriptor.descriptorType {
            case VK_DESCRIPTOR_TYPE_SAMPLER,
                 VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
                descriptorBinding.samplers.reserveCapacity(availableItems)
                for i in 0..<availableItems {
                    if i >= descriptorBinding.imageInfos.count {
                        descriptorBinding.imageInfos.append(VkDescriptorImageInfo())
                    }
                    assert(descriptorBinding.imageInfos.count > i)

                    let sampler = samplers[i] as? VulkanSampler
                    assert(sampler != nil)
                    if let sampler = sampler {
                        descriptorBinding.imageInfos[i].sampler = sampler.sampler
                        // take ownership of sampler
                        descriptorBinding.samplers.append(sampler)
                    }
            }
            default:
                Log.err("Invalid descriptor type!")
                assertionFailure("Invalid descriptor type!")
                return
            }
            
            // update binding!
            descriptorBinding.write = write
            descriptorBinding.valueSet = true
            self.updateDescriptorBinding(descriptorBinding, binding: binding)
        }
    }

    func makeDescriptorSet() -> VulkanDescriptorSet {
        let device = self.device as! VulkanGraphicsDevice
        let descriptorSet = device.makeDescriptorSet(layout: self.descriptorSetLayout, poolID: self.poolID)!
        descriptorSet.bindings = self.bindings

        let tempHolder = TemporaryBufferHolder(label: "VulkanShaderBindingSet.makeDescriptorSet")

        var descriptorWrites: [VkWriteDescriptorSet] = []
        descriptorWrites.reserveCapacity(descriptorSet.bindings.count)

        for i in 0..<descriptorSet.bindings.count {
            if descriptorSet.bindings[i].valueSet == false { continue }

            descriptorSet.bindings[i].write.dstSet = descriptorSet.descriptorSet
            
            let binding = descriptorSet.bindings[i]
            var write = binding.write
            if binding.imageInfos.count > 0 {
                assert(binding.bufferInfos.isEmpty)
                assert(binding.texelBufferViews.isEmpty)

                write.pImageInfo = unsafePointerCopy(collection: binding.imageInfos, holder: tempHolder)
            }
            if binding.bufferInfos.count > 0 {
                assert(binding.imageInfos.isEmpty)
                assert(binding.texelBufferViews.isEmpty)

                write.pBufferInfo = unsafePointerCopy(collection: binding.bufferInfos, holder: tempHolder)
            }
            if binding.texelBufferViews.count > 0 {
                assert(binding.imageInfos.isEmpty)
                assert(binding.bufferInfos.isEmpty)

                write.pTexelBufferView = unsafePointerCopy(collection: binding.texelBufferViews, holder: tempHolder)
            }
            descriptorWrites.append(write)
        }

        assert(descriptorWrites.count > 0)

        vkUpdateDescriptorSets(device.device, UInt32(descriptorWrites.count), &descriptorWrites, 0, nil)

        return descriptorSet
    }

    private func findDescriptorBinding(_ binding: Int) -> DescriptorBinding? {
        for b in self.bindings {
            if b.layoutBinding.binding == binding {
                return b
            }
        }
        return nil
    }

    private func updateDescriptorBinding(_ desc: DescriptorBinding, binding: Int) {
        for i in 0..<self.bindings.count {
            let b = self.bindings[i]            
            if b.layoutBinding.binding == binding {
                self.bindings[i] = desc
                break
            }
        }
    }
}

#endif //if ENABLE_VULKAN
