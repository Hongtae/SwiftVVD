//
//  File: VulkanInstance.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

let VK_MAKE_VERSION = { (major: UInt32, minor: UInt32, patch: UInt32)->UInt32 in
    (((major) << 22) | ((minor) << 12) | (patch))
}
let VK_VERSION_MAJOR = { (version: UInt32) -> UInt32 in
    version >> 22
}
let VK_VERSION_MINOR = { (version: UInt32) -> UInt32 in
    (version >> 12) & 0x3ff 
}
let VK_VERSION_PATCH = { (version: UInt32) -> UInt32 in
    (version & 0xfff)
}

public struct VulkanLayerProperties {
    let name: String
    let specVersion: UInt32
    let implementationVersion: UInt32
    let description: String
    let extensions: [String: UInt32]
}

private weak var vulkanDebugLogger: Logger? = nil

public class VulkanLogger: Logger {
    public init() {
        super.init(category: "Vulkan", bind: false)
    }
}

private func debugUtilsMessengerCallback(messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT,
                                         messageTypes: VkDebugUtilsMessageTypeFlagsEXT,
                                         pCallbackData: UnsafePointer<VkDebugUtilsMessengerCallbackDataEXT>?,
                                         pUserData: UnsafeMutableRawPointer?) -> VkBool32 {

    var logLevel: Log.Level = .info    
    var prefix = ""
    if (messageSeverity.rawValue & VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT.rawValue) != 0 {
        prefix += ""
        logLevel = .verbose
    }
    if (messageSeverity.rawValue & VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT.rawValue) != 0 {
        prefix += "INFO: "
        logLevel = .info
    }
    if (messageSeverity.rawValue & VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT.rawValue) != 0 {
        prefix += "WARNING: "
        logLevel = .warning
    }
    if (messageSeverity.rawValue & VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT.rawValue) != 0 {
        prefix += "ERROR: "
        logLevel = .error
    }

    var type = ""
    if (messageTypes & UInt32(VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT.rawValue)) != 0 {
        type += ""
    }
    if (messageTypes & UInt32(VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT.rawValue)) != 0 {
        type += "VALIDATION-"
    }
    if (messageTypes & UInt32(VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT.rawValue)) != 0 {
        type += "PERFORMANCE-"
    }

    var mesgId: String = ""
    if let name = pCallbackData!.pointee.pMessageIdName {
        mesgId = String(cString: name)
    }
    let mesgIdNum = String(format:"0x%02x", pCallbackData!.pointee.messageIdNumber)
    let mesg = String(cString: pCallbackData!.pointee.pMessage)

    if let logger = vulkanDebugLogger {
        logger.log(level: logLevel, "[\(mesgId)](\(mesgIdNum)) \(mesg)")
    } else {
        Log.log(level: logLevel, "[VULKAN \(type)\(prefix)] [\(mesgId)](\(mesgIdNum)) \(mesg)")
    }

    return VkBool32(VK_FALSE)
}

public class VulkanInstance {

    public private(set) var layers: [String: VulkanLayerProperties]
    public private(set) var extensions: [String: UInt32] // key: extension-name, value: spec-version
    public private(set) var extensionSupportLayers: [String: [String]] // key: extension-name, value: layer-names(array)
    public private(set) var physicalDevices: [VulkanPhysicalDeviceDescription]

    public private(set) var instance: VkInstance
    public private(set) var allocationCallbacks: UnsafePointer<VkAllocationCallbacks>?
    
    private var debugMessenger: VkDebugUtilsMessengerEXT?
    
    public var extensionProc = VulkanInstanceExtensions()

    public let debugLogger = VulkanLogger()

    private let tempBufferHolder = TemporaryBufferHolder(label: "VulkanInstance") // for allocated unsafe buffers

