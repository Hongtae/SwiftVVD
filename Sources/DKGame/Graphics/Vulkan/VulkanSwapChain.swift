//
//  File: VulkanSwapChain.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanSwapChain: SwapChain {

    let window: Window
    let queue: VulkanCommandQueue
    let frameReadySemaphore: VkSemaphore

    var enableVSync = false
    var swapchain: VkSwapchainKHR?
    var surface: VkSurfaceKHR?
    var surfaceFormat = VkSurfaceFormatKHR()
    var availableSurfaceFormats: [VkSurfaceFormatKHR] = []

    var imageViews: [VulkanImageView] = []

    private let lock = NSLock()
    private var deviceReset = false

    private var frameIndex: UInt32 = 0
    private var renderPassDescriptor: RenderPassDescriptor

    public var commandQueue: CommandQueue { queue }

    @MainActor
    public init?(queue: VulkanCommandQueue, window: Window) {

        let device = queue.device as! VulkanGraphicsDevice
        var semaphoreCreateInfo = VkSemaphoreCreateInfo()
        semaphoreCreateInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
        var frameReadySemaphore: VkSemaphore?
        let err = vkCreateSemaphore(device.device, &semaphoreCreateInfo, device.allocationCallbacks, &frameReadySemaphore)
        if err != VK_SUCCESS {
            Log.err("vkCreateSemaphore failed: \(err)")            
            assertionFailure("vkCreateSemaphore failed: \(err)")            
            return nil
        }

        self.frameReadySemaphore = frameReadySemaphore!
        self.queue = queue
        self.window = window
        self.renderPassDescriptor = RenderPassDescriptor(
            colorAttachments: [],
            depthStencilAttachment: RenderPassDepthStencilAttachmentDescriptor())

        window.addEventObserver(self) { [weak self](event: WindowEvent) in
            if event.type == .resized {
                if let self = self {
                    synchronizedBy(locking: self.lock) { self.deviceReset = true }
                }
            }
        }
    }

    deinit {
        self.queue.waitIdle()

        let device = queue.device as! VulkanGraphicsDevice
        let instance = device.instance

        for imageView in self.imageViews {
            imageView.image!.image = nil
            imageView.image = nil
            imageView.waitSemaphore = nil
            imageView.signalSemaphore = nil
        }
        self.imageViews.removeAll()

        if let swapchain = self.swapchain {
            vkDestroySwapchainKHR(device.device, swapchain, device.allocationCallbacks)
        }
        if let surface = self.surface {
            vkDestroySurfaceKHR(instance.instance, surface, device.allocationCallbacks)          
        }
        vkDestroySemaphore(device.device, self.frameReadySemaphore, device.allocationCallbacks)
    }

    @MainActor
    func setup() -> Bool {
        let device = queue.device as! VulkanGraphicsDevice
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
            Log.err("vkCreateWin32SurfaceKHR failed: \(err)")
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
            Log.err("vkCreateAndroidSurfaceKHR failed: \(err)")
            return false
        }
