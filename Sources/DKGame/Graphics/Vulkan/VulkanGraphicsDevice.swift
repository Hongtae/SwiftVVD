#if ENABLE_VULKAN
import Vulkan
import Foundation

public enum VulkanGraphicsDeviceQueueCompletionHandlerType {
    case timelineSemaphore
    case fence
    case none
}

private let pipelineCacheDataKey = "_SavedSystemStates.Vulkan.PipelineCacheData"

public class VulkanGraphicsDevice : GraphicsDevice {

    public var name: String

    public let instance: VulkanInstance
    public let physicalDevice: VulkanPhysicalDeviceDescription

    public let device: VkDevice
    public var allocationCallbacks: UnsafePointer<VkAllocationCallbacks>? { self.instance.allocationCallbacks }

    public var properties: VkPhysicalDeviceProperties { self.physicalDevice.properties }
    public var features: VkPhysicalDeviceFeatures { self.physicalDevice.features }

    public var extensionProc = VulkanDeviceExtensions()

    public let queueFamilies: [VulkanQueueFamily]
    public let deviceMemoryTypes: [VkMemoryType]
    public let deviceMemoryHeaps: [VkMemoryHeap]

    private var pipelineCache: VkPipelineCache?

    static public var queueCompletionHandlerType: VulkanGraphicsDeviceQueueCompletionHandlerType = .fence
    var queueCompletionHandlerSemaphore: VulkanQueueCompletionHandlerTimelineSemaphore?
    var queueCompletionHandlerFence: VulkanQueueCompletionHandlerFence?

    public init?(instance: VulkanInstance,
                 physicalDevice: VulkanPhysicalDeviceDescription,
                 requiredExtensions: [String],
                 optionalExtensions: [String],
                 dispatchQueue: DispatchQueue?) {

        self.instance = instance
        self.physicalDevice = physicalDevice
        self.name = physicalDevice.name

        let tempHolder = TemporaryBufferHolder(label: "VulkanGraphicsDevice.init")

        let queuePriority = [Float](repeating: 0.0, count: Int(physicalDevice.maxQueues))
        let queuePriorityPointer = unsafePointerCopy(queuePriority, holder: tempHolder)

        // setup queue
        let queueCreateInfos: [VkDeviceQueueCreateInfo] = .init(unsafeUninitializedCapacity: physicalDevice.queueFamilies.count) {
            buffer, initializedCount in
            var count = 0
            for (index, queueFamily) in physicalDevice.queueFamilies.enumerated() {
                if (queueFamily.queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue |
                                                    VK_QUEUE_COMPUTE_BIT.rawValue |
                                                    VK_QUEUE_TRANSFER_BIT.rawValue)) != 0 {
                    var queueInfo = VkDeviceQueueCreateInfo()
                    queueInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
                    queueInfo.queueFamilyIndex = UInt32(index)
                    queueInfo.queueCount = queueFamily.queueCount
                    queueInfo.pQueuePriorities = queuePriorityPointer

                    buffer[count] = queueInfo
                    count += 1
                }
            }
            initializedCount = count
        }
        if queueCreateInfos.count == 0 {
            return nil
        }

        var requiredExtensions = requiredExtensions
        var optionalExtensions = optionalExtensions

        requiredExtensions.append(VK_KHR_SWAPCHAIN_EXTENSION_NAME)
        requiredExtensions.append(VK_KHR_MAINTENANCE1_EXTENSION_NAME)
        requiredExtensions.append(VK_KHR_TIMELINE_SEMAPHORE_EXTENSION_NAME)
        // requiredExtensions.append(VK_EXT_EXTENDED_DYNAMIC_STATE_EXTENSION_NAME)

        optionalExtensions.append(VK_KHR_MAINTENANCE2_EXTENSION_NAME);
        optionalExtensions.append(VK_KHR_MAINTENANCE3_EXTENSION_NAME);

        // setup extensions
        var deviceExtensions: [String] = []
        deviceExtensions.reserveCapacity(requiredExtensions.count + optionalExtensions.count)
        for ext in requiredExtensions {
            deviceExtensions.append(ext)
            if physicalDevice.hasExtension(ext) == false {
                Log.warn("Vulkan-Device-Extension:\"\(ext)\" not supported, but required.")
            }
        }
        for ext in optionalExtensions {
            if physicalDevice.hasExtension(ext) {
                deviceExtensions.append(ext)
            } else {
                Log.warn("Warning: Vulkan-Device-Extension:\"\(ext)\" not supported.")
            }
        }

        // features
        let enabledFeatures = physicalDevice.features // enable all features supported by a device
        var deviceCreateInfo = VkDeviceCreateInfo()
        deviceCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
        deviceCreateInfo.queueCreateInfoCount = UInt32(queueCreateInfos.count)
        deviceCreateInfo.pQueueCreateInfos = unsafePointerCopy(queueCreateInfos, holder: tempHolder)
        deviceCreateInfo.pEnabledFeatures = unsafePointerCopy(enabledFeatures, holder: tempHolder)

