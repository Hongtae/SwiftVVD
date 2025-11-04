//
//  File: VulkanPhysicalDevice.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanPhysicalDeviceDescription: CustomStringConvertible {

    enum DeviceType { 
        case integratedGPU
        case discreteGPU
        case virtualGPU
        case cpu
        case unknown
    }

    let device: VkPhysicalDevice
    private(set) lazy var name: String = {
        withUnsafeBytes(of: self.properties.deviceName) {
            String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }()
    var vendorID: UInt32 { self.properties.vendorID }
    var deviceID: UInt32 { self.properties.deviceID }

    private(set) lazy var registryID: String = {
        String(format: "%08x%08x", self.properties.vendorID, self.properties.deviceID)
    }()

    private(set) var devicePriority: Int
    private(set) var deviceMemory: UInt64
    private(set) var numGCQueues: UInt        // graphics | compute queue count.
    private(set) var maxQueues: UInt

    private(set) var properties: VkPhysicalDeviceProperties
    private(set) var deviceIDProperties: VkPhysicalDeviceIDProperties
    private(set) var deviceDriverProperties: VkPhysicalDeviceDriverProperties
    private(set) var extendedDynamicState3Properties: VkPhysicalDeviceExtendedDynamicState3PropertiesEXT 

    private(set) var features: VkPhysicalDeviceFeatures
    private(set) var v11Features: VkPhysicalDeviceVulkan11Features 
    private(set) var v12Features: VkPhysicalDeviceVulkan12Features 
    private(set) var v13Features: VkPhysicalDeviceVulkan13Features
    private(set) var extendedDynamicStateFeatures: VkPhysicalDeviceExtendedDynamicStateFeaturesEXT
    private(set) var extendedDynamicState2Features: VkPhysicalDeviceExtendedDynamicState2FeaturesEXT
    private(set) var extendedDynamicState3Features: VkPhysicalDeviceExtendedDynamicState3FeaturesEXT

    private(set) var memory: VkPhysicalDeviceMemoryProperties
    private(set) var queueFamilies: [VkQueueFamilyProperties]
    private(set) var extensions: [String: UInt32]

    func hasExtension(_ name: String) -> Bool { self.extensions[name] != nil }

    var deviceUUID: UUID {
        UUID(uuid: self.deviceIDProperties.deviceUUID)
    }
    var driverUUID: UUID {
        UUID(uuid: self.deviceIDProperties.driverUUID)
    }
    var driverName: String {
        withUnsafeBytes(of: self.deviceDriverProperties.driverName) {
            String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }
    var driverInfo: String {
        withUnsafeBytes(of: self.deviceDriverProperties.driverInfo) {
            String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }
    var conformanceVersion: (major: UInt8, minor: UInt8, subminor: UInt8, patch: UInt8) {
        let v = self.deviceDriverProperties.conformanceVersion
        return (v.major, v.minor, v.subminor, v.patch)
    }

    var deviceType: DeviceType {
        switch self.properties.deviceType {
        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU:    return .integratedGPU
        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:      return .discreteGPU
        case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU:       return .virtualGPU
        case VK_PHYSICAL_DEVICE_TYPE_CPU:               return .cpu
        default:                                        return .unknown
        }
    }

    init(device: VkPhysicalDevice) {
        self.device = device
        self.numGCQueues = 0 // graphics | compute queue
        self.maxQueues = 0
        self.deviceMemory = 0
        self.devicePriority = 0

        self.properties = VkPhysicalDeviceProperties()
        self.deviceIDProperties = VkPhysicalDeviceIDProperties()
        self.deviceIDProperties.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES
        self.deviceDriverProperties = VkPhysicalDeviceDriverProperties()
        self.deviceDriverProperties.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES
        self.extendedDynamicState3Properties = VkPhysicalDeviceExtendedDynamicState3PropertiesEXT()
        self.extendedDynamicState3Properties.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_PROPERTIES_EXT

        self.features = VkPhysicalDeviceFeatures()
        self.v11Features = VkPhysicalDeviceVulkan11Features()
        self.v11Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES
        self.v12Features = VkPhysicalDeviceVulkan12Features()
        self.v12Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
        self.v13Features = VkPhysicalDeviceVulkan13Features()
        self.v13Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES

        self.extendedDynamicStateFeatures = VkPhysicalDeviceExtendedDynamicStateFeaturesEXT()
        self.extendedDynamicStateFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT
        self.extendedDynamicState2Features = VkPhysicalDeviceExtendedDynamicState2FeaturesEXT()
        self.extendedDynamicState2Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT
        self.extendedDynamicState3Features = VkPhysicalDeviceExtendedDynamicState3FeaturesEXT()
        self.extendedDynamicState3Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT

        self.memory = VkPhysicalDeviceMemoryProperties()
        self.queueFamilies = []
        self.extensions = [:]

        let tempHolder = TemporaryBufferHolder(label: "VulkanPhysicalDevice.init")

        var queueFamilyCount: UInt32 = 0
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nil)

        self.queueFamilies = .init(unsafeUninitializedCapacity: Int(queueFamilyCount)) {
            buffer, initializedCount in
            vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, buffer.baseAddress)
            initializedCount = Int(queueFamilyCount)
        }

        // calculate num available queues. (Graphics & Compute)
        for qf in self.queueFamilies {
            if (qf.queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue | VK_QUEUE_COMPUTE_BIT.rawValue)) != 0 {
                self.numGCQueues += UInt(qf.queueCount)
            }
            self.maxQueues = max(self.maxQueues, UInt(qf.queueCount))
        }

        var properties = VkPhysicalDeviceProperties2()
        properties.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2
        appendNextChain(&properties, unsafePointerCopy(from: self.extendedDynamicState3Properties, holder: tempHolder))
        appendNextChain(&properties, unsafePointerCopy(from: self.deviceIDProperties, holder: tempHolder))
        appendNextChain(&properties, unsafePointerCopy(from: self.deviceDriverProperties, holder: tempHolder))

        vkGetPhysicalDeviceProperties2(device, &properties)
        self.properties = properties.properties

        enumerateNextChain(properties.pNext) { sType, ptr in
            if sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_PROPERTIES_EXT {
                self.extendedDynamicState3Properties =
                    ptr.bindMemory(to: VkPhysicalDeviceExtendedDynamicState3PropertiesEXT.self, capacity: 1).pointee
            }
            if sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES {
                self.deviceIDProperties = ptr.bindMemory(to: VkPhysicalDeviceIDProperties.self, capacity: 1).pointee
            }
            if sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES {
                self.deviceDriverProperties = ptr.bindMemory(to: VkPhysicalDeviceDriverProperties.self, capacity: 1).pointee
            }
        }

        var memoryProperties = VkPhysicalDeviceMemoryProperties()
        vkGetPhysicalDeviceMemoryProperties(device, &memoryProperties)
        self.memory = memoryProperties

        var features = VkPhysicalDeviceFeatures2()
        features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2

        appendNextChain(&features, unsafePointerCopy(from: self.v11Features, holder: tempHolder))
        appendNextChain(&features, unsafePointerCopy(from: self.v12Features, holder: tempHolder))
        appendNextChain(&features, unsafePointerCopy(from: self.v13Features, holder: tempHolder))
        appendNextChain(&features, unsafePointerCopy(from: self.extendedDynamicStateFeatures, holder: tempHolder))
        appendNextChain(&features, unsafePointerCopy(from: self.extendedDynamicState2Features, holder: tempHolder))
        appendNextChain(&features, unsafePointerCopy(from: self.extendedDynamicState3Features, holder: tempHolder))

        vkGetPhysicalDeviceFeatures2(device, &features)

        self.features = features.features

        enumerateNextChain(features.pNext) { sType, ptr in
            switch sType {
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES:
                self.v11Features = ptr.bindMemory(to: VkPhysicalDeviceVulkan11Features.self, capacity: 1).pointee
                self.v11Features.pNext = nil
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES:
                self.v12Features = ptr.bindMemory(to: VkPhysicalDeviceVulkan12Features.self, capacity: 1).pointee
                self.v12Features.pNext = nil
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES:
                self.v13Features = ptr.bindMemory(to: VkPhysicalDeviceVulkan13Features.self, capacity: 1).pointee
                self.v13Features.pNext = nil
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT:
                self.extendedDynamicStateFeatures = ptr.bindMemory(to: VkPhysicalDeviceExtendedDynamicStateFeaturesEXT.self, capacity: 1).pointee
                self.extendedDynamicStateFeatures.pNext = nil
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT:
                self.extendedDynamicState2Features = ptr.bindMemory(to: VkPhysicalDeviceExtendedDynamicState2FeaturesEXT.self, capacity: 1).pointee
                self.extendedDynamicState2Features.pNext = nil
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT:
                self.extendedDynamicState3Features = ptr.bindMemory(to: VkPhysicalDeviceExtendedDynamicState3FeaturesEXT.self, capacity: 1).pointee
                self.extendedDynamicState3Features.pNext = nil
            default:
                break
            }
        }

        self.devicePriority = 0
        switch properties.properties.deviceType {
        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:
            self.devicePriority += 1
            fallthrough
        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU:
            self.devicePriority += 1
            fallthrough
        case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU:
            self.devicePriority += 1
            fallthrough
        case VK_PHYSICAL_DEVICE_TYPE_CPU:
            self.devicePriority += 1
            fallthrough
        default:    // VK_PHYSICAL_DEVICE_TYPE_OTHER
            break
        }

        self.deviceMemory = 0
        // calculate device memory
        withUnsafeBytes(of: &memoryProperties.memoryHeaps) {
            let memoryHeaps = $0.bindMemory(to: VkMemoryHeap.self)
            for index in 0 ..< memoryProperties.memoryHeapCount {
                let heap = memoryHeaps[Int(index)]
                if (heap.flags & UInt32(VK_MEMORY_HEAP_DEVICE_LOCAL_BIT.rawValue)) != 0 {
                    self.deviceMemory += heap.size
                }
            } 
        }

        // get list of supported extensions
        var extensions: [String: UInt32] = [:]
        var extCount: UInt32 = 0
        let err = vkEnumerateDeviceExtensionProperties(device, nil, &extCount, nil)
        if err == VK_SUCCESS {
            if extCount > 0 {
                let rawExtensions: [VkExtensionProperties] = .init(unsafeUninitializedCapacity: Int(extCount)) {
                    buffer, initializedCount in
                    vkEnumerateDeviceExtensionProperties(device, nil, &extCount, buffer.baseAddress)
                    initializedCount = Int(extCount)
                }
                extensions.reserveCapacity(rawExtensions.count)
                for ext in rawExtensions {
                    let extensionName = withUnsafeBytes(of: ext.extensionName) {
                        String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
                    }
                    extensions[extensionName] = ext.specVersion
                }
            }
        } else {
            Log.err("vkEnumerateDeviceExtensionProperties failed:\(err)")
        }
        self.extensions = extensions
    }

    var description: String {
        let deviceType = switch self.properties.deviceType {
        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU:    "INTEGRATED_GPU"
        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:      "DISCRETE_GPU"
        case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU:       "VIRTUAL_GPU"
        case VK_PHYSICAL_DEVICE_TYPE_CPU:               "CPU"
        default:                                        "UNKNOWN"
        }

        let apiVersion = String(format: "%d.%d.%d",
                                VK_VERSION_MAJOR(self.properties.apiVersion),
                                VK_VERSION_MINOR(self.properties.apiVersion),
                                VK_VERSION_PATCH(self.properties.apiVersion))

        var desc = "VulkanPhysicalDevice(name: \"\(self.name)\", identifier:\(self.registryID), type:\(deviceType), API:\(apiVersion), QueueFamilies:\(self.queueFamilies.count), NumExtensions:\(self.extensions.count))"
        for (index, qf) in self.queueFamilies.enumerated() {
            let flags = String(format: "0x%04x", qf.queueFlags)
            let sparseBinding = (qf.queueFlags & UInt32(VK_QUEUE_SPARSE_BINDING_BIT.rawValue)) != 0 ? "Yes" : "No"
            let transfer = (qf.queueFlags & UInt32(VK_QUEUE_TRANSFER_BIT.rawValue)) != 0 ? "Yes" : "No"
            let compute = (qf.queueFlags & UInt32(VK_QUEUE_COMPUTE_BIT.rawValue)) != 0 ? "Yes" : "No"
            let graphics = (qf.queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue)) != 0 ? "Yes" : "No"

            desc += "\n -- Queue-Family[\(index)] Flags:\(flags) (SparseBinding:\(sparseBinding), Transfer:\(transfer), Compute:\(compute), Graphics:\(graphics), Queues:\(qf.queueCount))"
        }
        for (index, name) in self.extensions.keys.sorted().enumerated() {
            desc += "\n -- Device Extension[\(index)]: \"\(name)\" (Version: \(self.extensions[name]!))"
        }
        desc += "\n -- Device UUID: \(self.deviceUUID.uuidString)"
        desc += "\n -- Driver UUID: \(self.driverUUID.uuidString)"
        var driverInfo = self.driverName
        if !self.driverInfo.isEmpty {
            driverInfo += " (\(self.driverInfo))"
        }
        let cv = self.conformanceVersion
        desc += "\n -- Driver: \(driverInfo), Conformance Version: \(cv.major).\(cv.minor).\(cv.subminor).\(cv.patch)"
        return desc
    }
}
#endif //if ENABLE_VULKAN
