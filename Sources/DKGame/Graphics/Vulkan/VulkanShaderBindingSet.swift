#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanShaderBindingSet: ShaderBindingSet {
    public let device: GraphicsDevice
    public let descriptorSetLayout: VkDescriptorSetLayout
    public let layoutFlags: VkDescriptorSetLayoutCreateFlags

    private let poolID: VulkanDescriptorPoolID
    
    typealias DescriptorBinding = VulkanDescriptorSet.Binding    
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

    public func setBuffer(_ buffer: Buffer, offset: UInt64, length: UInt64, binding: UInt32) {
        self.setBufferArray([GPUBufferBindingInfo(buffer: buffer,
                                                  offset: offset,
                                                  length: length)],
                            binding:binding)
    }

    public func setBufferArray(_ buffers: [GPUBufferBindingInfo], binding: UInt32) {

    }

    // bind textures
    public func setTexture(_ texture: Texture, binding: UInt32) {
        self.setTextureArray([texture], binding: binding)
    }
    public func setTextureArray(_ textures: [Texture], binding: UInt32) {

    }

    // bind samplers
    public func setSamplerState(_ sampler: SamplerState, binding: UInt32) {
        self.setSamplerStateArray([sampler], binding: binding)
    }

    public func setSamplerStateArray(_ samplers: [SamplerState], binding: UInt32) {

    }

    public func makeDescriptorSet() -> VulkanDescriptorSet {
        let device = self.device as! VulkanGraphicsDevice
        let descriptorSet = device.makeDescriptorSet(layout: self.descriptorSetLayout, poolID: self.poolID)!
        descriptorSet.bindings = self.bindings

        let tempHolder = TemporaryBufferHolder(label: "VulkanShaderBindingSet.makeDescriptorSet")

        var descriptorWrites: [VkWriteDescriptorSet] = []
        for i in 0..<descriptorSet.bindings.count {
            if descriptorSet.bindings[i].valueSet == false { continue }

            descriptorSet.bindings[i].write.dstSet = descriptorSet.descriptorSet
            
            let binding = descriptorSet.bindings[i]
            var write = binding.write
            if binding.imageInfos.count > 0 {
                assert(binding.bufferInfos.isEmpty)
                assert(binding.texelBufferViews.isEmpty)

                write.pImageInfo = unsafePointerCopy(binding.imageInfos, holder: tempHolder)
            }
            if binding.bufferInfos.count > 0 {
                assert(binding.imageInfos.isEmpty)
                assert(binding.texelBufferViews.isEmpty)

                write.pBufferInfo = unsafePointerCopy(binding.bufferInfos, holder: tempHolder)
            }
            if binding.texelBufferViews.count > 0 {
                assert(binding.imageInfos.isEmpty)
                assert(binding.bufferInfos.isEmpty)

                write.pTexelBufferView = unsafePointerCopy(binding.texelBufferViews, holder: tempHolder)
            }
            descriptorWrites.append(write)
        }

        assert(descriptorWrites.count > 0)

        vkUpdateDescriptorSets(device.device, UInt32(descriptorWrites.count), &descriptorWrites, 0, nil)

        return descriptorSet
    }

    private func findDescriptorBinding(_ binding: UInt32) -> DescriptorBinding? {
        for b in self.bindings {
            if b.layoutBinding.binding == binding {
                return b
            }
        }
        return nil
    }

    private func updateDescriptorBinding(_ desc: DescriptorBinding, binding: UInt32) {
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
