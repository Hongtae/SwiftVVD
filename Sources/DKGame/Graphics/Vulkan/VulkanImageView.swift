#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanImageView: Texture {

    public let imageView: VkImageView
    
    public var waitSemaphore: VkSemaphore?
    public var signalSemaphore: VkSemaphore?

    public var image: VulkanImage?
    public let device: GraphicsDevice

    public init(image: VulkanImage, imageView: VkImageView, createInfo: VkImageViewCreateInfo) {
        self.image = image
        self.imageView = imageView
        self.device = image.device
    }

    public init(device: VulkanGraphicsDevice, imageView: VkImageView) {
        self.imageView = imageView
        self.device = device
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

    public var width: UInt32        { self.image!.width }
    public var height: UInt32       { self.image!.height }
    public var depth: UInt32        { self.image!.depth }
    public var mipmapCount: UInt32  { self.image!.mipmapCount }
    public var arrayLength: UInt32  { self.image!.arrayLength }

    public var type: TextureType    { self.image!.type }
    public var pixelFormat: PixelFormat { self.image!.pixelFormat }
}

#endif //if ENABLE_VULKAN
