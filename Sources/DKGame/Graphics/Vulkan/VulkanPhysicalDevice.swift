#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanPhysicalDeviceDescription: CustomStringConvertible {

    public enum DeviceType { 
        case integratedGPU
        case discreteGPU
        case virtualGPU
        case cpu
        case unknown
    }

    public let device: VkPhysicalDevice
    public private(set) lazy var name: String = {
        withUnsafeBytes(of: self.properties.deviceName) {
            String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }()
    public var venderID: UInt32 { self.properties.vendorID }
    public var deviceID: UInt32 { self.properties.deviceID }

    public private(set) lazy var registryID: String = {
        String(format: "%08x%08x", self.properties.vendorID, self.properties.deviceID)
    }()

    public let devicePriority: Int
    public let deviceMemory: UInt64
    public let numGCQueues: UInt        // graphics | compute queue count.
    public let maxQueues: UInt

    public let properties: VkPhysicalDeviceProperties
    public let features: VkPhysicalDeviceFeatures
    public let timelineSemaphoreSupported: Bool
    public let memory: VkPhysicalDeviceMemoryProperties
    public let queueFamilies: [VkQueueFamilyProperties]
    public let extensions: [String: UInt32]

    public func hasExtension(_ name: String) -> Bool { self.extensions[name] != nil }

    public init(device: VkPhysicalDevice) {
        self.device = device

        var queueFamilyCount: UInt32 = 0
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nil)

        self.queueFamilies = .init(unsafeUninitializedCapacity: Int(queueFamilyCount)) {
            buffer, initializedCount in
            vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, buffer.baseAddress)
            initializedCount = Int(queueFamilyCount)
        }

        var numGCQueues: UInt = 0 // graphics | compute queue
        var maxQueues: UInt = 0
        // calculate num available queues. (Graphics & Compute)
        for qf in self.queueFamilies {
            if (qf.queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue | VK_QUEUE_COMPUTE_BIT.rawValue)) != 0 {
                numGCQueues += UInt(qf.queueCount)
            }
            maxQueues = max(maxQueues, UInt(qf.queueCount))
        }
        self.numGCQueues = numGCQueues
        self.maxQueues = maxQueues

        var properties = VkPhysicalDeviceProperties()
        vkGetPhysicalDeviceProperties(device, &properties);

        self.properties = properties

        var memoryProperties = VkPhysicalDeviceMemoryProperties()
        vkGetPhysicalDeviceMemoryProperties(device, &memoryProperties);
        self.memory = memoryProperties

        var timelineSemaphoreSupport = VkPhysicalDeviceTimelineSemaphoreFeaturesKHR()
        timelineSemaphoreSupport.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES_KHR
        timelineSemaphoreSupport.timelineSemaphore = 0

        var features = VkPhysicalDeviceFeatures2()
        features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2

        withUnsafeMutablePointer(to: &timelineSemaphoreSupport) {
            features.pNext = UnsafeMutableRawPointer($0)
            vkGetPhysicalDeviceFeatures2(device, &features);
        }
        self.features = features.features
        self.timelineSemaphoreSupported = timelineSemaphoreSupport.timelineSemaphore != 0

        var devicePriority = 0
        switch (properties.deviceType) {
        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:		devicePriority += 1; fallthrough 
        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU:    devicePriority += 1; fallthrough 
        case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU:		devicePriority += 1; fallthrough 
        case VK_PHYSICAL_DEVICE_TYPE_CPU:				devicePriority += 1; fallthrough 
        default:    // VK_PHYSICAL_DEVICE_TYPE_OTHER
            break
        }

        var deviceMemory: UInt64 = 0
        // calculate device memory
        withUnsafeBytes(of: &memoryProperties.memoryHeaps) {
            let memoryHeaps = $0.bindMemory(to: VkMemoryHeap.self)
            for index in 0 ..< memoryProperties.memoryHeapCount {
                let heap = memoryHeaps[Int(index)]
                if (heap.flags & UInt32(VK_MEMORY_HEAP_DEVICE_LOCAL_BIT.rawValue)) != 0 {
                    deviceMemory += heap.size
                }
            } 
        }
        self.deviceMemory = deviceMemory
        self.devicePriority = devicePriority

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
            NSLog("ERROR: vkEnumerateDeviceExtensionProperties failed:\(err.rawValue)")
        }
        self.extensions = extensions
    }

    public var description: String {

        var deviceType = "Unknown"

        switch (self.properties.deviceType)
        {
        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU:
            deviceType = "INTEGRATED_GPU"
        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:
            deviceType = "DISCRETE_GPU"
        case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU:
            deviceType = "VIRTUAL_GPU"
        case VK_PHYSICAL_DEVICE_TYPE_CPU:
            deviceType = "CPU"
        default:
            deviceType = "UNKNOWN"
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
        return desc
    }
}
#endif //if ENABLE_VULKAN