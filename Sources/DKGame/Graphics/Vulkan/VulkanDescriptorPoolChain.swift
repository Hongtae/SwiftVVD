#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanDescriptorPoolChain {
    public weak var device: VulkanGraphicsDevice?
    public let poolID: VulkanDescriptorPoolID
    
    private var maxSets: UInt32
    private var descriptorPools: [VulkanDescriptorPool]
    
    public struct AllocationInfo {
        public let descriptorSet: VkDescriptorSet
        public let descriptorPool: VulkanDescriptorPool
    }

    public init(device: VulkanGraphicsDevice, poolID: VulkanDescriptorPoolID) {
        self.device = device
        self.poolID = poolID
        self.maxSets = 0
        self.descriptorPools = []
    }

    public func allocateDescriptorSet(layout: VkDescriptorSetLayout) -> AllocationInfo? {
        for i in 0..<self.descriptorPools.count {
            let pool = self.descriptorPools[i]
            if let ds = pool.allocateDescriptorSet(layout: layout) {
                if i > 0 {
                    self.descriptorPools.swapAt(i, 0)                    
                }
                return AllocationInfo(descriptorSet: ds, descriptorPool: pool)
            }
        }
        if let pool = self.addNewPool(flags: 0) {
            if let ds = pool.allocateDescriptorSet(layout: layout) {
                return AllocationInfo(descriptorSet: ds, descriptorPool: pool)
            }
        }
        return nil
    }

    public func addNewPool(flags: VkDescriptorPoolCreateFlags) -> VulkanDescriptorPool? {
        self.maxSets = self.maxSets * 2 + 1
        var poolSizes: [VkDescriptorPoolSize] = []
        poolSizes.reserveCapacity(descriptorTypes.count)
        for i in 0..<descriptorTypes.count {
            if self.poolID.typeSize[i] > 0 {
                let type: VkDescriptorType = descriptorTypes[i]
                let poolSize = VkDescriptorPoolSize(type: type, descriptorCount: self.poolID.typeSize[i] * self.maxSets)
                poolSizes.append(poolSize)
            }
        }
        var poolCreateInfo = VkDescriptorPoolCreateInfo()
        poolCreateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
        poolCreateInfo.flags = flags
        poolCreateInfo.poolSizeCount = UInt32(poolSizes.count)
        poolCreateInfo.maxSets = self.maxSets

        var pool: VkDescriptorPool?
        let device = self.device!
        let result: VkResult = poolSizes.withUnsafeBufferPointer {
            poolCreateInfo.pPoolSizes = $0.baseAddress
            return vkCreateDescriptorPool(device.device, &poolCreateInfo, device.allocationCallbacks, &pool)
        }
        if result == VK_SUCCESS {
            assert(pool != nil)

            let dp = VulkanDescriptorPool(device: device, pool: pool!, poolCreateInfo: poolCreateInfo, poolID: poolID)
            self.descriptorPools.insert(dp, at: 0)
            return dp
        }
        Log.err("vkCreateDescriptorPool failed: \(result)")
        return nil
    }

    @discardableResult
    public func cleanup() -> Int {
        var activePools: [VulkanDescriptorPool] = []
        var inactivePools: [VulkanDescriptorPool] = []

        for pool in self.descriptorPools {
            if pool.numAllocatedSets > 0 {
                activePools.append(pool)
            } else {
                inactivePools.append(pool)
            }
        }
        if inactivePools.count > 0 && activePools.count > 0 {
            inactivePools.sort { $0.maxSets > $1.maxSets }
            // add first (biggest) pool for reuse.
            activePools.append(inactivePools[0])
        }
        self.descriptorPools = activePools
        return self.descriptorPools.count
    }
}
#endif //if ENABLE_VULKAN