        if deviceExtensions.count > 0 {
            deviceCreateInfo.enabledExtensionCount = UInt32(deviceExtensions.count)
            deviceCreateInfo.ppEnabledExtensionNames = unsafePointerCopy(deviceExtensions.map {
                unsafePointerCopy($0, holder: tempHolder)
            }, holder: tempHolder)
        }

#if false
        // VK_EXT_extended_dynamic_state
        
        let extendedDynamicStateFeatures: [VkPhysicalDeviceExtendedDynamicStateFeaturesEXT] = []
        if extendedDynamicStateFeatures.count > 0 {
            let count = extendedDynamicStateFeatures.count
            let pointerCopy = unsafePointerCopy(extendedDynamicStateFeatures, holder: tempHolder)
            let mutablePointer = UnsafeMutablePointer(mutating: pointerCopy)

            // make linked list with pNext chain
            //let stride = MemoryLayout<VkPhysicalDeviceExtendedDynamicStateFeaturesEXT>.stride
            for index in 0..<(count - 1) {
                mutablePointer.advanced(by: index).pointee.pNext = UnsafeRawPointer(pointerCopy.advanced(by: index+1))
            }
            if true {
                for index in 0 ..< count {
                    let ptr = pointerCopy.advanced(by: index)
                    let ss = String(format: "self:%p, pNext:%p", OpaquePointer(ptr), OpaquePointer(ptr.pointee.pNext) ?? 0)
                    Log.debug("VkPhysicalDeviceExtendedDynamicStateFeaturesEXT[\(index)] \(ss)")
                }
            }

            deviceCreateInfo.pNext = UnsafeRawPointer(pointerCopy)
        }
#endif
        var device: VkDevice? = nil
        let err = vkCreateDevice(physicalDevice.device, &deviceCreateInfo, instance.allocationCallbacks, &device)
        if err != VK_SUCCESS {
            Log.err("vkCreateDevice Failed: \(err.rawValue)")
            return nil
        }
        self.device = device!
        self.extensionProc.load(device: self.device)

        self.deviceMemoryTypes = .init(unsafeUninitializedCapacity: Int(physicalDevice.memory.memoryTypeCount)) {
            buffer, initializedCount in
            let count: Int = Int(physicalDevice.memory.memoryTypeCount)
            withUnsafeBytes(of: physicalDevice.memory.memoryTypes) {
                let memoryTypes = $0.bindMemory(to: VkMemoryType.self)
                for index in 0 ..< count {
                    buffer[index] = memoryTypes[Int(index)]
                } 
                initializedCount = count
            }
        }
        self.deviceMemoryHeaps = .init(unsafeUninitializedCapacity: Int(physicalDevice.memory.memoryHeapCount)) {
            buffer, initializedCount in
            let count: Int = Int(physicalDevice.memory.memoryHeapCount)
            withUnsafeBytes(of: physicalDevice.memory.memoryHeaps) {
                let memoryHeaps = $0.bindMemory(to: VkMemoryHeap.self)
                for index in 0 ..< count {
                    buffer[index] = memoryHeaps[Int(index)]
                } 
                initializedCount = count
            }
        }
        
        self.queueFamilies = queueCreateInfos.map {
            var supportPresentation = false
#if VK_USE_PLATFORM_ANDROID_KHR
            supportPresentation = true;	// always true on Android
#endif
#if VK_USE_PLATFORM_WIN32_KHR
            supportPresentation = instance.extensionProc.vkGetPhysicalDeviceWin32PresentationSupportKHR?(physicalDevice.device, $0.queueFamilyIndex) ?? VkBool32(VK_FALSE) != VkBool32(VK_FALSE)
#endif
            let queueFamilyIndex = $0.queueFamilyIndex
            let queueCount = $0.queueCount
            let queueFamilyProperties = physicalDevice.queueFamilies[Int(queueFamilyIndex)]
            return VulkanQueueFamily(device: device!,
                                     familyIndex: queueFamilyIndex,
                                     count: queueCount,
                                     properties: queueFamilyProperties,
                                     presentationSupport: supportPresentation)
        }.sorted {
            lhs, rhs in
            let lp = lhs.supportPresentation ? 1 : 0
            let rp = rhs.supportPresentation ? 1 : 0

            if lp == rp {
                return lhs.familyIndex < rhs.familyIndex  // smaller index first
            }
            return lp > rp
        }

        self.loadPipelineCache()

