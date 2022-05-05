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

    public var autoIncrementTimelineEvent = false

    private struct DescriptorPoolChainMap {
        var poolChainMap: [VulkanDescriptorPoolID: VulkanDescriptorPoolChain] = [:]
        let lock: SpinLock = SpinLock()
    }
    private var descriptorPoolChainMaps: [DescriptorPoolChainMap] = .init(repeating: DescriptorPoolChainMap(), count: 7)

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
        let queuePriorityPointer = unsafePointerCopy(collection: queuePriority, holder: tempHolder)

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
        deviceCreateInfo.pQueueCreateInfos = unsafePointerCopy(collection: queueCreateInfos, holder: tempHolder)
        deviceCreateInfo.pEnabledFeatures = unsafePointerCopy(from: enabledFeatures, holder: tempHolder)

        if deviceExtensions.count > 0 {
            deviceCreateInfo.enabledExtensionCount = UInt32(deviceExtensions.count)
            deviceCreateInfo.ppEnabledExtensionNames = unsafePointerCopy(collection: deviceExtensions.map {
                unsafePointerCopy(string: $0, holder: tempHolder)
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
            Log.err("vkCreateDevice Failed: \(err)")
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
        for maps in self.descriptorPoolChainMaps {
            assert(maps.poolChainMap.isEmpty)
        }
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
            Log.err("vkCreatePipelineCache failed: \(err)")
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
                Log.err("vkGetPipelineCacheData failed: \(result)")
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
    public func makeShaderModule(from shader: Shader) -> ShaderModule? {
        if shader.spirvData.isEmpty { return nil }

        let maxPushConstantsSize = self.properties.limits.maxPushConstantsSize

        for layout in shader.pushConstantLayouts {
            if layout.offset >= maxPushConstantsSize {
                Log.err("PushConstant offset is out of range. (offset: \(layout.offset), limit: \(maxPushConstantsSize))")
                return nil
            }
            if (layout.offset + layout.size > maxPushConstantsSize) {
                Log.err("PushConstant range exceeded limit. (offset: \(layout.offset), size: \(layout.size), limit: \(maxPushConstantsSize))")
                return nil
            }            
        }

        let threadWorkgroupSize = shader.threadgroupSize
        let maxComputeWorkGroupSize = self.properties.limits.maxComputeWorkGroupSize
        if threadWorkgroupSize.x > maxComputeWorkGroupSize.0 ||
           threadWorkgroupSize.y > maxComputeWorkGroupSize.1 ||
           threadWorkgroupSize.z > maxComputeWorkGroupSize.2 {
            Log.err("Thread-WorkGroup size exceeded limit. Size:(\(threadWorkgroupSize.x), \(threadWorkgroupSize.y), \(threadWorkgroupSize.z)), Limit:(\(maxComputeWorkGroupSize.0), \(maxComputeWorkGroupSize.1), \(maxComputeWorkGroupSize.2))")
            return nil
            }

        var shaderModule: VkShaderModule? = nil
        let stride = MemoryLayout.stride(ofValue: shader.spirvData[0])
        let err: VkResult = shader.spirvData.withUnsafeBufferPointer {
            var shaderModuleCreateInfo = VkShaderModuleCreateInfo()
            shaderModuleCreateInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
            shaderModuleCreateInfo.codeSize = $0.count * stride
            shaderModuleCreateInfo.pCode = $0.baseAddress
            return vkCreateShaderModule(self.device, &shaderModuleCreateInfo, self.allocationCallbacks, &shaderModule)
        }
        if err != VK_SUCCESS {
            Log.err("vkCreateShaderModule failed: \(err)")
            return nil
        }

        switch (shader.stage) {
        case .vertex, .fragment, .compute:  break
        default:
            Log.warn("Unsupported shader type!")
            break
        }
        return VulkanShaderModule(device: self, module: shaderModule!, shader: shader)
    }

    public func makeShaderBindingSet(layout: ShaderBindingSetLayout) -> ShaderBindingSet? {
        let poolID = VulkanDescriptorPoolID(layout: layout)
        if poolID.mask != 0 {
#if DEBUG
            let index: Int = Int(poolID.hash % UInt32(descriptorPoolChainMaps.count))

            synchronizedBy(locking: self.descriptorPoolChainMaps[index].lock) {
                // find matching pool.
                if let chain = self.descriptorPoolChainMaps[index].poolChainMap[poolID] {
                    assert(chain.device! === self)
                    assert(chain.poolID == poolID)
                }
            }
#endif
            // create layout!
            var layoutBindings: [VkDescriptorSetLayoutBinding] = []
            layoutBindings.reserveCapacity(layout.bindings.count)
            for binding in layout.bindings {
                var layoutBinding = VkDescriptorSetLayoutBinding()
                layoutBinding.binding = binding.binding
                layoutBinding.descriptorType = binding.type.vkType()
                layoutBinding.descriptorCount = binding.arrayLength

                // input-attachment is for the fragment shader only! (framebuffer load operation)
                if layoutBinding.descriptorType == VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT &&
                layoutBinding.descriptorCount > 0 {
                    layoutBinding.stageFlags = VkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue)
                } else {
                    layoutBinding.stageFlags = VkShaderStageFlags(VK_SHADER_STAGE_ALL.rawValue)
                }

                //TODO: setup immutable sampler!

                layoutBindings.append(layoutBinding)
            }

            let tempHolder = TemporaryBufferHolder(label: "VulkanGraphicsDevice.makeShaderBindingSet")
            var descriptorSetLayout: VkDescriptorSetLayout? = nil

            var layoutCreateInfo = VkDescriptorSetLayoutCreateInfo()
            layoutCreateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
            layoutCreateInfo.bindingCount = UInt32(layoutBindings.count)
            layoutCreateInfo.pBindings = unsafePointerCopy(collection: layoutBindings, holder: tempHolder)

            var layoutSupport = VkDescriptorSetLayoutSupport()
            layoutSupport.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_SUPPORT
            vkGetDescriptorSetLayoutSupport(device, &layoutCreateInfo, &layoutSupport)
            assert(layoutSupport.supported != 0)

            let err = vkCreateDescriptorSetLayout(self.device, &layoutCreateInfo, self.allocationCallbacks, &descriptorSetLayout)
            if err != VK_SUCCESS {
                Log.err("vkCreateDescriptorSetLayout failed: \(err)")
                return nil
            }
            return VulkanShaderBindingSet(device: self, layout: descriptorSetLayout!, poolID: poolID, layoutCreateInfo: layoutCreateInfo)
        }
        return nil
    }

    public func makeRenderPipelineState(descriptor desc: RenderPipelineDescriptor,
        reflection: UnsafeMutablePointer<PipelineReflection>?) -> RenderPipelineState? {

        var result: VkResult = VK_SUCCESS;

        var pipelineLayout: VkPipelineLayout? = nil
        var renderPass: VkRenderPass? = nil
        var pipeline: VkPipeline? = nil
        var pipelineState: RenderPipelineState? = nil

        defer {
            if pipelineState == nil {
                if let pipelineLayout = pipelineLayout {
                    vkDestroyPipelineLayout(self.device, pipelineLayout, self.allocationCallbacks)
                }
                if let renderPass = renderPass {
                    vkDestroyRenderPass(self.device, renderPass, self.allocationCallbacks)
                }
                if let pipeline = pipeline {
                    vkDestroyPipeline(self.device, pipeline, self.allocationCallbacks)
                }
            }
        }

        return nil
    }
    public func makeComputePipelineState(descriptor desc: ComputePipelineDescriptor,
        reflection: UnsafeMutablePointer<PipelineReflection>?) -> ComputePipelineState? {

        var result: VkResult = VK_SUCCESS
        var pipelineLayout: VkPipelineLayout? = nil
        var pipeline: VkPipeline? = nil
        var pipelineState: ComputePipelineState? = nil

        let tempHolder = TemporaryBufferHolder(label: "VulkanGraphicsDevice.makeComputePipelineState")

        defer {
            // cleanup resources if function failure.
            if pipelineState == nil {
                if let pipelineLayout = pipelineLayout {
                    vkDestroyPipelineLayout(self.device, pipelineLayout, self.allocationCallbacks)
                }
                if let pipeline = pipeline {
                    vkDestroyPipeline(self.device, pipeline, self.allocationCallbacks)
                }
            }
        }

        var pipelineCreateInfo = VkComputePipelineCreateInfo()
        pipelineCreateInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO

        if desc.disableOptimization {
            pipelineCreateInfo.flags |= VkPipelineCreateFlags(VK_PIPELINE_CREATE_DISABLE_OPTIMIZATION_BIT.rawValue)
        }
        if desc.deferCompile {
            // pipelineCreateInfo.flags |= VkPipelineCreateFlags(VK_PIPELINE_CREATE_DEFER_COMPILE_BIT_NV.rawValue)
        }

        assert(desc.computeFunction is VulkanShaderFunction)
        let shader = desc.computeFunction as! VulkanShaderFunction
        let module = shader.module as! VulkanShaderModule
        assert(module.stage == .compute)

        var shaderStageCreateInfo = VkPipelineShaderStageCreateInfo()
        shaderStageCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        shaderStageCreateInfo.stage = module.stage.vkFlagBits()
        shaderStageCreateInfo.module = module.module
        shaderStageCreateInfo.pName = unsafePointerCopy(string: shader.functionName, holder: tempHolder)
        if shader.specializationInfo.mapEntryCount > 0 {
           shaderStageCreateInfo.pSpecializationInfo = unsafePointerCopy(from: shader.specializationInfo, holder: tempHolder)
        }

        pipelineCreateInfo.stage = shaderStageCreateInfo

        pipelineLayout = makePipelineLayout(
            functions: [shader],
            layoutDefaultStageFlags: VkShaderStageFlags(VK_SHADER_STAGE_ALL.rawValue))
        if pipelineLayout == nil { return nil }

        pipelineCreateInfo.layout = pipelineLayout;
        assert(pipelineCreateInfo.stage.stage == VK_SHADER_STAGE_COMPUTE_BIT)

        result = vkCreateComputePipelines(self.device, pipelineCache, 1, &pipelineCreateInfo, self.allocationCallbacks, &pipeline)
        if result != VK_SUCCESS {
            Log.err("vkCreateComputePipelines failed: \(result)")
            return nil
        }

        self.savePipelineCache()

        if let reflection = reflection {
            reflection.pointee.resources = module.resources
        }

        return VulkanComputePipelineState(device: self, pipeline: pipeline!, layout: pipelineLayout!)
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
        var createInfo = VkSemaphoreCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO

        var semaphore: VkSemaphore? = nil
        var typeCreateInfo = VkSemaphoreTypeCreateInfo()
        typeCreateInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO

        if self.autoIncrementTimelineEvent {
            typeCreateInfo.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE
        } else {
            typeCreateInfo.semaphoreType = VK_SEMAPHORE_TYPE_BINARY
        }

        typeCreateInfo.initialValue = 0
        let result: VkResult = withUnsafePointer(to: typeCreateInfo) {
            createInfo.pNext = UnsafeRawPointer($0)
            return vkCreateSemaphore(self.device, &createInfo, self.allocationCallbacks, &semaphore)
        }
        if result != VK_SUCCESS {
            Log.err("vkCreateSemaphore failed: \(result)")
            return nil
        }
        if typeCreateInfo.semaphoreType == VK_SEMAPHORE_TYPE_TIMELINE {
            return VulkanSemaphoreAutoIncrementalTimeline(device: self, semaphore: semaphore!)            
        }
        return VulkanSemaphore(device: self, semaphore: semaphore!)
    }

    public func makeSemaphore() -> Semaphore? {
        var createInfo = VkSemaphoreCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO

        var semaphore: VkSemaphore? = nil
        var typeCreateInfo = VkSemaphoreTypeCreateInfo()
        typeCreateInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO
        typeCreateInfo.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE
        typeCreateInfo.initialValue = 0

        let result: VkResult = withUnsafePointer(to: typeCreateInfo) {
            createInfo.pNext = UnsafeRawPointer($0)
            return vkCreateSemaphore(self.device, &createInfo, self.allocationCallbacks, &semaphore)
        }
        if result != VK_SUCCESS {
            Log.err("vkCreateSemaphore failed: \(result)")
            return nil
        }
        return VulkanTimelineSemaphore(device: self, semaphore: semaphore!)
    }

    func makeDescriptorSet(layout: VkDescriptorSetLayout, poolID: VulkanDescriptorPoolID) -> VulkanDescriptorSet? {
        if poolID.mask != 0 {
            let index: Int = Int(poolID.hash % UInt32(descriptorPoolChainMaps.count))

            self.descriptorPoolChainMaps[index].lock.lock()
            defer {
                self.descriptorPoolChainMaps[index].lock.unlock()
            }

            if self.descriptorPoolChainMaps[index].poolChainMap[poolID] == nil {
                self.descriptorPoolChainMaps[index].poolChainMap[poolID] = VulkanDescriptorPoolChain(device: self, poolID: poolID)
            }
            
            let chain = self.descriptorPoolChainMaps[index].poolChainMap[poolID]!
            assert(chain.device! === self)
            assert(chain.poolID == poolID)

            if let allocationInfo = chain.allocateDescriptorSet(layout: layout) {
                return VulkanDescriptorSet(device: self,
                                           descriptorPool: allocationInfo.descriptorPool,
                                           descriptorSet: allocationInfo.descriptorSet)
            }
        }
        return nil
    }

    func releaseDescriptorSets(_ sets: [VkDescriptorSet], from pool: VulkanDescriptorPool) {
        let poolID = pool.poolID
        assert(poolID.mask != 0)

        guard sets.isEmpty == false else { return }

        let index: Int = Int(poolID.hash % UInt32(descriptorPoolChainMaps.count))

        synchronizedBy(locking: self.descriptorPoolChainMaps[index].lock) {
            pool.release(descriptorSets: sets)
            let chain = self.descriptorPoolChainMaps[index].poolChainMap[poolID]!
            let numPools = chain.cleanup()
            if numPools == 0 {
                self.descriptorPoolChainMaps[index].poolChainMap[poolID] = nil
            }
        }
    }

    private func makePipelineLayout(functions: [ShaderFunction],
                                    layoutDefaultStageFlags: VkShaderStageFlags) -> VkPipelineLayout? {
        var descriptorSetLayouts: [VkDescriptorSetLayout?] = []
        let result = makePipelineLayout(functions: functions,
            descriptorSetLayouts: &descriptorSetLayouts,
            layoutDefaultStageFlags: layoutDefaultStageFlags)

        for setLayout in descriptorSetLayouts {
            assert(setLayout != nil)
            vkDestroyDescriptorSetLayout(self.device, setLayout, self.allocationCallbacks)
        }
        return result
    }

    private func makePipelineLayout(functions: [ShaderFunction],
                                    descriptorSetLayouts: inout [VkDescriptorSetLayout?],
                                    layoutDefaultStageFlags: VkShaderStageFlags) -> VkPipelineLayout? {
        var result: VkResult = VK_SUCCESS
        var numPushConstantRanges = 0

        for fn in functions {
            assert(fn is VulkanShaderFunction)
            let f = fn as! VulkanShaderFunction
            let module = f.module as! VulkanShaderModule

            numPushConstantRanges += module.pushConstantLayouts.count
        }

        var pushConstantRanges: [VkPushConstantRange] = []
        pushConstantRanges.reserveCapacity(numPushConstantRanges)

        var maxDescriptorBindings = 0   // maximum number of descriptor
        var maxDescriptorSets: UInt32 = 0       // maximum number of sets

        for fn in functions {
            let f = fn as! VulkanShaderFunction
            let module = f.module as! VulkanShaderModule

            for layout in module.pushConstantLayouts {
                if layout.size > 0 {
                    var range = VkPushConstantRange()
                    range.stageFlags = module.stage.vkFlags()
                    range.offset = layout.offset
                    range.size = layout.size
                    pushConstantRanges.append(range)
                }
            }

            // calculate max descriptor bindings a set
            if module.descriptors.isEmpty == false {
                maxDescriptorSets = max(maxDescriptorSets, module.descriptors.last!.set + 1)
                maxDescriptorBindings = max(maxDescriptorBindings, module.descriptors.count)
            }
        }

        // setup descriptor layout
        var descriptorBindings: [VkDescriptorSetLayoutBinding] = []
        descriptorBindings.reserveCapacity(maxDescriptorBindings)

        for setIndex in 0..<maxDescriptorSets {
            descriptorBindings.removeAll(keepingCapacity: true)
            for fn in functions {
                let f = fn as! VulkanShaderFunction
                let module = f.module as! VulkanShaderModule

                for desc in module.descriptors {
                    if desc.set > setIndex { break }

                    if desc.set == setIndex {
                        var newBinding = true

                        for i in 0..<descriptorBindings.count {
                            var b = descriptorBindings[i]
                            if b.binding == desc.binding {  // exist binding!! (conflict)
                                newBinding = false
                                if b.descriptorType == desc.type.vkType() {
                                    b.descriptorCount = max(b.descriptorCount, desc.count)
                                    b.stageFlags |= module.stage.vkFlags()
                                    descriptorBindings[i] = b // udpate.
                                } else {
                                    Log.err("descriptor binding conflict! (set=\(setIndex), binding=\(desc.binding))")
                                    return nil
                                }
                            }
                        }
                        if newBinding {
                            let binding = VkDescriptorSetLayoutBinding(
                                binding: desc.binding,
                                descriptorType: desc.type.vkType(),
                                descriptorCount: desc.count,
                                stageFlags: layoutDefaultStageFlags | module.stage.vkFlags(), 
                                pImmutableSamplers: nil  /* VkSampler* pImmutableSamplers */
                            )
                            descriptorBindings.append(binding)
                        }
                    }
                }
            }
            // create descriptor set (setIndex) layout
            var setLayout: VkDescriptorSetLayout? = nil
            result = descriptorBindings.withUnsafeBufferPointer {
                var setLayoutCreateInfo = VkDescriptorSetLayoutCreateInfo()
                setLayoutCreateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
                setLayoutCreateInfo.bindingCount = UInt32($0.count)
                setLayoutCreateInfo.pBindings = $0.baseAddress

                var layoutSupport = VkDescriptorSetLayoutSupport()
                layoutSupport.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_SUPPORT
                vkGetDescriptorSetLayoutSupport(device, &setLayoutCreateInfo, &layoutSupport);
                assert(layoutSupport.supported != 0)

                return vkCreateDescriptorSetLayout(self.device, &setLayoutCreateInfo, self.allocationCallbacks, &setLayout)
            }
            if result != VK_SUCCESS {
                Log.err("vkCreateDescriptorSetLayout failed: \(result)")
                return nil
            }
            descriptorSetLayouts.append(setLayout!)
            descriptorBindings.removeAll(keepingCapacity: true)
        }

        var pipelineLayout: VkPipelineLayout? = nil
        result = descriptorSetLayouts.withUnsafeBufferPointer {
            var pipelineLayoutCreateInfo = VkPipelineLayoutCreateInfo()
            pipelineLayoutCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
            pipelineLayoutCreateInfo.setLayoutCount = UInt32($0.count)
            pipelineLayoutCreateInfo.pSetLayouts = $0.baseAddress
            return pushConstantRanges.withUnsafeBufferPointer {
                pipelineLayoutCreateInfo.pushConstantRangeCount = UInt32($0.count)
                pipelineLayoutCreateInfo.pPushConstantRanges = $0.baseAddress

                return vkCreatePipelineLayout(self.device, &pipelineLayoutCreateInfo, self.allocationCallbacks, &pipelineLayout)
            }
        }
        if result != VK_SUCCESS {
            Log.err("ERROR: vkCreatePipelineLayout failed: \(result)")
            return nil
        }
        return pipelineLayout
    }
}
#endif //if ENABLE_VULKAN