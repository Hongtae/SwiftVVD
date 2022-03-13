#if ENABLE_VULKAN
import Vulkan
import Foundation

public struct VulkanInstanceExtensions {
    // VK_EXT_debug_utils
    var vkSetDebugUtilsObjectNameEXT: PFN_vkSetDebugUtilsObjectNameEXT?
    var vkSetDebugUtilsObjectTagEXT: PFN_vkSetDebugUtilsObjectTagEXT?
    var vkQueueBeginDebugUtilsLabelEXT: PFN_vkQueueBeginDebugUtilsLabelEXT?
    var vkQueueEndDebugUtilsLabelEXT: PFN_vkQueueEndDebugUtilsLabelEXT?
    var vkQueueInsertDebugUtilsLabelEXT: PFN_vkQueueInsertDebugUtilsLabelEXT?
    var vkCmdBeginDebugUtilsLabelEXT: PFN_vkCmdBeginDebugUtilsLabelEXT?
    var vkCmdEndDebugUtilsLabelEXT: PFN_vkCmdEndDebugUtilsLabelEXT?
    var vkCmdInsertDebugUtilsLabelEXT: PFN_vkCmdInsertDebugUtilsLabelEXT?
    var vkCreateDebugUtilsMessengerEXT: PFN_vkCreateDebugUtilsMessengerEXT?
    var vkDestroyDebugUtilsMessengerEXT: PFN_vkDestroyDebugUtilsMessengerEXT?
    var vkSubmitDebugUtilsMessageEXT: PFN_vkSubmitDebugUtilsMessageEXT?

    // VK_KHR_surface
    var vkGetPhysicalDeviceSurfaceSupportKHR: PFN_vkGetPhysicalDeviceSurfaceSupportKHR?
    var vkGetPhysicalDeviceSurfaceCapabilitiesKHR: PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR?
    var vkGetPhysicalDeviceSurfaceFormatsKHR: PFN_vkGetPhysicalDeviceSurfaceFormatsKHR?
    var vkGetPhysicalDeviceSurfacePresentModesKHR: PFN_vkGetPhysicalDeviceSurfacePresentModesKHR?


#if VK_USE_PLATFORM_WAYLAND_KHR
    // VK_KHR_wayland_surface
    var vkCreateWaylandSurfaceKHR: PFN_vkCreateWaylandSurfaceKHR?
    var vkGetPhysicalDeviceWaylandPresentationSupportKHR: PFN_vkGetPhysicalDeviceWaylandPresentationSupportKHR?
#endif
#if VK_USE_PLATFORM_ANDROID_KHR
    // VK_KHR_android_surface
    var vkCreateAndroidSurfaceKHR: PFN_vkCreateAndroidSurfaceKHR?
#endif
#if VK_USE_PLATFORM_WIN32_KHR
    // VK_KHR_win32_surface
    var vkCreateWin32SurfaceKHR: PFN_vkCreateWin32SurfaceKHR?
    var vkGetPhysicalDeviceWin32PresentationSupportKHR: PFN_vkGetPhysicalDeviceWin32PresentationSupportKHR?
#endif

