//
//  File: VulkanExtensions.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

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
    // var vkGetPhysicalDeviceSurfaceSupportKHR: PFN_vkGetPhysicalDeviceSurfaceSupportKHR?
    // var vkGetPhysicalDeviceSurfaceCapabilitiesKHR: PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR?
    // var vkGetPhysicalDeviceSurfaceFormatsKHR: PFN_vkGetPhysicalDeviceSurfaceFormatsKHR?
    // var vkGetPhysicalDeviceSurfacePresentModesKHR: PFN_vkGetPhysicalDeviceSurfacePresentModesKHR?


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
        // self.vkGetPhysicalDeviceSurfaceSupportKHR = loadInstanceProc(instance, "vkGetPhysicalDeviceSurfaceSupportKHR", to: PFN_vkGetPhysicalDeviceSurfaceSupportKHR.self)
        // self.vkGetPhysicalDeviceSurfaceCapabilitiesKHR = loadInstanceProc(instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR", to: PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR.self)
        // self.vkGetPhysicalDeviceSurfaceFormatsKHR = loadInstanceProc(instance, "vkGetPhysicalDeviceSurfaceFormatsKHR", to: PFN_vkGetPhysicalDeviceSurfaceFormatsKHR.self)
        // self.vkGetPhysicalDeviceSurfacePresentModesKHR = loadInstanceProc(instance, "vkGetPhysicalDeviceSurfacePresentModesKHR", to: PFN_vkGetPhysicalDeviceSurfacePresentModesKHR.self)

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

extension VkResult: CustomStringConvertible {
    public var description: String {
        let enumStr = { (value: VkResult) -> String in
            switch (value) {
            case VK_SUCCESS:
                return "VK_SUCCESS"
            case VK_NOT_READY:
                return "VK_NOT_READY"
            case VK_TIMEOUT:
                return "VK_TIMEOUT"
            case VK_EVENT_SET:
                return "VK_EVENT_SET"
            case VK_EVENT_RESET:
                return "VK_EVENT_RESET"
            case VK_INCOMPLETE:
                return "VK_INCOMPLETE"
            case VK_ERROR_OUT_OF_HOST_MEMORY:
                return "VK_ERROR_OUT_OF_HOST_MEMORY"
            case VK_ERROR_OUT_OF_DEVICE_MEMORY:
                return "VK_ERROR_OUT_OF_DEVICE_MEMORY"
            case VK_ERROR_INITIALIZATION_FAILED:
                return "VK_ERROR_INITIALIZATION_FAILED"
            case VK_ERROR_DEVICE_LOST:
                return "VK_ERROR_DEVICE_LOST"
            case VK_ERROR_MEMORY_MAP_FAILED:
                return "VK_ERROR_MEMORY_MAP_FAILED"
            case VK_ERROR_LAYER_NOT_PRESENT:
                return "VK_ERROR_LAYER_NOT_PRESENT"
            case VK_ERROR_EXTENSION_NOT_PRESENT:
                return "VK_ERROR_EXTENSION_NOT_PRESENT"
            case VK_ERROR_FEATURE_NOT_PRESENT:
                return "VK_ERROR_FEATURE_NOT_PRESENT"
            case VK_ERROR_INCOMPATIBLE_DRIVER:
                return "VK_ERROR_INCOMPATIBLE_DRIVER"
            case VK_ERROR_TOO_MANY_OBJECTS:
                return "VK_ERROR_TOO_MANY_OBJECTS"
            case VK_ERROR_FORMAT_NOT_SUPPORTED:
                return "VK_ERROR_FORMAT_NOT_SUPPORTED"
            case VK_ERROR_FRAGMENTED_POOL:
                return "VK_ERROR_FRAGMENTED_POOL"
            case VK_ERROR_UNKNOWN:
                return "VK_ERROR_UNKNOWN"
            case VK_ERROR_OUT_OF_POOL_MEMORY:
                return "VK_ERROR_OUT_OF_POOL_MEMORY"
            case VK_ERROR_INVALID_EXTERNAL_HANDLE:
                return "VK_ERROR_INVALID_EXTERNAL_HANDLE"
            case VK_ERROR_FRAGMENTATION:
                return "VK_ERROR_FRAGMENTATION"
            case VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS:
                return "VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS"
            case VK_ERROR_SURFACE_LOST_KHR:
                return "VK_ERROR_SURFACE_LOST_KHR"
            case VK_ERROR_NATIVE_WINDOW_IN_USE_KHR:
                return "VK_ERROR_NATIVE_WINDOW_IN_USE_KHR"
            case VK_SUBOPTIMAL_KHR:
                return "VK_SUBOPTIMAL_KHR"
            case VK_ERROR_OUT_OF_DATE_KHR:
                return "VK_ERROR_OUT_OF_DATE_KHR"
            case VK_ERROR_INCOMPATIBLE_DISPLAY_KHR:
                return "VK_ERROR_INCOMPATIBLE_DISPLAY_KHR"
            case VK_ERROR_VALIDATION_FAILED_EXT:
                return "VK_ERROR_VALIDATION_FAILED_EXT"
            case VK_ERROR_INVALID_SHADER_NV:
                return "VK_ERROR_INVALID_SHADER_NV"
            case VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT:
                return "VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT"
            case VK_ERROR_NOT_PERMITTED_EXT:
                return "VK_ERROR_NOT_PERMITTED_EXT"
            case VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT:
                return "VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT"
            default:
                break
            }
            return "VkResult"
        }
        return enumStr(self) + "(\(self.rawValue))"
    }
}

#endif //if ENABLE_VULKAN