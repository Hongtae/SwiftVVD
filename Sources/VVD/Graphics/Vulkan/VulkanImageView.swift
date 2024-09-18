//
//  File: VulkanImageView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanImageView: Texture {

    public let imageView: VkImageView
    
    public var waitSemaphore: VkSemaphore?
    public var signalSemaphore: VkSemaphore?

    public var image: VulkanImage?
    public let device: GraphicsDevice
    public let parent: Texture?

    public init(image: VulkanImage,
                imageView: VkImageView,
                parent: VulkanImageView? = nil) {
        self.image = image
        self.imageView = imageView
        self.device = image.device
        self.parent = parent
    }

    public init(device: VulkanGraphicsDevice, imageView: VkImageView) {
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

    public var width: Int       { self.image!.width }
    public var height: Int      { self.image!.height }
    public var depth: Int       { self.image!.depth }
    public var mipmapCount: Int { self.image!.mipmapCount }
    public var arrayLength: Int { self.image!.arrayLength }

    public var type: TextureType    { self.image!.type }
    public var pixelFormat: PixelFormat { self.image!.pixelFormat }

    public func makeTextureView(pixelFormat: PixelFormat) -> Texture? {
        self.image?.makeImageView(format: pixelFormat, parent: self)
    }
}

#endif //if ENABLE_VULKAN
