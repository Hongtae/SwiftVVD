//
//  File: VulkanBufferView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanBufferView: GPUBuffer {
    let device: GraphicsDevice
    let bufferView: VkBufferView?
    let buffer: VulkanBuffer?

    init(buffer: VulkanBuffer) {
        self.device = buffer.device
        self.buffer = buffer
        self.bufferView = nil
    }

    init(buffer: VulkanBuffer, bufferView: VkBufferView) {
        self.device = buffer.device
        self.bufferView = bufferView
        self.buffer = buffer
    }

    init(device: VulkanGraphicsDevice, bufferView: VkBufferView) {
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

    func contents() -> UnsafeMutableRawPointer? {
        return self.buffer?.contents()
    }

    func flush() {
        self.buffer?.flush(offset: 0, size: UInt(VK_WHOLE_SIZE))
    }

    var length: Int { self.buffer?.length ?? 0 }
}

#endif //if ENABLE_VULKAN