    mutating func load(instance: VkInstance) {
        // VK_EXT_debug_utils
        self.vkSetDebugUtilsObjectNameEXT = loadInstanceProc(instance, "vkSetDebugUtilsObjectNameEXT", to: PFN_vkSetDebugUtilsObjectNameEXT.self)
        self.vkSetDebugUtilsObjectTagEXT = loadInstanceProc(instance, "vkSetDebugUtilsObjectTagEXT", to: PFN_vkSetDebugUtilsObjectTagEXT.self)
        self.vkQueueBeginDebugUtilsLabelEXT = loadInstanceProc(instance, "vkQueueBeginDebugUtilsLabelEXT", to: PFN_vkQueueBeginDebugUtilsLabelEXT.self)
        self.vkQueueEndDebugUtilsLabelEXT = loadInstanceProc(instance, "vkQueueEndDebugUtilsLabelEXT", to: PFN_vkQueueEndDebugUtilsLabelEXT.self)
        self.vkQueueInsertDebugUtilsLabelEXT = loadInstanceProc(instance, "vkQueueInsertDebugUtilsLabelEXT", to: PFN_vkQueueInsertDebugUtilsLabelEXT.self)
        self.vkCmdBeginDebugUtilsLabelEXT = loadInstanceProc(instance, "vkCmdBeginDebugUtilsLabelEXT", to: PFN_vkCmdBeginDebugUtilsLabelEXT.self)
        self.vkCmdEndDebugUtilsLabelEXT = loadInstanceProc(instance, "vkCmdEndDebugUtilsLabelEXT", to: PFN_vkCmdEndDebugUtilsLabelEXT.self)
        self.vkCmdInsertDebugUtilsLabelEXT = loadInstanceProc(instance, "vkCmdInsertDebugUtilsLabelEXT", to: PFN_vkCmdInsertDebugUtilsLabelEXT.self)
        self.vkCreateDebugUtilsMessengerEXT = loadInstanceProc(instance, "vkCreateDebugUtilsMessengerEXT", to: PFN_vkCreateDebugUtilsMessengerEXT.self)
        self.vkDestroyDebugUtilsMessengerEXT = loadInstanceProc(instance, "vkDestroyDebugUtilsMessengerEXT", to: PFN_vkDestroyDebugUtilsMessengerEXT.self)
        self.vkSubmitDebugUtilsMessageEXT = loadInstanceProc(instance, "vkSubmitDebugUtilsMessageEXT", to: PFN_vkSubmitDebugUtilsMessageEXT.self)

        // VK_KHR_surface
        self.vkGetPhysicalDeviceSurfaceSupportKHR = loadInstanceProc(instance, "vkGetPhysicalDeviceSurfaceSupportKHR", to: PFN_vkGetPhysicalDeviceSurfaceSupportKHR.self)
        self.vkGetPhysicalDeviceSurfaceCapabilitiesKHR = loadInstanceProc(instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR", to: PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR.self)
        self.vkGetPhysicalDeviceSurfaceFormatsKHR = loadInstanceProc(instance, "vkGetPhysicalDeviceSurfaceFormatsKHR", to: PFN_vkGetPhysicalDeviceSurfaceFormatsKHR.self)
        self.vkGetPhysicalDeviceSurfacePresentModesKHR = loadInstanceProc(instance, "vkGetPhysicalDeviceSurfacePresentModesKHR", to: PFN_vkGetPhysicalDeviceSurfacePresentModesKHR.self)

#if VK_USE_PLATFORM_WAYLAND_KHR
        // VK_KHR_wayland_surface
        self.vkCreateWaylandSurfaceKHR = loadInstanceProc(instance, "vkCreateWaylandSurfaceKHR", to: PFN_vkCreateWaylandSurfaceKHR.self)
        self.vkGetPhysicalDeviceWaylandPresentationSupportKHR = loadInstanceProc(instance, "vkGetPhysicalDeviceWaylandPresentationSupportKHR", to: PFN_vkGetPhysicalDeviceWaylandPresentationSupportKHR.self)
#endif
#if VK_USE_PLATFORM_ANDROID_KHR
        // VK_KHR_android_surface
        self.vkCreateAndroidSurfaceKHR = loadInstanceProc(instance, "vkCreateAndroidSurfaceKHR", to: PFN_vkCreateAndroidSurfaceKHR.self)
#endif
#if VK_USE_PLATFORM_WIN32_KHR
        // VK_KHR_win32_surface
        self.vkCreateWin32SurfaceKHR = loadInstanceProc(instance, "vkCreateWin32SurfaceKHR", to: PFN_vkCreateWin32SurfaceKHR.self)
        self.vkGetPhysicalDeviceWin32PresentationSupportKHR = loadInstanceProc(instance, "vkGetPhysicalDeviceWin32PresentationSupportKHR", to: PFN_vkGetPhysicalDeviceWin32PresentationSupportKHR.self)
#endif
    }
    func loadInstanceProc<T>(_ instance: VkInstance, _ proc: String, to: T.Type) -> T? {
        if let pfn = vkGetInstanceProcAddr(instance, proc) {
            return unsafeBitCast(pfn, to: T.self)
        }
        return nil
    }
}

public struct VulkanDeviceExtensions {


    mutating func load(device: VkDevice) {

    }
    func loadDeviceProc<T>(_ device: VkDevice, _ proc: String, to: T.Type) -> T? {
        if let pfn = vkGetDeviceProcAddr(device, proc) {
            return unsafeBitCast(pfn, to: T.self)
        }
        return nil
    }
}
#endif //if ENABLE_VULKAN