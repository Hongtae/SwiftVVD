//
//  File: VulkanDescriptorPool.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

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

    public var hash: UInt32 {
        assert(self.typeSize.count == descriptorTypes.count)
        var data: [UInt32] = []
        data.reserveCapacity(self.typeSize.count + 1)
        data.append(self.mask)
        data.append(contentsOf: self.typeSize)
        return data.withUnsafeBytes { CRC32.hash(data: $0).hash }
    }

    public init() {
        self.mask = 0
        self.typeSize = .init(repeating: 0, count: descriptorTypes.count)
    }

    public init(poolSizes: [VkDescriptorPoolSize]) {
        var typeSize: [UInt32] = .init(repeating: 0, count: descriptorTypes.count)
        for ps in poolSizes {
            let index = index(of: ps.type)
            typeSize[index] += ps.descriptorCount
        }
        var mask: UInt32 = 0
        for (i, ts) in typeSize.enumerated() {
            if ts > 0 {
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
            typeSize[index] += UInt32(binding.arrayLength)
        }
        var mask: UInt32 = 0
        for (i, ts) in typeSize.enumerated() {
            if ts > 0 {
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
    public weak var device: VulkanGraphicsDevice?

    public var numAllocatedSets: UInt32

    private let lock = NSLock()

    public init(device: VulkanGraphicsDevice, pool: VkDescriptorPool, poolCreateInfo: VkDescriptorPoolCreateInfo, poolID: VulkanDescriptorPoolID) {
        self.device = device
        self.pool = pool
        self.poolID = poolID
        self.poolCreateFlags = poolCreateInfo.flags
        self.maxSets = poolCreateInfo.maxSets
        self.numAllocatedSets = 0
    }

    deinit {
        if let device = device {
            vkDestroyDescriptorPool(device.device, pool, device.allocationCallbacks)
        }
    }

    public func allocateDescriptorSet(layout: VkDescriptorSetLayout) -> VkDescriptorSet? {
        var allocateInfo = VkDescriptorSetAllocateInfo()
        allocateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
        allocateInfo.descriptorPool = self.pool
        allocateInfo.descriptorSetCount = 1

        let device = self.device!
        
        var descriptorSet: VkDescriptorSet? = nil
        let result: VkResult = withUnsafePointer(to: Optional(layout)) {
            allocateInfo.pSetLayouts = $0
            return synchronizedBy(locking: self.lock) {
                vkAllocateDescriptorSets(device.device, &allocateInfo, &descriptorSet)
            }
        }
        if result == VK_SUCCESS {
            numAllocatedSets += 1
        } else {
            // Log.err("vkAllocateDescriptorSets failed: \(result), pool: \(pool), used: \(numAllocatedSets)/\(maxSets)")
        }
        return descriptorSet
    }

    public func release(descriptorSets: [VkDescriptorSet]) {
        guard descriptorSets.isEmpty == false else { return }

        assert(self.numAllocatedSets > 0)
        assert(self.numAllocatedSets <= maxSets)

        let device = self.device!

        self.numAllocatedSets -= UInt32(descriptorSets.count)
        if self.numAllocatedSets == 0 {
            let result = synchronizedBy(locking: self.lock) {
                vkResetDescriptorPool(device.device, pool, 0)
            }
            if result != VK_SUCCESS {
                Log.err("vkResetDescriptorPool failed: \(result)")
            }
        } else if self.poolCreateFlags & UInt32(VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT.rawValue) != 0 {
            let optionalSets = descriptorSets.map{ Optional($0) }
            let result = optionalSets.withUnsafeBufferPointer { buffer in
                synchronizedBy(locking: self.lock) {
                    vkFreeDescriptorSets(device.device, self.pool, UInt32(buffer.count), buffer.baseAddress)
                }
            }
            assert(result == VK_SUCCESS)
            if result != VK_SUCCESS {
                Log.err("vkFreeDescriptorSets failed: \(result)")
            }
        }
    }
}

#endif //if ENABLE_VULKAN
