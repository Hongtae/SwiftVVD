//
//  File: VulkanBufferView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanBufferView: Buffer {
    public let device: GraphicsDevice
    public let bufferView: VkBufferView?
    public let buffer: VulkanBuffer?

    public init(buffer: VulkanBuffer) {
        self.device = buffer.device
        self.buffer = buffer
        self.bufferView = nil
    }

    public init(buffer: VulkanBuffer, bufferView: VkBufferView) {
        self.device = buffer.device
        self.bufferView = bufferView
        self.buffer = buffer
    }

    public init(device: VulkanGraphicsDevice, bufferView: VkBufferView) {
        self.device = device
        self.bufferView = bufferView
        self.buffer = nil
    }

    deinit {
        if let bufferView = bufferView {
            let device = self.device as! VulkanGraphicsDevice
            vkDestroyBufferView(device.device, bufferView, device.allocationCallbacks)
        }
    }

    public func contents() -> UnsafeMutableRawPointer? {
        return self.buffer!.contents()
    }

    public func flush() {
        self.buffer!.flush(offset: 0, size: UInt(VK_WHOLE_SIZE))
    }

    public var length: UInt { self.buffer!.length }
}

#endif //if ENABLE_VULKAN