    public init?(requiredLayers: [String] = [],
                 optionalLayers: [String] = [],
                 requiredExtensions: [String] = [],
                 optionalExtensions: [String] = [],
                 enableExtensionsForEnabledLayers: Bool = false,
                 enableLayersForEnabledExtensions: Bool = false,
                 enableValidation: Bool = false,
                 enableDebugUtils: Bool = false,
                 allocationCallbacks: VkAllocationCallbacks? = nil) {
        var requiredLayers = requiredLayers
        var optionalLayers = optionalLayers
        var requiredExtensions = requiredExtensions
        var optionalExtensions = optionalExtensions

        vulkanDebugLogger = self.debugLogger

        var appInfo : VkApplicationInfo = VkApplicationInfo()
        appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO
        appInfo.pNext = nil
        
        let tempHolder = TemporaryBufferHolder(label: "VulkanInstance.init")

        let applicationName = unsafePointerCopy(string: "DKGame.Vulkan", holder: tempHolder)
        let engineName = unsafePointerCopy(string: "DKGL", holder: tempHolder)

        appInfo.pApplicationName = applicationName
        appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0)
        appInfo.pEngineName = engineName
        appInfo.engineVersion = VK_MAKE_VERSION(2, 0, 0)
        appInfo.apiVersion = VK_MAKE_VERSION(1, 2, 0) // Vulkan-1.2

        var instanceVersion : UInt32 = 0
        var err: VkResult = VK_SUCCESS

        err = vkEnumerateInstanceVersion(&instanceVersion)
        if err == VK_SUCCESS {
            print(String(format: "Vulkan-Instance Version: %d.%d.%d (%d)",
                    VK_VERSION_MAJOR(instanceVersion),
                    VK_VERSION_MINOR(instanceVersion),
                    VK_VERSION_PATCH(instanceVersion),
                    instanceVersion))
        } else {
            print("vkEnumerateInstanceVersion failed: \(err)")
            return nil
        }

        // checking layers
        let availableLayers = { ()-> [VulkanLayerProperties] in
            var layers: [VulkanLayerProperties] = []
            var layerCount: UInt32 = 0
            vkEnumerateInstanceLayerProperties(&layerCount, nil)

            let rawLayers: [VkLayerProperties] = .init(unsafeUninitializedCapacity: Int(layerCount)) {
                buffer, initializedCount in
                vkEnumerateInstanceLayerProperties(&layerCount, buffer.baseAddress)
                initializedCount = Int(layerCount)
            }
            for layer in rawLayers {
                let prop = VulkanLayerProperties(
                    name: withUnsafeBytes(of: layer.layerName) {
                        String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
                    },
                    specVersion: layer.specVersion,
                    implementationVersion: layer.implementationVersion,
                    description: withUnsafeBytes(of: layer.description) {
                        String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
                    },
                    extensions: [:])
                layers.append(prop)                
            }
            return layers
        }()

        self.layers = .init(minimumCapacity: availableLayers.count)
        self.extensionSupportLayers = [:]

