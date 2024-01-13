//
//  File: VulkanDescriptorPoolChain.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanDescriptorPoolChain {
    unowned let device: VulkanGraphicsDevice
    public let poolID: VulkanDescriptorPoolID
    
    public var maxSets: UInt32
    public var descriptorPools: [VulkanDescriptorPool]
    
    public struct AllocationInfo {
        public let descriptorSet: VkDescriptorSet
        public let descriptorPool: VulkanDescriptorPool
    }

    public init(device: VulkanGraphicsDevice, poolID: VulkanDescriptorPoolID) {
        self.device = device
        self.poolID = poolID
        self.maxSets = 2
        self.descriptorPools = []
    }

    public func allocateDescriptorSet(layout: VkDescriptorSetLayout) -> AllocationInfo? {
        for (i, pool) in self.descriptorPools.enumerated() {
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
        self.maxSets = max(self.maxSets, 1) * 2
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
        // Log.debug("VulkanDescriptorPoolChain: \(ObjectIdentifier(self)) \(poolID), maxSets: \(maxSets)")

        var pool: VkDescriptorPool?
        let result: VkResult = poolSizes.withUnsafeBufferPointer {
            poolCreateInfo.pPoolSizes = $0.baseAddress
            return vkCreateDescriptorPool(device.device, &poolCreateInfo, device.allocationCallbacks, &pool)
        }
        if result == VK_SUCCESS {
            assert(pool != nil)

            let dp = VulkanDescriptorPool(device: device, pool: pool!, poolCreateInfo: poolCreateInfo, poolID: poolID)
            self.descriptorPools.insert(dp, at: 0)
            // Log.debug("VulkanDescriptorPoolChain.\(#function): \(ObjectIdentifier(self)) \(poolID), pools: \(self.descriptorPools.count) maxSets: \(maxSets)")
            return dp
        }
        Log.err("vkCreateDescriptorPool failed: \(result)")
        return nil
    }

    @discardableResult
    public func cleanup() -> Int {
        var activePools: [VulkanDescriptorPool] = []
        var inactivePools: [VulkanDescriptorPool] = []

        activePools.reserveCapacity(self.descriptorPools.count)
        inactivePools.reserveCapacity(self.descriptorPools.count)

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
        // Log.debug("VulkanDescriptorPoolChain.\(#function): \(ObjectIdentifier(self)) \(poolID), pools: \(self.descriptorPools.count) maxSets: \(maxSets)")
        return self.descriptorPools.count
    }
}
#endif //if ENABLE_VULKAN
