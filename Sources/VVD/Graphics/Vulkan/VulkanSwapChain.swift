//
//  File: VulkanSwapChain.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanSwapChain: SwapChain, @unchecked Sendable {

    let window: any Window
    let queue: VulkanCommandQueue

    var displaySyncEnabled: Bool = false {
        didSet {
            if oldValue != displaySyncEnabled {
                self.lock.withLock { self.deviceReset = true }
            }
        }
    }

    private var frameCount: UInt64  // incremented at each present 
    private var imageIndex: UInt32  // returned from vkAcquireNextImageKHR

    private var acquireFences: [VkFence]
    private var acquireSemaphores: [VkSemaphore]
    private var numberOfAcquireLocks: Int

    private var submitSemaphores: [VkSemaphore]
    private var imageViews: [VulkanImageView]
    private var numberOfSwapchainImages: Int
    private var offscreenImageView: VulkanImageView? = nil

    private var swapchain: VkSwapchainKHR?
    private var surface: VkSurfaceKHR?
    private var surfaceFormat = VkSurfaceFormatKHR()
    private var availableSurfaceFormats: [VkSurfaceFormatKHR] = []

    private let lock = NSLock()
    private var deviceReset = false
    private var surfaceReady = false
    private var validWindow = false
    private var cachedResolution: CGSize

    private var renderPassDescriptor: RenderPassDescriptor? = nil

    var commandQueue: CommandQueue { queue }

    @MainActor
    init?(queue: VulkanCommandQueue, window: any Window) {
        self.frameCount = 0
        self.imageIndex = 0
        self.acquireSemaphores = []
        self.acquireFences = []
        self.numberOfAcquireLocks = 0
        self.submitSemaphores = []
        self.numberOfSwapchainImages = 0
        self.imageViews = []

        self.queue = queue
        self.window = window
        self.cachedResolution = window.resolution
        self.validWindow = window.isValid

        window.addEventObserver(self) { [weak self](event: WindowEvent) in
            switch event.type {
                case .resized:
                if let self {
                    let resolution = self.window.resolution
                    self.lock.withLock {
                        self.cachedResolution = resolution
                        self.deviceReset = true
                    }
                }
                case .closed:
                if let self {
                    self.lock.withLock { self.validWindow = false }
                }
                case .shown, .activated:
                if let self {
                    self.lock.withLock {
                        if self.surfaceReady == false {
                            self.deviceReset = true
                        }
                    }
                }
                default:
                    break
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
        self.acquireFences.forEach {
            vkDestroyFence(device.device, $0, device.allocationCallbacks)
        }
        self.acquireSemaphores.forEach {
            vkDestroySemaphore(device.device, $0, device.allocationCallbacks)
        }
        self.submitSemaphores.forEach {
            vkDestroySemaphore(device.device, $0, device.allocationCallbacks)
        }
    }

    @MainActor
    func setup() -> Bool {
        let device = queue.device as! VulkanGraphicsDevice
        let instance = device.instance
        let physicalDevice = device.physicalDevice

        let queueFamilyIndex: UInt32 = self.queue.family.familyIndex

        if self.window.isValid == false {
            Log.err("VulkanSwapChain.setup() failed: invalid window.")
            return false
        }

        var err: VkResult = VK_SUCCESS

#if VK_USE_PLATFORM_WIN32_KHR
        var surfaceCreateInfo = VkWin32SurfaceCreateInfoKHR()
        surfaceCreateInfo.sType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR
        surfaceCreateInfo.hinstance = GetModuleHandleW(nil)
        surfaceCreateInfo.hwnd = (self.window as! Win32Window).hWnd

        err = instance.extensionProc.vkCreateWin32SurfaceKHR!(instance.instance, &surfaceCreateInfo, device.allocationCallbacks, &self.surface)
        if err != VK_SUCCESS {
            Log.err("vkCreateWin32SurfaceKHR failed: \(err)")
            return false
        }
#endif
#if VK_USE_PLATFORM_ANDROID_KHR
        var surfaceCreateInfo = VkAndroidSurfaceCreateInfoKHR()
        surfaceCreateInfo.sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR
        surfaceCreateInfo.window = (self.window as! AndroidWindow).nativeWindow // ANativeWindow *

        err = instance.extensionProc.vkCreateAndroidSurfaceKHR!(instance.instance, &surfaceCreateInfo, device.allocationCallbacks, &self.surface)
        if err != VK_SUCCESS {
            Log.err("vkCreateAndroidSurfaceKHR failed: \(err)")
            return false
        }
#endif
#if VK_USE_PLATFORM_WAYLAND_KHR
        var surfaceCreateInfo = VkWaylandSurfaceCreateInfoKHR()
        surfaceCreateInfo.sType = VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR
        surfaceCreateInfo.display = (self.window as! WaylandWindow).display
        surfaceCreateInfo.surface = (self.window as! WaylandWindow).surface

        err = instance.extensionProc.vkCreateWaylandSurfaceKHR!(instance.instance, &surfaceCreateInfo, device.allocationCallbacks, &self.surface)
        if err != VK_SUCCESS {
            Log.err("vkCreateWaylandSurfaceKHR failed: \(err)")
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
        // there is no preferred format, so we assume VK_FORMAT_B8G8R8A8_UNORM
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
        return self.updateDevice()
    }

    func updateDevice() -> Bool {
        let device = self.queue.device as! VulkanGraphicsDevice
        //let instance = device.instance
        let physicalDevice = device.physicalDevice

        let (resolution, surfaceFormat) = self.lock.withLock { 
            self.deviceReset = false
            self.surfaceReady = false
            return (self.cachedResolution, self.surfaceFormat)
        }
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

        if swapchainExtent.width == 0 || swapchainExtent.height == 0 {
            // surface is not visible, swapchain cannot be created until the size changes.
            Log.warning("Swapchain cannot be created with zero area (\(swapchainExtent.width) x \(swapchainExtent.height))");

            // create an off-screen render target as a fallback.
            let pixelFormat = PixelFormat.from(vkFormat: surfaceFormat.format)
            let imageView = device.makeTransientRenderTarget(type: .type2D,
                                                             pixelFormat: pixelFormat,
                                                             width: max(1, Int(width)),
                                                             height: max(1, Int(height)),
                                                             depth: 1)
            if let imageView {
                assert(imageView is VulkanImageView)
            }
            self.offscreenImageView = imageView as? VulkanImageView
            return false
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
        if self.displaySyncEnabled == false {
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
        var desiredNumberOfSwapchainImages: UInt32 = max(surfaceCaps.minImageCount, 2)
        if surfaceCaps.maxImageCount > 0 && desiredNumberOfSwapchainImages > surfaceCaps.maxImageCount {
            desiredNumberOfSwapchainImages = surfaceCaps.maxImageCount
        }

        // Find the transformation of the surface
        var preTransform = VkSurfaceTransformFlagBitsKHR(surfaceCaps.currentTransform.rawValue)
        if surfaceCaps.supportedTransforms & UInt32(VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR.rawValue) != 0 {
            // We prefer a non-rotated transform
            preTransform = VkSurfaceTransformFlagBitsKHR(VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR.rawValue)
        }

        var swapchainCreateInfo = VkSwapchainCreateInfoKHR()
        swapchainCreateInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
        swapchainCreateInfo.surface = self.surface
        swapchainCreateInfo.minImageCount = desiredNumberOfSwapchainImages
        swapchainCreateInfo.imageFormat = surfaceFormat.format
        swapchainCreateInfo.imageColorSpace = surfaceFormat.colorSpace
        swapchainCreateInfo.imageExtent = VkExtent2D(width: swapchainExtent.width, height: swapchainExtent.height)
        swapchainCreateInfo.imageUsage = UInt32(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue)
        swapchainCreateInfo.preTransform = preTransform
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
        vkGetPhysicalDeviceFormatProperties(physicalDevice.device, surfaceFormat.format, &formatProps)
        if formatProps.optimalTilingFeatures & UInt32(VK_FORMAT_FEATURE_BLIT_DST_BIT.rawValue) != 0 {
            swapchainCreateInfo.imageUsage |= UInt32(VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        }

        err = self.lock.withLock {
            vkCreateSwapchainKHR(device.device, &swapchainCreateInfo, device.allocationCallbacks, &self.swapchain)
        }
        if err != VK_SUCCESS {
            Log.err("vkCreateSwapchainKHR failed: \(err)")
            return false
        }

        let presentModeString = { (mode: VkPresentModeKHR) -> String in
            switch mode {
            case VK_PRESENT_MODE_IMMEDIATE_KHR:                 "VK_PRESENT_MODE_IMMEDIATE_KHR"
            case VK_PRESENT_MODE_MAILBOX_KHR:                   "VK_PRESENT_MODE_MAILBOX_KHR"
            case VK_PRESENT_MODE_FIFO_KHR:                      "VK_PRESENT_MODE_FIFO_KHR"
            case VK_PRESENT_MODE_FIFO_RELAXED_KHR:              "VK_PRESENT_MODE_FIFO_RELAXED_KHR"
            case VK_PRESENT_MODE_SHARED_DEMAND_REFRESH_KHR:     "VK_PRESENT_MODE_SHARED_DEMAND_REFRESH_KHR"
            case VK_PRESENT_MODE_SHARED_CONTINUOUS_REFRESH_KHR: "VK_PRESENT_MODE_SHARED_CONTINUOUS_REFRESH_KHR"
            default:
                "## UNKNOWN ##"
            }
        }
        Log.info("VkSwapchainKHR created. (\(swapchainExtent.width) x \(swapchainExtent.height), V-sync:\(self.displaySyncEnabled), \(presentModeString(swapchainPresentMode)))")

        // If an existing swap chain is re-created, destroy the old swap chain
        // This also cleans up all the presentable images
        if let swapchainOld = swapchainOld {
            self.lock.withLock {
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
            imageViewCreateInfo.format = surfaceFormat.format
            imageViewCreateInfo.components = VkComponentMapping(
                r: VK_COMPONENT_SWIZZLE_IDENTITY,
                g: VK_COMPONENT_SWIZZLE_IDENTITY,
                b: VK_COMPONENT_SWIZZLE_IDENTITY,
                a: VK_COMPONENT_SWIZZLE_IDENTITY)

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

            let swapchainImageView = VulkanImageView(device: device, imageView: imageView!)
            swapchainImageView.image = swapchainImage
            swapchainImageView.waitSemaphore = nil
            swapchainImageView.signalSemaphore = nil

            self.imageViews.append(swapchainImageView)
        }

        let resizeSemaphoreArray = { (semaphores: inout [VkSemaphore], count: Int) in
            while semaphores.count > count {
                let last = semaphores.removeLast()
                vkDestroySemaphore(device.device, last, device.allocationCallbacks)
            }
            while semaphores.count < count {
                // create binary semaphore
                var semaphoreCreateInfo = VkSemaphoreCreateInfo()
                semaphoreCreateInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
                var semaphore: VkSemaphore?
                let err = vkCreateSemaphore(device.device, &semaphoreCreateInfo, device.allocationCallbacks, &semaphore)
                if err != VK_SUCCESS {
                    Log.err("vkCreateSemaphore failed: \(err)")            
                    assertionFailure("vkCreateSemaphore failed: \(err)")            
                    return false
                }
                semaphores.append(semaphore!)
            }
            return semaphores.count == count
        }
        let resizeFenceArray = { (fences: inout [VkFence], count: Int, signaled: Bool) in
            while fences.count > count {
                let last = fences.removeLast()
                vkDestroyFence(device.device, last, device.allocationCallbacks)
            }
            while fences.count < count {
                // create fence
                var fenceCreateInfo = VkFenceCreateInfo()
                fenceCreateInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
                fenceCreateInfo.flags = signaled ? VkFenceCreateFlags(VK_FENCE_CREATE_SIGNALED_BIT.rawValue) : 0
                var fence: VkFence?
                let err = vkCreateFence(device.device, &fenceCreateInfo, device.allocationCallbacks, &fence)
                if err != VK_SUCCESS {
                    Log.err("vkCreateFence failed: \(err)")
                    assertionFailure("vkCreateFence failed: \(err)")
                    return false
                }
                fences.append(fence!)
            }
            return fences.count == count
        }

        let numAcquireLocks = max(swapchainImageCount, 3)

        if resizeFenceArray(&self.acquireFences, Int(numAcquireLocks), true) == false {
            return false
        }
        if resizeSemaphoreArray(&self.acquireSemaphores, Int(numAcquireLocks)) == false {
            return false
        }
        if resizeSemaphoreArray(&self.submitSemaphores, Int(swapchainImageCount)) == false {
            return false
        }

        self.imageIndex = 0
        self.frameCount = 0
        self.numberOfAcquireLocks = Int(numAcquireLocks)
        self.numberOfSwapchainImages = Int(swapchainImageCount)
        self.offscreenImageView = nil

        assert(self.numberOfAcquireLocks > 0)
        assert(self.acquireSemaphores.count == self.numberOfAcquireLocks)
        assert(self.acquireFences.count == self.numberOfAcquireLocks)

        assert(self.numberOfSwapchainImages > 0)
        assert(self.submitSemaphores.count == self.numberOfSwapchainImages)
        assert(self.imageViews.count == self.numberOfSwapchainImages)

        self.lock.withLock {
            self.surfaceReady = true
        }
        return true 
    }

    @inline(__always)
    private func updateDeviceIfNeeded() {
        let needUpdate = self.lock.withLock { self.deviceReset }
        if needUpdate {
            self.queue.waitIdle()

            if self.updateDevice() == false {
                Log.error("VulkanSwapChain.updateDevice() failed! (surfaceReady: \(self.surfaceReady))")
            }
        }
    }

    func setupFrame() {
        self.updateDeviceIfNeeded()

        let device = self.queue.device as! VulkanGraphicsDevice

        let acquireLockIndex = self.frameCount % UInt64(self.numberOfAcquireLocks)
        let waitSemaphore = self.acquireSemaphores[Int(acquireLockIndex)]
        let fence = self.acquireFences[Int(acquireLockIndex)]

        let frameReady = self.lock.withLock {
            if self.surfaceReady {
                let st = vkGetFenceStatus(device.device, fence)
                if st == VK_NOT_READY {
                    let start = DispatchTime.now()
                    vkWaitForFences(device.device, 1, [fence], VK_TRUE, UInt64.max)
                    let end = DispatchTime.now()
                    let elapsed = (end.uptimeNanoseconds - start.uptimeNanoseconds) / 1000
                    if elapsed > 100 {
                        Log.warning("VulkanSwapChain.setupFrame: vkWaitForFences took \(elapsed) μs.")
                    }
                } else if st != VK_SUCCESS {
                    Log.err("vkGetFenceStatus failed: \(st)")
                }
                vkResetFences(device.device, 1, [fence])
                let err = vkAcquireNextImageKHR(device.device, self.swapchain, UInt64.max, waitSemaphore, nil, &self.imageIndex)
                switch err {
                case VK_SUCCESS, VK_TIMEOUT, VK_NOT_READY ,VK_SUBOPTIMAL_KHR:
                    return true
                default:
                    Log.err("vkAcquireNextImageKHR failed: \(err)")
                }
            }
            return false
        }

        let renderTarget: VulkanImageView
        if frameReady {
            renderTarget = self.imageViews[Int(self.imageIndex)]
            renderTarget.waitSemaphore = waitSemaphore
            renderTarget.signalSemaphore = waitSemaphore
        } else {
            renderTarget = self.offscreenImageView!
        }

        let colorAttachment = RenderPassColorAttachmentDescriptor(
            renderTarget: renderTarget,
            loadAction: .clear,
            storeAction: .store,
            clearColor: Color(r: 0, g: 0, b: 0, a:0))

        self.renderPassDescriptor = RenderPassDescriptor(
            colorAttachments: [colorAttachment],
            depthStencilAttachment: RenderPassDepthStencilAttachmentDescriptor())
    }

    var pixelFormat: PixelFormat {
        get {
            self.lock.withLock {
                PixelFormat.from(vkFormat: self.surfaceFormat.format)
            }
        }
        set (value) {
            self.lock.withLock {
                let format = value.vkFormat()
                if format != self.surfaceFormat.format {
                    if value.isColorFormat {
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

    var maximumBufferCount: Int {
        self.lock.withLock {
            assert(self.imageViews.count == self.numberOfSwapchainImages)
            return self.numberOfSwapchainImages
        }
    }

    func currentRenderPassDescriptor() -> RenderPassDescriptor {
        if self.renderPassDescriptor == nil {
            self.setupFrame()
        }
        guard let renderPassDescriptor else {
            fatalError("VulkanSwapChain.currentRenderPassDescriptor() failed.")
        }
        assert(renderPassDescriptor.colorAttachments.isEmpty == false)
        return renderPassDescriptor
    }

    @discardableResult
    func present(waitEvents: [GPUEvent]) -> Bool {
        let (validWindow, surfaceReady) = self.lock.withLock {
            (self.validWindow, self.surfaceReady)
        }
        if validWindow == false {
            Log.err("VulkanSwapChain.present(waitEvents:) failed: invalid window.")
            return false
        }
        if surfaceReady == false {
            self.renderPassDescriptor = nil
            return false
        }

        let acquireLockIndex = self.frameCount % UInt64(self.numberOfAcquireLocks)
        let waitSemaphore = self.acquireSemaphores[Int(acquireLockIndex)]
        let fence = self.acquireFences[Int(acquireLockIndex)]

        let submitSemaphore = self.submitSemaphores[Int(self.imageIndex)]
        let presentSrc = self.imageViews[Int(self.imageIndex)]

        do {
            var waitSemaphoreInfo = VkSemaphoreSubmitInfo()
            waitSemaphoreInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO
            waitSemaphoreInfo.semaphore = waitSemaphore
            waitSemaphoreInfo.stageMask = VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT

            var signalSemaphoreInfo = VkSemaphoreSubmitInfo()
            signalSemaphoreInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO
            signalSemaphoreInfo.semaphore = submitSemaphore
            signalSemaphoreInfo.stageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT

            withUnsafePointer(to: &waitSemaphoreInfo) { waitSemaphoreInfo in
                withUnsafePointer(to: &signalSemaphoreInfo) { signalSemaphoreInfo in
                    var submitInfo = VkSubmitInfo2()
                    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO_2
                    submitInfo.waitSemaphoreInfoCount = 1
                    submitInfo.pWaitSemaphoreInfos = waitSemaphoreInfo
                    submitInfo.signalSemaphoreInfoCount = 1
                    submitInfo.pSignalSemaphoreInfos = signalSemaphoreInfo

                    let err = self.queue.withVkQueue { queue in
                        vkQueueSubmit2(queue, 1, &submitInfo, fence)
                    }
                    if err != VK_SUCCESS {
                        Log.err("vkQueueSubmit2 failed: \(err)")
                    }
                }
            }
        }

        if let buffer = self.queue.makeCommandBuffer() {
            if let encoder = buffer.makeCopyCommandEncoder() as? VulkanCopyCommandEncoder {
                encoder.callback { commandBuffer in
                    presentSrc.image?.setLayout(VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                                      discardOldLayout: false,
                                      accessMask: VK_ACCESS_2_NONE,
                                      stageBegin: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                                      stageEnd: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                                      queueFamilyIndex: self.queue.family.familyIndex,
                                      commandBuffer: commandBuffer)
                }
                encoder.waitSemaphore(submitSemaphore, value: 0, flags: VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT)
                encoder.signalSemaphore(submitSemaphore, value: 0, flags: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT)
                encoder.endEncoding()
                buffer.commit()
            }
        }

        var waitSemaphores = waitEvents.map { event in
            let s = event as! VulkanSemaphore
            // VUID-vkQueuePresentKHR-pWaitSemaphores-03267
            assert(s.isBinarySemaphore, "VulkanSwapChain.present(waitEvents:) The event of waitEvents must be a binary semaphore.")
            return Optional(s.semaphore)
        }
        waitSemaphores.append(submitSemaphore)
        
        let err: VkResult = withUnsafePointer(to: self.swapchain) {
            var presentInfo = VkPresentInfoKHR()
            presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR
            presentInfo.swapchainCount = 1
            presentInfo.pSwapchains = $0
            return withUnsafePointer(to: self.imageIndex) {
                presentInfo.pImageIndices = $0

                // Check if a wait semaphore has been specified to wait for before presenting the image
                if waitSemaphores.count > 0 {
                    return waitSemaphores.withUnsafeBufferPointer {
                        presentInfo.pWaitSemaphores = $0.baseAddress
                        presentInfo.waitSemaphoreCount = UInt32($0.count)

                        return self.queue.withVkQueue { queue in
                            vkQueuePresentKHR(queue, &presentInfo)
                        }
                    }
                } else {
                    presentInfo.pWaitSemaphores = nil
                    presentInfo.waitSemaphoreCount = 0

                    return self.queue.withVkQueue { queue in
                        vkQueuePresentKHR(queue, &presentInfo)
                    }
                }
            }
        }

        if err != VK_SUCCESS {
            Log.err("vkQueuePresentKHR failed: \(err)")
        }

        self.renderPassDescriptor = nil

        if err == VK_ERROR_OUT_OF_DATE_KHR {
            self.lock.withLock { self.deviceReset = true }
        }
        self.updateDeviceIfNeeded()

        self.frameCount = self.frameCount + 1

        return err == VK_SUCCESS
    }
}
#endif //if ENABLE_VULKAN