        for layer in availableLayers {
            let extensions = layer.name.withCString { cname -> [String: UInt32] in
                var extensions: [String: UInt32] = [:]
                var extCount: UInt32 = 0
                let err = vkEnumerateInstanceExtensionProperties(cname, &extCount, nil)
                if err == VK_SUCCESS {
                    if extCount > 0 {
                        let rawExtensions: [VkExtensionProperties] = .init(unsafeUninitializedCapacity: Int(extCount)) {
                            buffer, initializedCount in
                            vkEnumerateInstanceExtensionProperties(cname, &extCount, buffer.baseAddress)
                            initializedCount = Int(extCount)
                        }
                        for ext in rawExtensions {
                            let extensionName = withUnsafeBytes(of: ext.extensionName) {
                                String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
                            }
                            extensions[extensionName] = ext.specVersion
                        }
                    }
                } else {
                    Log.err("vkEnumerateInstanceExtensionProperties failed: \(err)")
                }
                return extensions
            }            
            for ext in extensions.keys {
                if var extLayers = self.extensionSupportLayers[ext] {
                    extLayers.append(layer.name)
                } else {
                    self.extensionSupportLayers[ext] = [layer.name]
                }
            }

            let prop = VulkanLayerProperties(
                name: layer.name,
                specVersion: layer.specVersion,
                implementationVersion: layer.implementationVersion,
                description: layer.description,
                extensions: extensions)

            self.layers[prop.name] = prop
        }
        // default ext
        self.extensions = { () -> [String: UInt32] in
            var extensions: [String: UInt32] = [:]
            var extCount: UInt32 = 0
            let err = vkEnumerateInstanceExtensionProperties(nil, &extCount, nil)
            if err == VK_SUCCESS {
                if extCount > 0 {
                    let rawExtensions: [VkExtensionProperties] = .init(unsafeUninitializedCapacity: Int(extCount)) {
                        buffer, initializedCount in
                        vkEnumerateInstanceExtensionProperties(nil, &extCount, buffer.baseAddress)
                        initializedCount = Int(extCount)
                    }
                    for ext in rawExtensions {
                        let extensionName = withUnsafeBytes(of: ext.extensionName) {
                            String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
                        }
                        extensions[extensionName] = ext.specVersion
                    }
                }
            } else {
                Log.err("vkEnumerateInstanceExtensionProperties failed:\(err)")
            }
            return extensions
        }()
        for ext in self.extensions.keys {
            if self.extensionSupportLayers[ext] == nil {
                self.extensionSupportLayers[ext] = []
            }
        }

        let printInfo = true
        if printInfo {
            Log.verbose("Vulkan available layers: \(self.layers.count)")
            for layer in self.layers.values {
                let spec = "\(VK_VERSION_MAJOR(layer.specVersion)).\(VK_VERSION_MINOR(layer.specVersion)).\(VK_VERSION_PATCH(layer.specVersion))"
                Log.verbose(" -- Layer: \(layer.name) (\"\(layer.description)\", spec:\(spec), implementation:\(layer.implementationVersion))")

                for ext in layer.extensions.keys.sorted() {
                    let specVersion = layer.extensions[ext]!
                    Log.verbose("  +-- Layer extension: \(ext) (Version: \(specVersion))")
                }
            }
            for ext in self.extensions.keys.sorted() {
                let specVersion = self.extensions[ext]!
                Log.verbose(" -- Instance extension: \(ext) (Version: \(specVersion))")
            }
        }

        if enableValidation {
            requiredLayers.append("VK_LAYER_KHRONOS_validation")
            requiredExtensions.append(VK_EXT_DEBUG_UTILS_EXTENSION_NAME)
        } else if enableDebugUtils {
            requiredExtensions.append(VK_EXT_DEBUG_UTILS_EXTENSION_NAME)
        }

        requiredExtensions.append(VK_KHR_SURFACE_EXTENSION_NAME)
#if VK_USE_PLATFORM_WIN32_KHR
        requiredExtensions.append(VK_KHR_WIN32_SURFACE_EXTENSION_NAME)
#endif
#if VK_USE_PLATFORM_ANDROID_KHR
        requiredExtensions.append(VK_KHR_ANDROID_SURFACE_EXTENSION_NAME)
#endif
#if VK_USE_PLATFORM_WAYLAND_KHR
        requiredExtensions.append(VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME)
#endif

        // add layers for required extensions
        for ext in requiredExtensions {
            if let layers = self.extensionSupportLayers[ext] {
                if enableLayersForEnabledExtensions {
                    requiredLayers.append(contentsOf: layers)
                }
            } else {
                Log.warn("Instance extension: \(ext) not supported, but required.")
            }
        }
        // add layers for optional extensions,
        for ext in optionalExtensions {
            if let layers = self.extensionSupportLayers[ext] {
                if enableLayersForEnabledExtensions {
                    optionalLayers.append(contentsOf: layers)
                }
            } else {
                Log.warn("Instance extension: \(ext) not supported.")
            }
        }
        
