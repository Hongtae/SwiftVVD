#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanSwapChain: SwapChain {
    public var pixelFormat: PixelFormat = .invalid
    public var maximumBufferCount: UInt64 = 0

    let window: Window
    let queue: VulkanCommandQueue
    let frameReadySemaphore: VkSemaphore

    var swapchain: VkSwapchainKHR?
    var surface: VkSurfaceKHR?
    var enableVSync = false

    var availableSurfaceFormats: [VkSurfaceFormatKHR] = []

    private let lock = SpinLock()
    private var deviceReset = false

    public init?(queue: VulkanCommandQueue, window: Window) {

        let device = queue.device as! VulkanGraphicsDevice
        var semaphoreCreateInfo = VkSemaphoreCreateInfo()
        semaphoreCreateInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
        var frameReadySemaphore: VkSemaphore?
        let err = vkCreateSemaphore(device.device, &semaphoreCreateInfo, device.allocationCallbacks, &frameReadySemaphore)
        if err != VK_SUCCESS {
#if DEBUG
            fatalError("vkCreateSemaphore failed: \(err.rawValue)")            
#else
            Log.err("vkCreateSemaphore failed: \(err.rawValue)")            
#endif
            return nil
        }

        self.frameReadySemaphore = frameReadySemaphore!
        self.queue = queue
        self.window = window

        window.addEventObserver(self) { (event: WindowEvent) in
            if event.type == .resized {
                synchronizedBy(locking: self.lock) { self.deviceReset = true }
            }
        }
    }

    deinit {
        self.window.removeEventObserver(self)

        _ = self.queue.waitIdle()
        let device = queue.device as! VulkanGraphicsDevice
        let instance = device.instance

        if let swapchain = self.swapchain {
    		vkDestroySwapchainKHR(device.device, swapchain, device.allocationCallbacks);
        }
        if let surface = self.surface {
    		vkDestroySurfaceKHR(instance.instance, surface, device.allocationCallbacks);            
        }
    	vkDestroySemaphore(device.device, self.frameReadySemaphore, device.allocationCallbacks);
    }

    public func setup() -> Bool {
        let device = self.queue.device as! VulkanGraphicsDevice
        let instance = device.instance
        let physicalDevice = device.physicalDevice

        let queueFamilyIndex: UInt32 = self.queue.family.familyIndex

        var err: VkResult = VK_SUCCESS

#if VK_USE_PLATFORM_WIN32_KHR
        var surfaceCreateInfo = VkWin32SurfaceCreateInfoKHR()
        surfaceCreateInfo.sType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR
        surfaceCreateInfo.hinstance = GetModuleHandleW(nil)
        surfaceCreateInfo.hwnd = (self.window as! Win32Window).hWnd

        err = instance.extensionProc.vkCreateWin32SurfaceKHR!(instance.instance, &surfaceCreateInfo, device.allocationCallbacks, &self.surface)
        if (err != VK_SUCCESS)
        {
            Log.err("vkCreateWin32SurfaceKHR failed: \(err.rawValue)")
            return false
        }
#endif
#if VK_USE_PLATFORM_ANDROID_KHR
        var surfaceCreateInfo = VkAndroidSurfaceCreateInfoKHR()
        surfaceCreateInfo.sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR
        surfaceCreateInfo.window = (self.window as! AndroidWindow).nativeWindow // ANativeWindow *

        err = instance.extensionProc.vkCreateAndroidSurfaceKHR!(instance.instance, &surfaceCreateInfo, device.allocationCallbacks, &self.surface)
        if (err != VK_SUCCESS)
        {
            Log.err("vkCreateAndroidSurfaceKHR failed: \(err.rawValue)")
            return false
        }
#endif

        var surfaceSupported: VkBool32 = VkBool32(VK_FALSE)
        err = vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice.device, queueFamilyIndex, surface, &surfaceSupported);
        if err != VK_SUCCESS {
            Log.err("vkGetPhysicalDeviceSurfaceSupportKHR failed: \(err.rawValue)")
            return false
        }
        if surfaceSupported == VkBool32(VK_FALSE) {
            Log.err("VkSurfaceKHR not support with QueueFamily at index: \(queueFamilyIndex)")
            return false
        }

        // get color format, color space
        // Get list of supported surface formats
        var surfaceFormatCount: UInt32 = 0
        err = vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice.device, surface, &surfaceFormatCount, nil)
        if err != VK_SUCCESS {
            Log.err("vkGetPhysicalDeviceSurfaceFormatsKHR failed: \(err.rawValue)")
            return false
        }
        if (surfaceFormatCount == 0)
        {
            Log.err("vkGetPhysicalDeviceSurfaceFormatsKHR returns 0 surface format count")
            return false
        }

        self.availableSurfaceFormats = .init(repeating: VkSurfaceFormatKHR(), count: Int(surfaceFormatCount))
    	err = vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice.device, surface, &surfaceFormatCount, &availableSurfaceFormats)
        if err != VK_SUCCESS {
            Log.err("vkGetPhysicalDeviceSurfaceFormatsKHR failed: \(err.rawValue)")
            return false;
        }

        return false
    }

    public func currentRenderPassDescriptor() -> RenderPassDescriptor {
        let depthStencilAttachment = RenderPassDepthStencilAttachmentDescriptor()
        return RenderPassDescriptor(colorAttachments:[], depthStencilAttachment: depthStencilAttachment)
    }

    public func present(waitEvents: [Event]) -> Bool { false }
}

#endif //if ENABLE_VULKAN