        // create queue completion handlr
        switch (Self.queueCompletionHandlerType) {
            case .timelineSemaphore:
                Log.info("VulkanGraphicsDevice: Create Queue-Completion handler! (TimelineSemaphore)")
                self.queueCompletionHandlerSemaphore = VulkanQueueCompletionHandlerTimelineSemaphore(
                    device: self,
                    dispatchQueue: dispatchQueue)
            case .fence:
                Log.info("VulkanGraphicsDevice: Create Queue-Completion handler! (Fence)")
                self.queueCompletionHandlerFence = VulkanQueueCompletionHandlerFence(
                    device: self,
                    dispatchQueue: dispatchQueue)
            default:
                Log.warn("VulkanGraphicsDevice: No Queue-Completion handler!")
                break
        }
    }
    
    deinit {
        vkDeviceWaitIdle(self.device)
        self.queueCompletionHandlerSemaphore?.destroy(device: self)
        self.queueCompletionHandlerFence?.destroy(device: self)
        self.queueCompletionHandlerSemaphore = nil
        self.queueCompletionHandlerFence = nil

        if let pipelineCache = self.pipelineCache {
            vkDestroyPipelineCache(self.device, pipelineCache, self.allocationCallbacks)
            self.pipelineCache = nil
        }
        vkDestroyDevice(self.device, self.allocationCallbacks)
        Log.debug("VulkanGraphicsDevice destroyed.")
    }

    public func loadPipelineCache() {
        if let pipelineCache = self.pipelineCache {
            vkDestroyPipelineCache(self.device, pipelineCache, self.allocationCallbacks)
            self.pipelineCache = nil
        }

        var pipelineCacheCreateInfo = VkPipelineCacheCreateInfo()
        pipelineCacheCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO

        // load from user-data
        if let data = UserDefaults.standard.data(forKey: pipelineCacheDataKey) {
            let length = data.count
            if length > 0 {
                let buffer: UnsafeMutablePointer<UInt8> = .allocate(capacity: length)
                defer { buffer.deallocate() }

                data.copyBytes(to: buffer, count: length)
                pipelineCacheCreateInfo.initialDataSize = length
                pipelineCacheCreateInfo.pInitialData = UnsafeRawPointer(buffer)
            }
        }
        var pipelineCache: VkPipelineCache? = nil
        let err = vkCreatePipelineCache(self.device, &pipelineCacheCreateInfo, self.allocationCallbacks, &pipelineCache)
        if err == VK_SUCCESS {
            self.pipelineCache = pipelineCache
        } else {
            Log.err("vkCreatePipelineCache failed: \(err.rawValue)")
        }
    }

    public func savePipelineCache() {
        if let pipelineCache = self.pipelineCache {
            var result: VkResult = VK_SUCCESS
            var buffer: UnsafeMutableRawPointer? = nil
            var dataLength: Int = 0
            repeat {
                result = vkGetPipelineCacheData(self.device, pipelineCache, &dataLength, nil)
                if result != VK_SUCCESS {
                    break
                }
                if dataLength <= 0 {
                    break
                }
                buffer = .allocate(byteCount: dataLength, alignment: 1)
                result = vkGetPipelineCacheData(self.device, pipelineCache, &dataLength, buffer)
                if result != VK_SUCCESS {
                    break
                }
            } while false

            if result == VK_SUCCESS {
                if let buffer = buffer, dataLength > 0 {
                    let data: Data = .init(bytesNoCopy: buffer, count: dataLength, deallocator: .custom {
                        pointer, size in pointer.deallocate()
                    })
                    UserDefaults.standard.set(data, forKey: pipelineCacheDataKey)
                    UserDefaults.standard.synchronize()

                    Log.info("Vulkan PipelineCache saved \(dataLength) bytes.")
                }
            } else {
                Log.err("vkGetPipelineCacheData failed: \(result.rawValue)")
            }

        } else {
            Log.err("VkPipelineCache is nil")            
        }
    }

    public func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue? {
        var queueFlags: UInt32 = 0
        if flags.contains(.graphics) {
            queueFlags = queueFlags | UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue)
        }
        if flags.contains(.compute) {
            queueFlags = queueFlags | UInt32(VK_QUEUE_COMPUTE_BIT.rawValue)
        }
        var queueMask = UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue | VK_QUEUE_COMPUTE_BIT.rawValue)
        queueMask = queueMask ^ queueFlags

        // find the exact matching queue
        for family in self.queueFamilies {
            if family.properties.queueFlags & queueMask == 0 &&
               family.properties.queueFlags & queueFlags == queueFlags {
                if let queue = family.makeCommandQueue(device: self) {
                    return queue
                }
            }
        }
    	// find any queue that satisfies the condition.
        for family in self.queueFamilies {
            if family.properties.queueFlags & queueFlags == queueFlags {
                if let queue = family.makeCommandQueue(device: self) {
                    return queue
                }
            }
        }
        return nil
    }
    public func makeShaderModule() -> ShaderModule? {
        return nil
    }
    public func makeBindingSet() -> ShaderBindingSet? {
        return nil
    }
    public func makeRenderPipelineState() -> RenderPipelineState? {
        return nil
    }
    public func makeComputePipelineState() -> ComputePipelineState? {
        return nil
    }
    public func makeBuffer() -> Buffer? {
        return nil
    }
    public func makeTexture() -> Texture? {
        return nil
    }
    public func makeSamplerState() -> SamplerState? {
        return nil
    }
    public func makeEvent() -> Event? {
        return nil
    }
    public func makeSemaphore() -> Semaphore? {
        return nil
    }
}
#endif //if ENABLE_VULKAN