        // setup layer, merge extension list
        var enabledLayers: [String] = []
        for layer in optionalLayers {
            if self.layers[layer] != nil {
                requiredLayers.append(layer)
            } else {
                Log.warn("Layer: \(layer) not supported.")
            }
        }
        for layer in requiredLayers {
            enabledLayers.append(layer)
            if self.layers[layer] == nil {
                Log.warn("Layer: \(layer) not supported, but required.")
            }
        }
        // setup instance extensions!
        var enabledExtensions: [String] = []
        if enableExtensionsForEnabledLayers {
            for item in enabledLayers {
                if let layer = self.layers[item] {
                    optionalExtensions.append(contentsOf: layer.extensions.keys)
                }
            }
        }
        // merge two extensions
        for ext in optionalExtensions {
            if self.extensionSupportLayers[ext] != nil {
                requiredExtensions.append(ext)
            }
        }
        enabledExtensions.append(contentsOf: requiredExtensions)

        var instanceCreateInfo: VkInstanceCreateInfo = VkInstanceCreateInfo()
        instanceCreateInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        instanceCreateInfo.pApplicationInfo = unsafePointerCopy(from: appInfo, holder: tempHolder)

        if enableValidation {
            let enabledFeatures: [VkValidationFeatureEnableEXT] = [
                VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_EXT,
                VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_RESERVE_BINDING_SLOT_EXT]

            var validationFeatures = VkValidationFeaturesEXT()
            validationFeatures.sType = VK_STRUCTURE_TYPE_VALIDATION_FEATURES_EXT

            validationFeatures.enabledValidationFeatureCount = UInt32(enabledFeatures.count)
            validationFeatures.pEnabledValidationFeatures = unsafePointerCopy(collection: enabledFeatures, holder: tempHolder)

            instanceCreateInfo.pNext = UnsafeRawPointer(unsafePointerCopy(from: validationFeatures, holder: tempHolder))
        }

        if enabledLayers.count > 0 {
            instanceCreateInfo.enabledLayerCount = UInt32(enabledLayers.count)
            instanceCreateInfo.ppEnabledLayerNames = unsafePointerCopy(collection: enabledLayers.map {
                unsafePointerCopy(string: $0, holder: tempHolder)
            }, holder: tempHolder)
        }
        if enabledExtensions.count > 0 {
            instanceCreateInfo.enabledExtensionCount = UInt32(enabledExtensions.count)
            instanceCreateInfo.ppEnabledExtensionNames = unsafePointerCopy(collection: enabledExtensions.map {
                unsafePointerCopy(string: $0, holder: tempHolder)
            }, holder: tempHolder)
        }

        // create instance!
        self.physicalDevices = []

        if let cb = allocationCallbacks {
            self.allocationCallbacks = unsafePointerCopy(from: cb, holder: self.tempBufferHolder)
        }

        var instance: VkInstance?
        err = vkCreateInstance(&instanceCreateInfo, self.allocationCallbacks, &instance)
        if err != VK_SUCCESS {
            Log.err("vkCreateInstance failed: \(err)")
            return nil
        }

        self.instance = instance!

        if enabledLayers.isEmpty {
            Log.verbose("VkInstance enabled layers: None")
        } else {
            for (index, layer) in enabledLayers.enumerated() {
                Log.verbose("VkInstance enabled layer[\(index)]: \(layer)")
            }
        }
        if enabledExtensions.isEmpty {
            Log.verbose("VkInstance enabled extensions: None")
        } else {
            for (index, ext) in enabledExtensions.enumerated() {
                Log.verbose("VkInstance enabled extension[\(index)]: \(ext)")
            }
        }

        // load extensions
        self.extensionProc.load(instance: self.instance)

