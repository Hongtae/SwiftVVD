//
//  File: VulkanImageView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanImageView: Texture {

    let imageView: VkImageView
    var waitSemaphore: VkSemaphore?
    var signalSemaphore: VkSemaphore?
    var image: VulkanImage?

    let device: GraphicsDevice
    let parent: Texture?

    init(image: VulkanImage, imageView: VkImageView, parent: VulkanImageView? = nil) {
        self.image = image
        self.imageView = imageView
        self.device = image.device
        self.parent = parent
    }

    init(device: VulkanGraphicsDevice, imageView: VkImageView) {
        self.imageView = imageView
        self.device = device
        self.parent = nil
    }

    deinit {
        let device = device as! VulkanGraphicsDevice

        vkDestroyImageView(device.device, imageView, device.allocationCallbacks)
        if let signalSemaphore = self.signalSemaphore {
            vkDestroySemaphore(device.device, signalSemaphore, device.allocationCallbacks)
        }
        if let waitSemaphore = self.waitSemaphore {
            vkDestroySemaphore(device.device, waitSemaphore, device.allocationCallbacks)
        }
    }

    var width: Int       { self.image!.width }
    var height: Int      { self.image!.height }
    var depth: Int       { self.image!.depth }
    var mipmapCount: Int { self.image!.mipmapCount }
    var arrayLength: Int { self.image!.arrayLength }
    var sampleCount: Int { self.image!.sampleCount }

    var type: TextureType    { self.image!.type }
    var pixelFormat: PixelFormat { self.image!.pixelFormat }

    var isTransient: Bool { self.image!.isTransient }

    func makeTextureView(pixelFormat: PixelFormat) -> Texture? {
        self.image?.makeImageView(format: pixelFormat, parent: self)
    }
}
#endif //if ENABLE_VULKAN
