//
//  File: VulkanBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanBuffer {
    public var buffer: VkBuffer
    public var usage: VkBufferUsageFlags
    public var sharingMode: VkSharingMode
    public var size: VkDeviceSize

    let memory: VulkanMemoryBlock?
    public let device: GraphicsDevice

    public init(device: VulkanGraphicsDevice, memory: VulkanMemoryBlock, buffer: VkBuffer, bufferCreateInfo: VkBufferCreateInfo) {
        self.device = device
        self.memory = memory
        self.buffer = buffer
        self.usage = bufferCreateInfo.usage
        self.sharingMode = bufferCreateInfo.sharingMode
        self.size = bufferCreateInfo.size

        assert(self.memory!.size >= self.size)
    }

    public init(device: VulkanGraphicsDevice, buffer: VkBuffer, size: VkDeviceSize) {
        self.device = device
        self.memory = nil
        self.buffer = buffer
        self.usage = 0
        self.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        self.size = size

        assert(self.size > 0)
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroyBuffer(device.device, buffer, device.allocationCallbacks)
        if var memory = self.memory {
            memory.chunk!.pool.dealloc(&memory)
        }
    }

    public var length: Int { Int(self.size) }

    public func contents() -> UnsafeMutableRawPointer? {
        if let memory = self.memory {
            assert(memory.chunk != nil)
            if let mapped = memory.chunk!.mapped {
                return mapped + Int(memory.offset)
            }
        }
        return nil
    }

    public func flush(offset: UInt, size: UInt) {
        if let memory = self.memory {
            assert(memory.chunk != nil)
            if (offset < memory.size) {
                let s = min(memory.size - UInt64(offset), UInt64(size))
                memory.chunk!.flush(offset: memory.offset + UInt64(offset), size: s)
            }
        }
    }

    public func makeBufferView(pixelFormat: PixelFormat, offset: UInt, range: UInt) -> VulkanBufferView? {
        if self.usage & UInt32(VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT.rawValue) != 0 ||
           self.usage & UInt32(VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT.rawValue) != 0 {

            let format = pixelFormat.vkFormat()
            if format != VK_FORMAT_UNDEFINED {
                let device = self.device as! VulkanGraphicsDevice
                let alignment = device.properties.limits.minTexelBufferOffsetAlignment

                assert(offset & UInt(alignment) == 0)

                var bufferViewCreateInfo = VkBufferViewCreateInfo()
                bufferViewCreateInfo.sType = VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO
                bufferViewCreateInfo.buffer = buffer
                bufferViewCreateInfo.format = format
                bufferViewCreateInfo.offset = VkDeviceSize(offset)
                bufferViewCreateInfo.range = VkDeviceSize(range)

                var bufferView: VkBufferView? = nil
                let result = vkCreateBufferView(device.device, &bufferViewCreateInfo, device.allocationCallbacks, &bufferView)
                if result == VK_SUCCESS {
                    return VulkanBufferView(buffer: self, bufferView: bufferView!)
                } else {
                    Log.err("vkCreateBufferView failed: \(result)")
                }
            } else {
                Log.err("VulkanBuffer::makeBufferView failed: Invalid pixel format!")
            }
        } else {
            Log.err("VulkanBuffer::makeBufferView failed: Invalid buffer object (Not intended for texel buffer creation)")
        }
        return nil
    }
}

#endif //if ENABLE_VULKAN
