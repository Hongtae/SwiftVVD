#if ENABLE_VULKAN
import Vulkan
import Foundation

let descriptorTypes: [VkDescriptorType] = [
    VK_DESCRIPTOR_TYPE_SAMPLER,
    VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
    VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
    VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
    VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER,
    VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
    VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
    VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC,
    VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT,
    VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT
].sorted { $0.rawValue < $1.rawValue }

private func index(of type: VkDescriptorType) -> Int {
    var begin = 0
    var count = descriptorTypes.count
    var mid = begin
    while count > 0 {
        mid = count / 2
        if descriptorTypes[begin + mid].rawValue < type.rawValue {
            begin += mid + 1
            count -= mid + 1
        } else {
            count = mid
        }
    }
    assert(begin >= 0 && begin < descriptorTypes.count)
    return begin
}

public struct VulkanDescriptorPoolID: Hashable, Equatable {
    public let mask: UInt32
    public let typeSize: [UInt32]

    public init() {
        self.mask = 0
        self.typeSize = .init(repeating: 0, count: descriptorTypes.count)
    }

    public init(poolSizes: [VkDescriptorPoolSize]) {
        var typeSize: [UInt32] = .init(repeating: 0, count: descriptorTypes.count)
        for i in 0..<poolSizes.count {
            let poolSize = poolSizes[i]
            let index = index(of: poolSize.type)
            typeSize[index] += poolSize.descriptorCount
        }
        var mask: UInt32 = 0
        for i in 0..<typeSize.count {
            if typeSize[i] > 0 {
                mask = mask | (1 << i)
            }
        }
        self.mask = mask
        self.typeSize = typeSize
    }

    public init(layout: ShaderBindingSetLayout) {
        var typeSize: [UInt32] = .init(repeating: 0, count: descriptorTypes.count)
        for binding in layout.bindings {
            let type = binding.type.vkType()
            let index = index(of: type)
            typeSize[index] += binding.arrayLength
        }
        var mask: UInt32 = 0
        for i in 0..<typeSize.count {
            if typeSize[i] > 0 {
                mask = mask | (1 << i)
            }
        }
        self.mask = mask
        self.typeSize = typeSize
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(mask)
        for type in typeSize {
            hasher.combine(type)
        }
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        if lhs.mask == rhs.mask {
            for i in 0..<descriptorTypes.count {
                if lhs.typeSize[i] != rhs.typeSize[i] {
                    return false
                }
            }
            return true
        }
        return false
    }
}

public class VulkanDescriptorPool {
    public let poolID: VulkanDescriptorPoolID
    public let pool: VkDescriptorPool
    public let poolCreateFlags: VkDescriptorPoolCreateFlags
    public let maxSets: UInt32
    public let device: VulkanGraphicsDevice

    public var numAllocatedSets: UInt32

    public init(device: VulkanGraphicsDevice, pool: VkDescriptorPool, poolCreateInfo: VkDescriptorPoolCreateInfo, poolID: VulkanDescriptorPoolID) {
        self.device = device
        self.pool = pool
        self.poolID = poolID
        self.poolCreateFlags = poolCreateInfo.flags
        self.maxSets = poolCreateInfo.maxSets
        self.numAllocatedSets = 0
    }

    deinit {
        vkDestroyDescriptorPool(device.device, pool, device.allocationCallbacks)
    }

    public func allocateDescriptorSet(layout: VkDescriptorSetLayout) -> VkDescriptorSet? {
        var allocateInfo = VkDescriptorSetAllocateInfo()
        allocateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
        allocateInfo.descriptorPool = self.pool
        allocateInfo.descriptorSetCount = 1

        var descriptorSet: VkDescriptorSet? = nil
        let result: VkResult = withUnsafePointer(to: Optional(layout)) {
            allocateInfo.pSetLayouts = $0
            return vkAllocateDescriptorSets(device.device, &allocateInfo, &descriptorSet)
        }
        if result == VK_SUCCESS {
            numAllocatedSets += 1
        } else {
            Log.err("vkAllocateDescriptorSets failed: \(result)")
        }
        return descriptorSet
    }

    public func release(descriptorSets: [VkDescriptorSet]) {
        assert(numAllocatedSets > 0)
        guard descriptorSets.isEmpty == false else { return }
        
        self.numAllocatedSets -= UInt32(descriptorSets.count)
        if self.numAllocatedSets == 0 {
            let result = vkResetDescriptorPool(self.device.device, pool, 0);
            if result != VK_SUCCESS {
                Log.err("vkResetDescriptorPool failed: \(result)")
            }
        } else if self.poolCreateFlags & UInt32(VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT.rawValue) != 0 {
            let optionalSets = descriptorSets.map{ Optional($0) }
            let result = optionalSets.withUnsafeBufferPointer {
                vkFreeDescriptorSets(self.device.device, self.pool, UInt32($0.count), $0.baseAddress);
            }
            assert(result == VK_SUCCESS)
            if result != VK_SUCCESS {
                Log.err("vkFreeDescriptorSets failed: \(result)")
            }
        }
    }
}

#endif //if ENABLE_VULKAN