#endif

        var surfaceSupported: VkBool32 = VkBool32(VK_FALSE)
        err = vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice.device, queueFamilyIndex, surface, &surfaceSupported)
        if err != VK_SUCCESS {
            Log.err("vkGetPhysicalDeviceSurfaceSupportKHR failed: \(err)")
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
            Log.err("vkGetPhysicalDeviceSurfaceFormatsKHR failed: \(err)")
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
            Log.err("vkGetPhysicalDeviceSurfaceFormatsKHR failed: \(err)")
            return false
        }

        // If the surface format list only includes one entry with VK_FORMAT_UNDEFINED,
        // there is no preferered format, so we assume VK_FORMAT_B8G8R8A8_UNORM
        if (surfaceFormatCount == 1) && (availableSurfaceFormats[0].format == VK_FORMAT_UNDEFINED) {
            self.surfaceFormat.format = VK_FORMAT_B8G8R8A8_UNORM
        } else {
            // Always select the first available color format
            // If you need a specific format (e.g. SRGB) you'd need to
            // iterate over the list of available surface format and
            // check for it's presence
            self.surfaceFormat.format = availableSurfaceFormats[0].format
        }
        self.surfaceFormat.colorSpace = availableSurfaceFormats[0].colorSpace

        // create swapchain
        return self.update()
    }

    @MainActor
    @discardableResult
    func update() -> Bool {
        let device = self.queue.device as! VulkanGraphicsDevice
        //let instance = device.instance
        let physicalDevice = device.physicalDevice

        let resolution = self.window.resolution
        var width = UInt32(resolution.width.rounded())
        var height = UInt32(resolution.height.rounded())

        var err: VkResult = VK_SUCCESS
        let swapchainOld = self.swapchain

        // Get physical device surface properties and formats
        var surfaceCaps = VkSurfaceCapabilitiesKHR()
        err = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice.device, self.surface, &surfaceCaps)
        if err != VK_SUCCESS {
            Log.err("vkGetPhysicalDeviceSurfaceCapabilitiesKHR failed: \(err)")
            return false
        }

        // Get available present modes
        var presentModeCount: UInt32 = 0
        err = vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice.device, self.surface, &presentModeCount, nil)
        if err != VK_SUCCESS {
            Log.err("vkGetPhysicalDeviceSurfacePresentModesKHR failed: \(err)")
            return false
        }
        if presentModeCount == 0 {
            Log.err("vkGetPhysicalDeviceSurfacePresentModesKHR returns 0 present mode count")
            return false
        }

        var presentModes: [VkPresentModeKHR] = .init(repeating: VkPresentModeKHR(rawValue: 0), count: Int(presentModeCount))
        err = vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice.device, self.surface, &presentModeCount, &presentModes)
        if err != VK_SUCCESS {
            Log.err("vkGetPhysicalDeviceSurfacePresentModesKHR failed: \(err)")
            return false
        }

        var swapchainExtent = VkExtent2D()
        // If width (and height) equals the special value 0xFFFFFFFF, the size of the surface will be set by the swapchain
        if surfaceCaps.currentExtent.width == 0xFFFFFFFF {
            // If the surface size is undefined, the size is set to
            // the size of the images requested.
            swapchainExtent.width = width
            swapchainExtent.height = height
        } else {
            // If the surface size is defined, the swap chain size must match
            swapchainExtent = surfaceCaps.currentExtent
            width = surfaceCaps.currentExtent.width
            height = surfaceCaps.currentExtent.height
        }

        // Select a present mode for the swapchain
        // VK_PRESENT_MODE_IMMEDIATE_KHR
        // VK_PRESENT_MODE_MAILBOX_KHR
        // VK_PRESENT_MODE_FIFO_KHR
        // VK_PRESENT_MODE_FIFO_RELAXED_KHR

        // The VK_PRESENT_MODE_FIFO_KHR mode must always be present as per spec
        // This mode waits for the vertical blank ("v-sync")
        var swapchainPresentMode: VkPresentModeKHR = VK_PRESENT_MODE_FIFO_KHR

        // If v-sync is not requested, try to find a mailbox mode
        // It's the lowest latency non-tearing present mode available
        if self.enableVSync == false {
            for i in 0 ..< Int(presentModeCount) {
                if presentModes[i] == VK_PRESENT_MODE_MAILBOX_KHR {
                    swapchainPresentMode = VK_PRESENT_MODE_MAILBOX_KHR
                    break
                }
                if swapchainPresentMode != VK_PRESENT_MODE_MAILBOX_KHR && presentModes[i] == VK_PRESENT_MODE_IMMEDIATE_KHR {
                    swapchainPresentMode = VK_PRESENT_MODE_IMMEDIATE_KHR
                }
            }
        }

        // Determine the number of images
        var desiredNumberOfSwapchainImages: UInt32 = surfaceCaps.minImageCount + 1
        if surfaceCaps.maxImageCount > 0 && desiredNumberOfSwapchainImages > surfaceCaps.maxImageCount {
            desiredNumberOfSwapchainImages = surfaceCaps.maxImageCount
        }

        // Find the transformation of the surface
        var preTransform = VkSurfaceTransformFlagsKHR(surfaceCaps.currentTransform.rawValue)
        if surfaceCaps.supportedTransforms & UInt32(VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR.rawValue) != 0 {
            // We prefer a non-rotated transform
            preTransform = VkSurfaceTransformFlagsKHR(VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR.rawValue)
        }

        var swapchainCreateInfo = VkSwapchainCreateInfoKHR()
        swapchainCreateInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
        swapchainCreateInfo.surface = self.surface
        swapchainCreateInfo.minImageCount = desiredNumberOfSwapchainImages
        swapchainCreateInfo.imageFormat = self.surfaceFormat.format
        swapchainCreateInfo.imageColorSpace = self.surfaceFormat.colorSpace
        swapchainCreateInfo.imageExtent = VkExtent2D(width: swapchainExtent.width, height: swapchainExtent.height)
        swapchainCreateInfo.imageUsage = UInt32(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue)
        swapchainCreateInfo.preTransform = VkSurfaceTransformFlagBitsKHR(Int32(preTransform))
        swapchainCreateInfo.imageArrayLayers = 1
        swapchainCreateInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE
        swapchainCreateInfo.queueFamilyIndexCount = 0
        swapchainCreateInfo.pQueueFamilyIndices = nil
        swapchainCreateInfo.presentMode = swapchainPresentMode
        swapchainCreateInfo.oldSwapchain = swapchainOld
        // Setting clipped to VK_TRUE allows the implementation to discard rendering outside of the surface area
        swapchainCreateInfo.clipped = VkBool32(VK_TRUE)
        swapchainCreateInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR

        // Set additional usage flag for blitting from the swapchain images if supported
        var formatProps = VkFormatProperties()
        vkGetPhysicalDeviceFormatProperties(physicalDevice.device, self.surfaceFormat.format, &formatProps)
        if formatProps.optimalTilingFeatures & UInt32(VK_FORMAT_FEATURE_BLIT_DST_BIT.rawValue) != 0 {
            swapchainCreateInfo.imageUsage |= UInt32(VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        }

        err = synchronizedBy(locking: self.lock) {
            vkCreateSwapchainKHR(device.device, &swapchainCreateInfo, device.allocationCallbacks, &self.swapchain)
        }
        if err != VK_SUCCESS {
            Log.err("vkCreateSwapchainKHR failed: \(err)")
            return false
        }

        let presentModeString = { (mode: VkPresentModeKHR) -> String in
            switch (mode)
            {
            case VK_PRESENT_MODE_IMMEDIATE_KHR: return "VK_PRESENT_MODE_IMMEDIATE_KHR"
            case VK_PRESENT_MODE_MAILBOX_KHR:   return "VK_PRESENT_MODE_MAILBOX_KHR"
            case VK_PRESENT_MODE_FIFO_KHR:      return "VK_PRESENT_MODE_FIFO_KHR"
            case VK_PRESENT_MODE_FIFO_RELAXED_KHR:  return "VK_PRESENT_MODE_FIFO_RELAXED_KHR"
            case VK_PRESENT_MODE_SHARED_DEMAND_REFRESH_KHR: return "VK_PRESENT_MODE_SHARED_DEMAND_REFRESH_KHR"
            case VK_PRESENT_MODE_SHARED_CONTINUOUS_REFRESH_KHR: return "VK_PRESENT_MODE_SHARED_CONTINUOUS_REFRESH_KHR"
            default: break
            }
            return "## UNKNOWN ##"
        }
        Log.info("VkSwapchainKHR created. (\(swapchainExtent.width) x \(swapchainExtent.height), V-sync:\(self.enableVSync), \(presentModeString(swapchainPresentMode)))")

        // If an existing swap chain is re-created, destroy the old swap chain
        // This also cleans up all the presentable images
        if let swapchainOld = swapchainOld {
            synchronizedBy(locking: self.lock) {
                vkDestroySwapchainKHR(device.device, swapchainOld, device.allocationCallbacks)
            }
        }

        for imageView in self.imageViews {
            imageView.image!.image = nil
            imageView.image = nil
            imageView.waitSemaphore = nil
            imageView.signalSemaphore = nil
        }
        self.imageViews.removeAll()

        var swapchainImageCount: UInt32 = 0
        err = vkGetSwapchainImagesKHR(device.device, self.swapchain, &swapchainImageCount, nil)
        if err != VK_SUCCESS {
            Log.err("vkGetSwapchainImagesKHR failed: \(err)")
            return false
        }

        // Get the swap chain images
        var swapchainImages: [VkImage?] = .init(repeating: nil, count: Int(swapchainImageCount))
        err = vkGetSwapchainImagesKHR(device.device, self.swapchain, &swapchainImageCount, &swapchainImages)
        if err != VK_SUCCESS {
            Log.err("vkGetSwapchainImagesKHR failed: \(err)")
            return false
        }

        // Get the swap chain buffers containing the image and imageview
        self.imageViews.reserveCapacity(swapchainImages.count)
        for image in swapchainImages {
            var imageViewCreateInfo = VkImageViewCreateInfo()
            imageViewCreateInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
            imageViewCreateInfo.format = self.surfaceFormat.format
            imageViewCreateInfo.components = VkComponentMapping(
                r: VK_COMPONENT_SWIZZLE_R,
                g: VK_COMPONENT_SWIZZLE_G,
                b: VK_COMPONENT_SWIZZLE_B,
                a: VK_COMPONENT_SWIZZLE_A)

            imageViewCreateInfo.subresourceRange.aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
            imageViewCreateInfo.subresourceRange.baseMipLevel = 0
            imageViewCreateInfo.subresourceRange.levelCount = 1
            imageViewCreateInfo.subresourceRange.baseArrayLayer = 0
            imageViewCreateInfo.subresourceRange.layerCount = 1
            imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
            imageViewCreateInfo.flags = 0
            imageViewCreateInfo.image = image

            var imageView: VkImageView? = nil
            err = vkCreateImageView(device.device, &imageViewCreateInfo, device.allocationCallbacks, &imageView)
            if err != VK_SUCCESS {
                Log.err("vkCreateImageView failed: \(err)")
                return false
            }

            let swapchainImage = VulkanImage(device: device, image: image!)
            swapchainImage.imageType = VK_IMAGE_TYPE_2D
            swapchainImage.format = swapchainCreateInfo.imageFormat
            swapchainImage.extent = VkExtent3D(width: swapchainExtent.width, height: swapchainExtent.height, depth: 1 )
            swapchainImage.mipLevels = 1
            swapchainImage.arrayLayers = swapchainCreateInfo.imageArrayLayers
            swapchainImage.usage = swapchainCreateInfo.imageUsage
            swapchainImage.setLayout(VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                                     accessMask: 0,
                                     stageBegin: UInt32(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT.rawValue),
                                     stageEnd: UInt32(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT.rawValue))

            let swapchainImageView = VulkanImageView(device: device, imageView: imageView!)
            swapchainImageView.image = swapchainImage
            swapchainImageView.waitSemaphore = frameReadySemaphore
            swapchainImageView.signalSemaphore = frameReadySemaphore

            self.imageViews.append(swapchainImageView)
        }
        return true 
    }

    func setupFrame() async {
        let device = self.queue.device as! VulkanGraphicsDevice

        let resetSwapchain = synchronizedBy(locking: self.lock) { self.deviceReset }
        if resetSwapchain {
            vkDeviceWaitIdle(device.device)
            synchronizedBy(locking: self.lock) { self.deviceReset = false }
            await self.update()
        }

        let result = synchronizedBy(locking: self.lock) {
            vkAcquireNextImageKHR(device.device, self.swapchain, UInt64.max, self.frameReadySemaphore, nil, &self.frameIndex)
        }
        switch result {
        case VK_SUCCESS, VK_TIMEOUT, VK_NOT_READY ,VK_SUBOPTIMAL_KHR:
            break
        default:
            Log.err("vkAcquireNextImageKHR failed: \(result)")
        }

        let colorAttachment = RenderPassColorAttachmentDescriptor(
            renderTarget: self.imageViews[Int(self.frameIndex)],
            loadAction: .clear,
            storeAction: .store,
            clearColor: Color(r: 0, g: 0, b: 0, a:0))

        self.renderPassDescriptor.colorAttachments.removeAll()
        self.renderPassDescriptor.colorAttachments.append(colorAttachment)
    }

    public var pixelFormat: PixelFormat {
        get {
            synchronizedBy(locking: self.lock) {
                PixelFormat.from(vkFormat: self.surfaceFormat.format)
            }
        }
        set (value) {
            synchronizedBy(locking: self.lock) {
                let format = value.vkFormat()
                if format != self.surfaceFormat.format {
                    if value.isColorFormat() {
                        var formatChanged = false
                        if self.availableSurfaceFormats.count == 1 &&
                           self.availableSurfaceFormats[0].format == VK_FORMAT_UNDEFINED {
                            formatChanged = true
                            self.surfaceFormat.format = format
                            self.surfaceFormat.colorSpace = self.availableSurfaceFormats[0].colorSpace       
                        } else {
                            for fmt in self.availableSurfaceFormats {
                                if fmt.format == format {
                                    formatChanged = true
                                    self.surfaceFormat = fmt
                                    break
                                }
                            }
                        }
                        if formatChanged {
                            self.deviceReset = true
                            Log.info("SwapChain.pixelFormat value changed!")
                        } else {
                            Log.err("Failed to set SwapChain.pixelFormat property: not supported format")
                        }
                    } else {
                        Log.err("Failed to set SwapChain.pixelFormat property: invalid format")
                    }
                }
            }            
        }
    }

    public var maximumBufferCount: Int {
        synchronizedBy(locking: self.lock) { self.imageViews.count }
    }

    public func currentRenderPassDescriptor() async -> RenderPassDescriptor {
        if self.renderPassDescriptor.colorAttachments.count == 0 {
            await self.setupFrame()
        }
        return self.renderPassDescriptor
    }

    @discardableResult
    public func present(waitEvents: [Event]) -> Bool {
        var waitSemaphores: [VkSemaphore?] = []
        waitSemaphores.reserveCapacity(waitEvents.count + 1)

        for event in waitEvents {
            let s = event as! VulkanSemaphore
            waitSemaphores.append(s.semaphore)
        }
        waitSemaphores.append(self.frameReadySemaphore)

        var presentInfo = VkPresentInfoKHR()
        presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR
        presentInfo.swapchainCount = 1

        let err: VkResult = withUnsafePointer(to: self.swapchain) {
            presentInfo.pSwapchains = $0
            return withUnsafePointer(to: self.frameIndex) {
                presentInfo.pImageIndices = $0

                // Check if a wait semaphore has been specified to wait for before presenting the image
                if waitSemaphores.count > 0 {
                    return waitSemaphores.withUnsafeBufferPointer {
                        presentInfo.pWaitSemaphores = $0.baseAddress
                        presentInfo.waitSemaphoreCount = UInt32($0.count)

                        return vkQueuePresentKHR(self.queue.queue, &presentInfo)
                    }
                } else {
                    presentInfo.pWaitSemaphores = nil
                    presentInfo.waitSemaphoreCount = 0
                    return vkQueuePresentKHR(self.queue.queue, &presentInfo)
                }
            }
        }

        if err != VK_SUCCESS {
            Log.err("vkQueuePresentKHR failed: \(err)")
        }

        renderPassDescriptor.colorAttachments.removeAll(keepingCapacity: true)
        return err == VK_SUCCESS
    }
}

#endif //if ENABLE_VULKAN