        if enabledExtensions.contains(VK_EXT_DEBUG_UTILS_EXTENSION_NAME) {
            var debugUtilsMessengerCreateInfo = VkDebugUtilsMessengerCreateInfoEXT()
            debugUtilsMessengerCreateInfo.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
            debugUtilsMessengerCreateInfo.messageSeverity = UInt32(
                VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT.rawValue |
                VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT.rawValue |
                VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT.rawValue |
                VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT.rawValue)

            debugUtilsMessengerCreateInfo.messageType = UInt32(
                VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT.rawValue |
                VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT.rawValue |
                VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT.rawValue)

            debugUtilsMessengerCreateInfo.pUserData = nil
            debugUtilsMessengerCreateInfo.pfnUserCallback = debugUtilsMessengerCallback

            err = self.extensionProc.vkCreateDebugUtilsMessengerEXT!(instance, &debugUtilsMessengerCreateInfo, self.allocationCallbacks, &self.debugMessenger)
            if err != VK_SUCCESS {
                Log.err("vkCreateDebugUtilsMessengerEXT failed: \(err)")
            }
        }

        // get physical device list
        var gpuCount: UInt32 = 0
        err = vkEnumeratePhysicalDevices(instance, &gpuCount, nil)
        if err != VK_SUCCESS {
            Log.err("vkEnumeratePhysicalDevices failed: \(err)")
        }
        if gpuCount > 0 {
            // enumerate devices
            var physicalDevices: [VkPhysicalDevice?] = .init(repeating: nil, count: Int(gpuCount))
            err = vkEnumeratePhysicalDevices(instance, &gpuCount, &physicalDevices)
            if err != VK_SUCCESS {
                Log.err("ERROR: vkEnumeratePhysicalDevices failed: \(err)")
                return nil
            }
            var maxQueueSize: UInt = 0
            for device in physicalDevices {
                let pd = VulkanPhysicalDeviceDescription(device: device!)
                maxQueueSize = max(maxQueueSize, pd.maxQueues)
                self.physicalDevices.append(pd)
            }
        } else {
            Log.err("No Vulkan GPU found")
            return nil
        }
        // sort deviceList order by Type/NumQueues/Memory
        self.physicalDevices.sort {
            lhs, rhs in
            if lhs.devicePriority == rhs.devicePriority {
                if lhs.numGCQueues == rhs.numGCQueues {
                    return lhs.deviceMemory > rhs.deviceMemory
                }
                return lhs.numGCQueues > rhs.numGCQueues
            }
            return lhs.devicePriority > rhs.devicePriority
        }

        for (index, device) in self.physicalDevices.enumerated() {
            Log.verbose("PhysicalDevice[\(index)]: \(device)")
        }
    }

    deinit {
        if let messenger = self.debugMessenger {
            self.extensionProc.vkDestroyDebugUtilsMessengerEXT?(self.instance, messenger, self.allocationCallbacks)
        }
        vkDestroyInstance(self.instance, self.allocationCallbacks)
    }

    public func makeDevice(identifier: String,
                           requiredExtensions: [String] = [],
                           optionalExtensions: [String] = []) -> VulkanGraphicsDevice? {
        for device in self.physicalDevices {
            if device.registryID == identifier {
                return VulkanGraphicsDevice(instance: self,
                                            physicalDevice: device,
                                            requiredExtensions: requiredExtensions,
                                            optionalExtensions: optionalExtensions)
            }
        }
        return nil
    }

    public func makeDevice(requiredExtensions: [String] = [],
                           optionalExtensions: [String] = []) -> VulkanGraphicsDevice? {
        for device in self.physicalDevices {
            if let vgd = VulkanGraphicsDevice(instance: self,
                                              physicalDevice: device,
                                              requiredExtensions: requiredExtensions,
                                              optionalExtensions: optionalExtensions) {
                return vgd
            }
        }
        return nil
    }    
}
#endif //if ENABLE_VULKAN