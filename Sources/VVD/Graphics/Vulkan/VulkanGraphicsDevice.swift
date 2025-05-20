//
//  File: VulkanGraphicsDevice.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

private let pipelineCacheDataKey = "_SavedSystemStates.Vulkan.PipelineCacheData"

extension VkSampleCountFlagBits {
    init?(from value: Int) {
        switch Int32(value) {
        case VK_SAMPLE_COUNT_1_BIT.rawValue: self = VK_SAMPLE_COUNT_1_BIT
        case VK_SAMPLE_COUNT_2_BIT.rawValue: self = VK_SAMPLE_COUNT_2_BIT
        case VK_SAMPLE_COUNT_4_BIT.rawValue: self = VK_SAMPLE_COUNT_4_BIT
        case VK_SAMPLE_COUNT_8_BIT.rawValue: self = VK_SAMPLE_COUNT_8_BIT
        case VK_SAMPLE_COUNT_16_BIT.rawValue: self = VK_SAMPLE_COUNT_16_BIT
        case VK_SAMPLE_COUNT_32_BIT.rawValue: self = VK_SAMPLE_COUNT_32_BIT
        case VK_SAMPLE_COUNT_64_BIT.rawValue: self = VK_SAMPLE_COUNT_64_BIT
        default: return nil
        }
    }
}

final class VulkanGraphicsDevice: GraphicsDevice, @unchecked Sendable {

    var name: String

    let instance: VulkanInstance
    let physicalDevice: VulkanPhysicalDeviceDescription

    let device: VkDevice
    var allocationCallbacks: UnsafePointer<VkAllocationCallbacks>? { self.instance.allocationCallbacks }

    var properties: VkPhysicalDeviceProperties { self.physicalDevice.properties }
    var features: VkPhysicalDeviceFeatures { self.physicalDevice.features }

    var extensionProc = VulkanDeviceExtensions()

    let queueFamilies: [VulkanQueueFamily]
    let deviceMemoryTypes: [VkMemoryType]
    let deviceMemoryHeaps: [VkMemoryHeap]
    private var memoryPools: [VulkanMemoryPool]

    private var pipelineCache: VkPipelineCache?

    private struct FenceCallback {
        let fence: VkFence
        let operation: @Sendable () -> Void
    }
    private var pendingFenceCallbacks: [FenceCallback] = []
    private var reusableFences: [VkFence] = []
    private var numberOfFences: UInt = 0
    private var fenceCompletionLock = NSLock()

    var autoIncrementTimelineEvent = false

    private struct DescriptorPoolChainMap {
        var poolChainMap: [VulkanDescriptorPoolID: VulkanDescriptorPoolChain] = [:]
        let lock = NSLock()
    }
    private var descriptorPoolChainMaps: [DescriptorPoolChainMap] = .init(repeating: DescriptorPoolChainMap(), count: 7)
    private var task: Task<Void, Never>?

    init?(instance: VulkanInstance,
          physicalDevice: VulkanPhysicalDeviceDescription,
          requiredExtensions: [String],
          optionalExtensions: [String]) {

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
            Log.error("Error: No queues in PhysicalDevice")
            return nil
        }

        var requiredExtensions = requiredExtensions
        requiredExtensions.append(VK_KHR_SWAPCHAIN_EXTENSION_NAME)
        // requiredExtensions.append(VK_KHR_MAINTENANCE1_EXTENSION_NAME)                // vulkan 1.1
        // requiredExtensions.append(VK_KHR_TIMELINE_SEMAPHORE_EXTENSION_NAME)          // vulkan 1.2
        // requiredExtensions.append(VK_KHR_SYNCHRONIZATION_2_EXTENSION_NAME)           // vulkan 1.3
        // requiredExtensions.append(VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME)           // vulkan 1.3
        // requiredExtensions.append(VK_EXT_EXTENDED_DYNAMIC_STATE_EXTENSION_NAME)      // vulkan 1.3
        // requiredExtensions.append(VK_EXT_EXTENDED_DYNAMIC_STATE_2_EXTENSION_NAME)    // vulkan 1.3
        // requiredExtensions.append(VK_EXT_EXTENDED_DYNAMIC_STATE_3_EXTENSION_NAME)    

        //var optionalExtensions = optionalExtensions
        // optionalExtensions.append(VK_KHR_MAINTENANCE_2_EXTENSION_NAME)   // vulkan 1.1
        // optionalExtensions.append(VK_KHR_MAINTENANCE_3_EXTENSION_NAME)   // vulkan 1.1
        // optionalExtensions.append(VK_KHR_MAINTENANCE_4_EXTENSION_NAME)   // vulkan 1.1

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

        if deviceExtensions.isEmpty == false {
            deviceCreateInfo.enabledExtensionCount = UInt32(deviceExtensions.count)
            deviceCreateInfo.ppEnabledExtensionNames = unsafePointerCopy(collection: deviceExtensions.map {
                unsafePointerCopy(string: $0, holder: tempHolder)
            }, holder: tempHolder)
        }

        let v11Features = physicalDevice.v11Features
        let v12Features = physicalDevice.v12Features
        let v13Features = physicalDevice.v13Features
        appendNextChain(&deviceCreateInfo, unsafePointerCopy(from: v11Features, holder: tempHolder))
        appendNextChain(&deviceCreateInfo, unsafePointerCopy(from: v12Features, holder: tempHolder))
        appendNextChain(&deviceCreateInfo, unsafePointerCopy(from: v13Features, holder: tempHolder))

        if deviceExtensions.contains(VK_EXT_EXTENDED_DYNAMIC_STATE_3_EXTENSION_NAME) {
            // VK_EXT_extended_dynamic_state
            var features = VkPhysicalDeviceExtendedDynamicState3FeaturesEXT()
            features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT
            features.extendedDynamicState3DepthClampEnable = VK_TRUE
            features.extendedDynamicState3PolygonMode = VK_TRUE
            features.extendedDynamicState3DepthClipEnable = VK_TRUE
            appendNextChain(&deviceCreateInfo, unsafePointerCopy(from: features, holder: tempHolder))
        }

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
        self.memoryPools = []
        
        self.queueFamilies = queueCreateInfos.map {
            var supportPresentation = false
#if VK_USE_PLATFORM_WIN32_KHR
            supportPresentation = instance.extensionProc
                .vkGetPhysicalDeviceWin32PresentationSupportKHR?(
                    physicalDevice.device,
                    $0.queueFamilyIndex) ?? VK_FALSE
                != VK_FALSE
#endif
#if VK_USE_PLATFORM_ANDROID_KHR
            supportPresentation = true  // always true on Android
#endif
#if VK_USE_PLATFORM_WAYLAND_KHR
            if let display = (WaylandApplication.shared as? WaylandApplication)?.display {
                supportPresentation = instance.extensionProc
                    .vkGetPhysicalDeviceWaylandPresentationSupportKHR?(
                        physicalDevice.device,
                        $0.queueFamilyIndex,
                        display) ?? VK_FALSE
                    != VK_FALSE
            }
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

        // init memory pools
        let memoryAllocationContext = VulkanMemoryAllocationContext(device: self.device) {
            instance.allocationCallbacks
        }
        self.memoryPools = self.deviceMemoryTypes.enumerated().map { index, type in
            VulkanMemoryPool(context: memoryAllocationContext,
                             typeIndex: UInt32(index),
                             flags: type.propertyFlags,
                             heap: self.deviceMemoryHeaps[Int(type.heapIndex)])
        }

        self.loadPipelineCache()

        self.task = .detached(priority: .background) { [weak self] in
            let taskID = UUID()
            detachedServiceTasks.withLock { $0[taskID] = "VulkanGraphicsDevice Helper task" }
            defer {
                detachedServiceTasks.withLock { $0[taskID] = nil }
            }

            Log.info("VulkanGraphicsDevice Helper task is started.")

            var err: VkResult = VK_SUCCESS
            var fences: [VkFence?] = []
            var waitingFences: [FenceCallback] = []
            var completionHandlers: [@Sendable ()->Void] = []

            let fenceWaitInterval = 0.01
            var timer = TickCounter.now

            mainLoop: while true {
                guard let self = self else { break }
                if Task.isCancelled { break }

                self.fenceCompletionLock.withLock {
                    waitingFences.append(contentsOf: self.pendingFenceCallbacks)
                    self.pendingFenceCallbacks.removeAll(keepingCapacity: true)
                }

                if waitingFences.isEmpty == false {
                    fences.removeAll(keepingCapacity: true)
                    fences.reserveCapacity(waitingFences.count)
                    waitingFences.forEach { fences.append($0.fence) }

                    err = vkWaitForFences(self.device, UInt32(fences.count), fences, VK_FALSE, 0)
                    fences.removeAll(keepingCapacity: true)

                    if err == VK_SUCCESS {
                        var waitingFencesCopy: [FenceCallback] = []
                        waitingFencesCopy.reserveCapacity(waitingFences.count)

                        for cb in waitingFences {
                            if vkGetFenceStatus(self.device, cb.fence) == VK_SUCCESS {
                                fences.append(cb.fence)
                                completionHandlers.append(cb.operation)
                            } else {
                                waitingFencesCopy.append(cb)  // fence is not ready (unsignaled)
                            }
                        }
                        // save unsignaled fences
                        waitingFences = waitingFencesCopy

                        // reset signaled fences
                        if fences.count > 0 {
                            err = vkResetFences(self.device, UInt32(fences.count), fences)
                            if err != VK_SUCCESS {
                                Log.err("vkResetFences failed: \(err)")
                                assertionFailure("vkResetFences failed: \(err)")
                            }
                        }
                    } else if err != VK_TIMEOUT {
                        Log.err("vkWaitForFences failed: \(err)")
                        assertionFailure("vkWaitForFences failed: \(err)")
                    }

                    if completionHandlers.count > 0 {
                        let dispatchQueue = DispatchQueue.global()
                        for handler in completionHandlers {
                            dispatchQueue.async { handler() }
                        }
                        completionHandlers.removeAll(keepingCapacity: true)
                    }

                    if fences.count > 0 {
                        self.fenceCompletionLock.withLock {
                            self.reusableFences.append(contentsOf: fences.compactMap{ $0 })
                        }
                        fences.removeAll(keepingCapacity: true)
                    }

                    if err == VK_TIMEOUT {
                        let t = fenceWaitInterval - timer.elapsed
                        if t > 0 {
                            do {
                                try await Task.sleep(until: .now + .seconds(t), clock: .suspending)
                            } catch {
                                break mainLoop
                            }
                        }
                    }
                    timer.reset()
                } else {
                    await Task.yield()
                }
            }
            assert(completionHandlers.isEmpty, "completionHandlers must be empty!")
            Log.info("VulkanGraphicsDevice Helper task is finished.")
        }
    }
    
    deinit {
        //Log.debug("VulkanGraphicsDevice is being destroyed.")

        self.task?.cancel()

        for maps in self.descriptorPoolChainMaps {
            maps.poolChainMap.forEach{
                $0.value.descriptorPools.forEach { (pool) in
                    assert(pool.numAllocatedSets == 0)
                    vkDestroyDescriptorPool(self.device, pool.pool, self.allocationCallbacks)
                }
            }
            // assert(maps.poolChainMap.isEmpty)
        }
        vkDeviceWaitIdle(self.device)

        assert(self.pendingFenceCallbacks.isEmpty, "CompletionHandler must be empty!")

        if self.reusableFences.count != self.numberOfFences {
            Log.warn("Some fences were not returned. \(self.reusableFences.count)/\(self.numberOfFences)")
        }
        for fence in self.reusableFences {
            vkDestroyFence(self.device, fence, self.allocationCallbacks)
        }

        // destroy pipeline cache
        if let pipelineCache = self.pipelineCache {
            vkDestroyPipelineCache(self.device, pipelineCache, self.allocationCallbacks)
            self.pipelineCache = nil
        }
        // destroy memory pools
        self.memoryPools.removeAll()

        vkDestroyDevice(self.device, self.allocationCallbacks)
        Log.debug("VulkanGraphicsDevice destroyed.")
    }

    func loadPipelineCache() {
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

    func savePipelineCache() {
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

    private func indexOfMemoryType(typeBits: UInt32, properties: VkMemoryPropertyFlags) -> Int? {
        for i in 0..<self.deviceMemoryTypes.count {
            if (typeBits & (1 << i)) != 0 && (self.deviceMemoryTypes[i].propertyFlags & properties) == properties {
                    return i
            }
        }
        // assertionFailure("VulkanGraphicsDevice error: Unknown memory type!")
        // return UInt32.max
        return nil
    }

    func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue? {
        var queueFlags: UInt32 = 0
        if flags.contains(.render) {
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

    func makeShaderModule(from shader: Shader) -> ShaderModule? {
        if shader.validate() == false { return nil }

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
        let err: VkResult = shader.spirvData!.withUnsafeBytes {
            var shaderModuleCreateInfo = VkShaderModuleCreateInfo()
            shaderModuleCreateInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
            shaderModuleCreateInfo.codeSize = $0.count
            shaderModuleCreateInfo.pCode = $0.baseAddress?.assumingMemoryBound(to: UInt32.self)
            return vkCreateShaderModule(self.device, &shaderModuleCreateInfo, self.allocationCallbacks, &shaderModule)
        }
        if err != VK_SUCCESS {
            Log.err("vkCreateShaderModule failed: \(err)")
            return nil
        }

        switch shader.stage {
        case .vertex, .fragment, .compute:  break
        default:
            Log.warn("Unsupported shader type!")
            break
        }
        return VulkanShaderModule(device: self, module: shaderModule!, shader: shader)
    }

    func makeShaderBindingSet(layout: ShaderBindingSetLayout) -> ShaderBindingSet? {
        let poolID = VulkanDescriptorPoolID(layout: layout)
        if poolID.mask != 0 {
#if DEBUG
            let index: Int = Int(poolID.hash % UInt32(descriptorPoolChainMaps.count))

            self.descriptorPoolChainMaps[index].lock.withLock {
                // find matching pool.
                if let chain = self.descriptorPoolChainMaps[index].poolChainMap[poolID] {
                    assert(chain.device === self)
                    assert(chain.poolID == poolID)
                }
            }
#endif
            // create layout!
            let layoutBindings: [VkDescriptorSetLayoutBinding] = layout.bindings.map { binding in
                var layoutBinding = VkDescriptorSetLayoutBinding()
                layoutBinding.binding = UInt32(binding.binding)
                layoutBinding.descriptorType = binding.type.vkType()
                layoutBinding.descriptorCount = UInt32(binding.arrayLength)

                // input-attachment is for the fragment shader only! (framebuffer load operation)
                if layoutBinding.descriptorType == VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT &&
                layoutBinding.descriptorCount > 0 {
                    layoutBinding.stageFlags = VkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue)
                } else {
                    layoutBinding.stageFlags = VkShaderStageFlags(VK_SHADER_STAGE_ALL.rawValue)
                }
                //TODO: setup immutable sampler!
                return layoutBinding
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

    func makeRenderPipelineState(descriptor desc: RenderPipelineDescriptor,
        reflection: UnsafeMutablePointer<PipelineReflection>?) -> RenderPipelineState? {

        var result: VkResult = VK_SUCCESS

        var pipelineLayout: VkPipelineLayout? = nil
        var pipeline: VkPipeline? = nil
        var pipelineState: RenderPipelineState? = nil

        defer {
            if pipelineState == nil {
                if let pipelineLayout = pipelineLayout {
                    vkDestroyPipelineLayout(self.device, pipelineLayout, self.allocationCallbacks)
                }
                if let pipeline = pipeline {
                    vkDestroyPipeline(self.device, pipeline, self.allocationCallbacks)
                }
            }
        }

        for attachment in desc.colorAttachments {
            if attachment.pixelFormat.isColorFormat == false {
                Log.err("Invalid attachment pixel format: \(attachment.pixelFormat)")
                return nil
            }
        }
        let colorAttachmentCount = desc.colorAttachments.reduce(0) {
            max($0, $1.index + 1)            
        }
        if colorAttachmentCount > self.properties.limits.maxColorAttachments {
            Log.err("The number of colors attached exceeds the device limit. (\(colorAttachmentCount) > \(self.properties.limits.maxColorAttachments))")
            return nil
        }

        if let vs = desc.vertexFunction {
            assert(vs.stage == .vertex)
        }
        if let fs = desc.fragmentFunction {
            assert(fs.stage == .fragment)
        }

        let tempHolder = TemporaryBufferHolder(label: "VulkanGraphicsDevice.makeRenderPipelineState")

        var pipelineCreateInfo = VkGraphicsPipelineCreateInfo()
        pipelineCreateInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO

        // shader stages
        let shaderFunctions = [desc.vertexFunction, desc.fragmentFunction].compactMap { $0 }
        let shaderStageCreateInfos: [VkPipelineShaderStageCreateInfo] = shaderFunctions.map { fn in
            assert(fn is VulkanShaderFunction)
            let fn = fn as! VulkanShaderFunction
            let module = fn.module

            var shaderStageCreateInfo = VkPipelineShaderStageCreateInfo()
            shaderStageCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
            shaderStageCreateInfo.stage = module.stage.vkFlagBits()
            shaderStageCreateInfo.module = module.module
            shaderStageCreateInfo.pName = unsafePointerCopy(string: fn.functionName, holder: tempHolder)
            if fn.specializationInfo.mapEntryCount > 0 {
                shaderStageCreateInfo.pSpecializationInfo = unsafePointerCopy(from: fn.specializationInfo, holder: tempHolder)
            }
            return shaderStageCreateInfo
        }
        pipelineCreateInfo.stageCount = UInt32(shaderStageCreateInfos.count)
        pipelineCreateInfo.pStages = unsafePointerCopy(collection: shaderStageCreateInfos, holder: tempHolder)

        pipelineLayout = makePipelineLayout(
            functions: shaderFunctions,
            layoutDefaultStageFlags: VkShaderStageFlags(VK_SHADER_STAGE_ALL.rawValue))
        if pipelineLayout == nil { return nil }
        pipelineCreateInfo.layout = pipelineLayout

        // vertex input state
        let vertexBindingDescriptions: [VkVertexInputBindingDescription] = desc.vertexDescriptor.layouts.enumerated().map {
            index, layout in
            var binding = VkVertexInputBindingDescription()
            binding.binding = UInt32(index)
            binding.stride = UInt32(layout.stride)
            binding.inputRate = switch layout.stepRate {
            case .vertex:   VK_VERTEX_INPUT_RATE_VERTEX
            case .instance: VK_VERTEX_INPUT_RATE_INSTANCE
            }
            return binding
        }
        let vertexAttributeDescriptions: [VkVertexInputAttributeDescription] = desc.vertexDescriptor.attributes.map {
            var attr = VkVertexInputAttributeDescription()
            attr.location = UInt32($0.location)
            attr.binding = UInt32($0.bufferIndex)
            attr.format = $0.format.vkFormat()
            attr.offset = UInt32($0.offset)
            return attr
        }
        var vertexInputState = VkPipelineVertexInputStateCreateInfo()
        vertexInputState.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
        vertexInputState.vertexBindingDescriptionCount = UInt32(vertexBindingDescriptions.count)
        vertexInputState.pVertexBindingDescriptions = unsafePointerCopy(collection: vertexBindingDescriptions, holder: tempHolder)
        vertexInputState.vertexAttributeDescriptionCount = UInt32(vertexAttributeDescriptions.count)
        vertexInputState.pVertexAttributeDescriptions = unsafePointerCopy(collection: vertexAttributeDescriptions, holder: tempHolder)
        pipelineCreateInfo.pVertexInputState = unsafePointerCopy(from: vertexInputState, holder: tempHolder)

        // input assembly
        var inputAssemblyState = VkPipelineInputAssemblyStateCreateInfo()
        inputAssemblyState.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
        inputAssemblyState.topology = switch desc.primitiveTopology {
        case .point:            VK_PRIMITIVE_TOPOLOGY_POINT_LIST
        case .line:             VK_PRIMITIVE_TOPOLOGY_LINE_LIST
        case .lineStrip:        VK_PRIMITIVE_TOPOLOGY_LINE_STRIP
        case .triangle:         VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
        case .triangleStrip:    VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP
        }
        pipelineCreateInfo.pInputAssemblyState = unsafePointerCopy(from: inputAssemblyState, holder: tempHolder)

        // setup viewport
        var viewportState = VkPipelineViewportStateCreateInfo()
        viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
        viewportState.viewportCount = 1
        viewportState.scissorCount = 1
        pipelineCreateInfo.pViewportState = unsafePointerCopy(from: viewportState, holder: tempHolder)

        // rasterization state
        var rasterizationState = VkPipelineRasterizationStateCreateInfo()
        rasterizationState.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
        rasterizationState.polygonMode = VK_POLYGON_MODE_FILL
        if desc.triangleFillMode == .lines {
            if self.features.fillModeNonSolid != 0 {
                rasterizationState.polygonMode = VK_POLYGON_MODE_LINE
            } else {
                Log.warn("VulkanGraphicsDevice.\(#function): PolygonFillMode not supported for this hardware.")
            }
        }

        rasterizationState.cullMode = VkCullModeFlags(VK_CULL_MODE_NONE.rawValue)
        rasterizationState.frontFace = VK_FRONT_FACE_CLOCKWISE

        rasterizationState.depthClampEnable = VK_FALSE
        rasterizationState.rasterizerDiscardEnable = desc.rasterizationEnabled ? VK_FALSE : VK_TRUE
        rasterizationState.depthBiasEnable = VK_FALSE
        rasterizationState.lineWidth = 1.0
        pipelineCreateInfo.pRasterizationState = unsafePointerCopy(from: rasterizationState, holder: tempHolder)

        // setup multisampling
        if let sampleCount = VkSampleCountFlagBits(from: desc.rasterSampleCount) {
            var multisampleState = VkPipelineMultisampleStateCreateInfo()
            multisampleState.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
            multisampleState.rasterizationSamples = sampleCount
            multisampleState.pSampleMask = nil
            pipelineCreateInfo.pMultisampleState = unsafePointerCopy(from: multisampleState, holder: tempHolder)
        } else {
            Log.err("VulkanGraphicsDevice.makeRenderPipeline(): Invalid sample count! (\(desc.rasterSampleCount))")
            return nil
        }

        // setup depth-stencil
        var depthStencilState = VkPipelineDepthStencilStateCreateInfo()
        depthStencilState.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
        depthStencilState.depthTestEnable = VK_FALSE
        depthStencilState.depthWriteEnable = VK_FALSE
        depthStencilState.depthCompareOp = VK_COMPARE_OP_ALWAYS
        depthStencilState.depthBoundsTestEnable = VK_FALSE
        depthStencilState.minDepthBounds = 0.0
        depthStencilState.maxDepthBounds = 1.0
        depthStencilState.front = VkStencilOpState(failOp: VK_STENCIL_OP_KEEP,
                                                   passOp: VK_STENCIL_OP_KEEP,
                                                   depthFailOp: VK_STENCIL_OP_KEEP,
                                                   compareOp: VK_COMPARE_OP_ALWAYS,
                                                   compareMask: 0xffffffff,
                                                   writeMask: 0xffffffff,
                                                   reference: 0)
        depthStencilState.back = VkStencilOpState(failOp: VK_STENCIL_OP_KEEP,
                                                   passOp: VK_STENCIL_OP_KEEP,
                                                   depthFailOp: VK_STENCIL_OP_KEEP,
                                                   compareOp: VK_COMPARE_OP_ALWAYS,
                                                   compareMask: 0xffffffff,
                                                   writeMask: 0xffffffff,
                                                   reference: 0)
        depthStencilState.stencilTestEnable = VK_FALSE
        pipelineCreateInfo.pDepthStencilState = unsafePointerCopy(from: depthStencilState, holder: tempHolder)

        // dynamic states
        let dynamicStateEnables: [VkDynamicState] = [
            VK_DYNAMIC_STATE_VIEWPORT,
            VK_DYNAMIC_STATE_SCISSOR,
            VK_DYNAMIC_STATE_LINE_WIDTH,
            VK_DYNAMIC_STATE_DEPTH_BIAS,
            VK_DYNAMIC_STATE_BLEND_CONSTANTS,
            VK_DYNAMIC_STATE_DEPTH_BOUNDS,
            VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK,
            VK_DYNAMIC_STATE_STENCIL_WRITE_MASK,
            VK_DYNAMIC_STATE_STENCIL_REFERENCE,

            // Provided by VK_VERSION_1_3
            VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE,
            VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE,
            VK_DYNAMIC_STATE_DEPTH_COMPARE_OP,
            VK_DYNAMIC_STATE_DEPTH_BOUNDS_TEST_ENABLE,
            VK_DYNAMIC_STATE_STENCIL_TEST_ENABLE,
            VK_DYNAMIC_STATE_STENCIL_OP,

            // VK_EXT_extended_dynamic_state
            VK_DYNAMIC_STATE_CULL_MODE,
            VK_DYNAMIC_STATE_FRONT_FACE,
            // VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY, //required: VkPhysicalDeviceExtendedDynamicState3PropertiesEXT.dynamicPrimitiveTopologyUnrestricted

            // VK_EXT_extended_dynamic_state3
            // VK_DYNAMIC_STATE_POLYGON_MODE_EXT,
            // VK_DYNAMIC_STATE_DEPTH_CLAMP_ENABLE_EXT
            // VK_DYNAMIC_STATE_DEPTH_CLIP_ENABLE_EXT
        ]
        var dynamicState = VkPipelineDynamicStateCreateInfo()
        dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
        dynamicState.pDynamicStates = unsafePointerCopy(collection: dynamicStateEnables, holder: tempHolder)
        dynamicState.dynamicStateCount = UInt32(dynamicStateEnables.count)
        pipelineCreateInfo.pDynamicState = unsafePointerCopy(from: dynamicState, holder: tempHolder)

        // VK_KHR_dynamic_rendering
        var pipelineRenderingCreateInfo = VkPipelineRenderingCreateInfo()
        pipelineRenderingCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO
        if desc.colorAttachments.isEmpty == false {
            pipelineRenderingCreateInfo.colorAttachmentCount = UInt32(desc.colorAttachments.count)
            pipelineRenderingCreateInfo.pColorAttachmentFormats = unsafePointerCopy(
                collection: desc.colorAttachments.map {
                    $0.pixelFormat.vkFormat()
                }, holder: tempHolder)
        }
        pipelineRenderingCreateInfo.depthAttachmentFormat = VK_FORMAT_UNDEFINED
        pipelineRenderingCreateInfo.stencilAttachmentFormat = VK_FORMAT_UNDEFINED
        // VUID-VkGraphicsPipelineCreateInfo-renderPass-06589
        if desc.depthStencilAttachmentPixelFormat.isDepthFormat {
            pipelineRenderingCreateInfo.depthAttachmentFormat = desc.depthStencilAttachmentPixelFormat.vkFormat()
        }
        if desc.depthStencilAttachmentPixelFormat.isStencilFormat {
            pipelineRenderingCreateInfo.stencilAttachmentFormat = desc.depthStencilAttachmentPixelFormat.vkFormat()
        }
        appendNextChain(&pipelineCreateInfo, unsafePointerCopy(from: pipelineRenderingCreateInfo, holder: tempHolder))

        let blendOperation = { (op: BlendOperation) -> VkBlendOp in
            switch op {
            case .add:                      VK_BLEND_OP_ADD
            case .subtract:                 VK_BLEND_OP_SUBTRACT
            case .reverseSubtract:          VK_BLEND_OP_REVERSE_SUBTRACT
            case .min:                      VK_BLEND_OP_MIN
            case .max:                      VK_BLEND_OP_MAX
            }
        }
        let blendFactor = { (factor: BlendFactor) -> VkBlendFactor in
            switch factor {
            case .zero:                     VK_BLEND_FACTOR_ZERO
            case .one:                      VK_BLEND_FACTOR_ONE
            case .sourceColor:              VK_BLEND_FACTOR_SRC_COLOR
            case .oneMinusSourceColor:      VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR
            case .sourceAlpha:              VK_BLEND_FACTOR_SRC_ALPHA
            case .oneMinusSourceAlpha:      VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
            case .destinationColor:         VK_BLEND_FACTOR_DST_COLOR
            case .oneMinusDestinationColor: VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR
            case .destinationAlpha:         VK_BLEND_FACTOR_DST_ALPHA
            case .oneMinusDestinationAlpha: VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA
            case .sourceAlphaSaturated:     VK_BLEND_FACTOR_SRC_ALPHA_SATURATE
            case .blendColor:               VK_BLEND_FACTOR_CONSTANT_COLOR
            case .oneMinusBlendColor:       VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR
            case .blendAlpha:               VK_BLEND_FACTOR_CONSTANT_ALPHA
            case .oneMinusBlendAlpha:       VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA
            case .source1Color:             VK_BLEND_FACTOR_SRC1_COLOR
            case .oneMinusSource1Color:     VK_BLEND_FACTOR_ONE_MINUS_SRC1_COLOR
            case .source1Alpha:             VK_BLEND_FACTOR_SRC1_ALPHA
            case .oneMinusSource1Alpha:     VK_BLEND_FACTOR_ONE_MINUS_SRC1_ALPHA
            }
        }

        // color blending
        let colorBlendAttachmentStates: [VkPipelineColorBlendAttachmentState] = desc.colorAttachments.map { attachment in
            var blendState = VkPipelineColorBlendAttachmentState()
            blendState.blendEnable = attachment.blendState.enabled ? VK_TRUE : VK_FALSE
            blendState.srcColorBlendFactor = blendFactor(attachment.blendState.sourceRGBBlendFactor)
            blendState.dstColorBlendFactor = blendFactor(attachment.blendState.destinationRGBBlendFactor)
            blendState.colorBlendOp = blendOperation(attachment.blendState.rgbBlendOperation)
            blendState.srcAlphaBlendFactor = blendFactor(attachment.blendState.sourceAlphaBlendFactor)
            blendState.dstAlphaBlendFactor = blendFactor(attachment.blendState.destinationAlphaBlendFactor)
            blendState.alphaBlendOp = blendOperation(attachment.blendState.alphaBlendOperation)

            blendState.colorWriteMask = 0
            if attachment.blendState.writeMask.contains(.red) {
                blendState.colorWriteMask |= VkColorComponentFlags(VK_COLOR_COMPONENT_R_BIT.rawValue)
            }
            if attachment.blendState.writeMask.contains(.green) {
                blendState.colorWriteMask |= VkColorComponentFlags(VK_COLOR_COMPONENT_G_BIT.rawValue)
            }
            if attachment.blendState.writeMask.contains(.blue) {
                blendState.colorWriteMask |= VkColorComponentFlags(VK_COLOR_COMPONENT_B_BIT.rawValue)
            }
            if attachment.blendState.writeMask.contains(.alpha) {
                blendState.colorWriteMask |= VkColorComponentFlags(VK_COLOR_COMPONENT_A_BIT.rawValue)
            }
            return blendState
        }
        var colorBlendState = VkPipelineColorBlendStateCreateInfo()
        colorBlendState.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
        colorBlendState.attachmentCount = UInt32(colorBlendAttachmentStates.count)
        colorBlendState.pAttachments = unsafePointerCopy(collection: colorBlendAttachmentStates, holder: tempHolder)
        pipelineCreateInfo.pColorBlendState = unsafePointerCopy(from: colorBlendState, holder: tempHolder)

        result = vkCreateGraphicsPipelines(self.device, pipelineCache, 1, &pipelineCreateInfo, self.allocationCallbacks, &pipeline)
        if result != VK_SUCCESS {
            Log.err("vkCreateGraphicsPipelines failed: \(result)")
            return nil
        }
        
        self.savePipelineCache()

        if let reflection = reflection {

            var inputAttributes: [ShaderAttribute] = []
            var pushConstantLayouts: [ShaderPushConstantLayout] = []
            var resources: [ShaderResource] = []

            var maxResourceCount = 0
            var maxPushConstantLayoutCount = 0

            for fn in shaderFunctions {
                let fn = fn as! VulkanShaderFunction
                let module = fn.module
                maxResourceCount += module.resources.count
                maxPushConstantLayoutCount += module.pushConstantLayouts.count

                if module.stage == .vertex {
                    inputAttributes = module.inputAttributes.filter(\.enabled)
                }
            }
            resources.reserveCapacity(maxResourceCount)
            pushConstantLayouts.reserveCapacity(maxPushConstantLayoutCount)

            for fn in shaderFunctions {
                let fn = fn as! VulkanShaderFunction
                let module = fn.module

                for res in module.resources {
                    if res.enabled == false { continue }

                    var exist = false
                    for (i, var res2) in resources.enumerated() {
                        if res.set == res2.set && res.binding == res2.binding {
                            assert(res.type == res2.type)
                            res2.stages.insert(ShaderStageFlags(stage:fn.stage))
                            resources[i] = res2
                            exist = true
                            break
                        }
                    }
                    if exist == false {
                        var res = res
                        res.stages = ShaderStageFlags(stage: fn.stage)
                        resources.append(res)
                    }
                }
                for layout in module.pushConstantLayouts {
                    var exist = false
                    for (i, var layout2) in pushConstantLayouts.enumerated() {
                        if layout.offset == layout2.offset && layout.size == layout2.size {
                            layout2.stages.insert(ShaderStageFlags(stage: fn.stage))
                            pushConstantLayouts[i] = layout2
                            exist = true
                            break
                        }
                    }
                    if exist == false {
                        var layout = layout
                        layout.stages = ShaderStageFlags(stage: fn.stage)
                        pushConstantLayouts.append(layout)
                    }
                }
            }

            reflection.pointee.inputAttributes = inputAttributes
            reflection.pointee.resources = resources
            reflection.pointee.pushConstantLayouts = pushConstantLayouts
        }

        pipelineState = VulkanRenderPipelineState(device: self,
                                                  pipeline: pipeline!,
                                                  layout: pipelineLayout!)
        return pipelineState
    }

    func makeComputePipelineState(descriptor desc: ComputePipelineDescriptor,
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

        if desc.computeFunction == nil {
            return nil      // compute function must be provided.
        }

        assert(desc.computeFunction is VulkanShaderFunction)
        let shader = desc.computeFunction as! VulkanShaderFunction
        let module = shader.module //as! VulkanShaderModule
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

        pipelineCreateInfo.layout = pipelineLayout
        assert(pipelineCreateInfo.stage.stage == VK_SHADER_STAGE_COMPUTE_BIT)

        result = vkCreateComputePipelines(self.device, pipelineCache, 1, &pipelineCreateInfo, self.allocationCallbacks, &pipeline)
        if result != VK_SUCCESS {
            Log.err("vkCreateComputePipelines failed: \(result)")
            return nil
        }

        self.savePipelineCache()

        if let reflection = reflection {
            reflection.pointee.inputAttributes = module.inputAttributes
            reflection.pointee.pushConstantLayouts = module.pushConstantLayouts
            reflection.pointee.resources = module.resources
        }

        pipelineState = VulkanComputePipelineState(device: self, pipeline: pipeline!, layout: pipelineLayout!)
        return pipelineState
    }

    func makeDepthStencilState(descriptor desc: DepthStencilDescriptor) -> DepthStencilState? {

        let compareOp = { (fn: CompareFunction) -> VkCompareOp in
            switch fn {
            case .never:            VK_COMPARE_OP_NEVER
            case .less:             VK_COMPARE_OP_LESS
            case .equal:            VK_COMPARE_OP_EQUAL
            case .lessEqual:        VK_COMPARE_OP_LESS_OR_EQUAL
            case .greater:          VK_COMPARE_OP_GREATER
            case .notEqual:         VK_COMPARE_OP_NOT_EQUAL
            case .greaterEqual:     VK_COMPARE_OP_GREATER_OR_EQUAL
            case .always:           VK_COMPARE_OP_ALWAYS
            }
        }
        let stencilOp = { (op: StencilOperation) -> VkStencilOp in
            switch op {
            case .keep:             VK_STENCIL_OP_KEEP
            case .zero:             VK_STENCIL_OP_ZERO
            case .replace:          VK_STENCIL_OP_REPLACE
            case .incrementClamp:   VK_STENCIL_OP_INCREMENT_AND_CLAMP
            case .decrementClamp:   VK_STENCIL_OP_DECREMENT_AND_CLAMP
            case .invert:           VK_STENCIL_OP_INVERT
            case .incrementWrap:    VK_STENCIL_OP_INCREMENT_AND_WRAP
            case .decrementWrap:    VK_STENCIL_OP_DECREMENT_AND_WRAP
            }
        }
        let stencilOpState = { (stencil: StencilDescriptor) -> VkStencilOpState in
            VkStencilOpState(
                failOp: stencilOp(stencil.stencilFailureOperation),
                passOp: stencilOp(stencil.depthStencilPassOperation),
                depthFailOp: stencilOp(stencil.depthFailOperation),
                compareOp: compareOp(stencil.stencilCompareFunction),
                compareMask: stencil.readMask,
                writeMask: stencil.writeMask,
                reference: 0) // use dynamic state (VK_DYNAMIC_STATE_STENCIL_REFERENCE)
        }

        let depthStencilState = VulkanDepthStencilState(device: self)
        depthStencilState.depthTestEnable = VK_TRUE
        depthStencilState.depthWriteEnable = desc.isDepthWriteEnabled ? VK_TRUE : VK_FALSE
        depthStencilState.depthCompareOp = compareOp(desc.depthCompareFunction)
        depthStencilState.depthBoundsTestEnable = VK_FALSE
        depthStencilState.front = stencilOpState(desc.frontFaceStencil)
        depthStencilState.back  = stencilOpState(desc.backFaceStencil)
        depthStencilState.stencilTestEnable = VK_TRUE
        depthStencilState.minDepthBounds = 0.0
        depthStencilState.maxDepthBounds = 1.0

        if depthStencilState.front.compareOp == VK_COMPARE_OP_ALWAYS &&
           depthStencilState.front.failOp == VK_STENCIL_OP_KEEP &&
           depthStencilState.front.passOp == VK_STENCIL_OP_KEEP &&
           depthStencilState.front.depthFailOp == VK_STENCIL_OP_KEEP &&
           depthStencilState.back.compareOp == VK_COMPARE_OP_ALWAYS &&
           depthStencilState.back.failOp == VK_STENCIL_OP_KEEP &&
           depthStencilState.back.passOp == VK_STENCIL_OP_KEEP &&
           depthStencilState.back.depthFailOp == VK_STENCIL_OP_KEEP {
            depthStencilState.stencilTestEnable = VK_FALSE
        }
        if depthStencilState.depthWriteEnable == VK_FALSE &&
           depthStencilState.depthCompareOp == VK_COMPARE_OP_ALWAYS {
            depthStencilState.depthTestEnable = VK_FALSE
        }
        return depthStencilState
    }

    func makeBuffer(length: Int, storageMode: StorageMode, cpuCacheMode: CPUCacheMode) -> GPUBuffer? {
        guard length > 0 else { return nil }

        var buffer: VkBuffer? = nil
        var memory: VulkanMemoryBlock? = nil

        defer {
            if buffer != nil {
                vkDestroyBuffer(self.device, buffer, self.allocationCallbacks)
            }
            if var memory {
                memory.chunk!.pool.dealloc(&memory)
            }
        }

        var bufferCreateInfo = VkBufferCreateInfo()
        bufferCreateInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        bufferCreateInfo.size = VkDeviceSize(length)
        bufferCreateInfo.usage = 0x1ff
        bufferCreateInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE

        var result: VkResult = vkCreateBuffer(self.device, &bufferCreateInfo, self.allocationCallbacks, &buffer)
        if result != VK_SUCCESS {
            Log.err("vkCreateBuffer failed: \(result)")
            return nil
        }

        let memProperties = switch storageMode {
        case .shared:
            VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue | VK_MEMORY_PROPERTY_HOST_CACHED_BIT.rawValue)
        default:
            VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue)
        }

        var dedicatedRequirements = VkMemoryDedicatedRequirements()
        dedicatedRequirements.sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS
        var memoryRequirements  = VkMemoryRequirements2()
        memoryRequirements.sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2
        withUnsafeMutablePointer(to: &dedicatedRequirements) {
            memoryRequirements.pNext = UnsafeMutableRawPointer($0)
            var memoryRequirementsInfo = VkBufferMemoryRequirementsInfo2()
            memoryRequirementsInfo.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_REQUIREMENTS_INFO_2
            memoryRequirementsInfo.buffer = buffer
            vkGetBufferMemoryRequirements2(device, &memoryRequirementsInfo, &memoryRequirements)
        }

        let memReqs = memoryRequirements.memoryRequirements
        assert(memReqs.size >= bufferCreateInfo.size)
        guard let memoryTypeIndex = self.indexOfMemoryType(typeBits: memReqs.memoryTypeBits, properties: memProperties)
        else {
            fatalError("VulkanGraphicsDevice error: Unknown memory type!")
        }

        if dedicatedRequirements.prefersDedicatedAllocation != 0 {
            memory = self.memoryPools[memoryTypeIndex].allocDedicated(size: memReqs.size, image: nil, buffer: buffer)
        } else {
            memory = self.memoryPools[memoryTypeIndex].alloc(size: memReqs.size)
        }
        guard let mem = memory else {
            Log.error("Memory allocation failed.")
            return nil
        }
        result = vkBindBufferMemory(self.device, buffer, mem.chunk!.memory, mem.offset)
        if result != VK_SUCCESS {
            Log.err("vkBindBufferMemory failed: \(result)")
            return nil
        }

        let bufferObject = VulkanBuffer(device: self, memory: mem, buffer: buffer!, bufferCreateInfo: bufferCreateInfo)
        buffer = nil
        memory = nil

        return VulkanBufferView(buffer: bufferObject)
    }

    func makeTexture(descriptor desc: TextureDescriptor) -> Texture? {
        var image: VkImage? = nil
        var memory: VulkanMemoryBlock? = nil

        defer {
            if image != nil {
                vkDestroyImage(self.device, image, self.allocationCallbacks)
            }
            if var memory {
                memory.chunk!.pool.dealloc(&memory)
            }
        }

        var imageCreateInfo = VkImageCreateInfo()
        imageCreateInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
        imageCreateInfo.flags = UInt32(VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT.rawValue)
        switch desc.textureType {
        case .type1D:
            imageCreateInfo.imageType = VK_IMAGE_TYPE_1D
        case .type2D:
            imageCreateInfo.imageType = VK_IMAGE_TYPE_2D
        case .type3D:
            imageCreateInfo.imageType = VK_IMAGE_TYPE_3D
        case .typeCube:
            imageCreateInfo.imageType = VK_IMAGE_TYPE_2D
            imageCreateInfo.flags |= UInt32(VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT.rawValue)
        default:
            assertionFailure("Invalid texture type!")
            Log.err("VulkanGraphicsDevice.makeTexture(): Invalid texture type!")
            return nil
        }

        if desc.width < 1 || desc.height < 1 || desc.depth < 1 {
            Log.err("Texture dimensions (width, height, depth) value must be greater than or equal to 1.")
            return nil
        }

        imageCreateInfo.arrayLayers = UInt32(max(desc.arrayLength, 1))
        if imageCreateInfo.arrayLayers > 1 && imageCreateInfo.imageType == VK_IMAGE_TYPE_2D {
            imageCreateInfo.flags |= UInt32(VK_IMAGE_CREATE_2D_ARRAY_COMPATIBLE_BIT.rawValue)
        }
        imageCreateInfo.format = desc.pixelFormat.vkFormat()
        assert(imageCreateInfo.format != VK_FORMAT_UNDEFINED, "Unsupported format!")

        imageCreateInfo.extent.width = UInt32(desc.width)
        imageCreateInfo.extent.height = UInt32(desc.height)
        imageCreateInfo.extent.depth = UInt32(desc.depth)
        imageCreateInfo.mipLevels = UInt32(desc.mipmapLevels)

        if let sampleCount = VkSampleCountFlagBits(from: desc.sampleCount) {
            imageCreateInfo.samples = sampleCount
        } else {
            assertionFailure("Invalid sample count!")
            Log.err("VulkanGraphicsDevice.makeTexture(): Invalid sample count! (\(desc.sampleCount))")
            return nil
        }

        imageCreateInfo.tiling = VK_IMAGE_TILING_OPTIMAL

        if desc.usage.contains(.copySource){
            imageCreateInfo.usage |= UInt32(VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        }
        if desc.usage.contains(.copyDestination) {
            imageCreateInfo.usage |= UInt32(VK_IMAGE_USAGE_TRANSFER_DST_BIT.rawValue)
        }
        if desc.usage.contains(.shaderRead) || desc.usage.contains(.sampled) {
            imageCreateInfo.usage |= UInt32(VK_IMAGE_USAGE_SAMPLED_BIT.rawValue)
        }
        if desc.usage.contains(.shaderWrite) || desc.usage.contains(.storage) {
            imageCreateInfo.usage |= UInt32(VK_IMAGE_USAGE_STORAGE_BIT.rawValue)
        }
        if desc.usage.contains(.renderTarget) {
            imageCreateInfo.usage |= UInt32(VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT.rawValue)
            if desc.pixelFormat.isDepthFormat || desc.pixelFormat.isStencilFormat {
                imageCreateInfo.usage |= UInt32(VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue)
            } else {
                imageCreateInfo.usage |= UInt32(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue)
            }
        }

        imageCreateInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        // Set initial layout of the image to undefined
        imageCreateInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED

        var result: VkResult = vkCreateImage(self.device, &imageCreateInfo, self.allocationCallbacks, &image)
        if result != VK_SUCCESS {
            Log.err("vkCreateImage failed: \(result)")
            return nil
        }

        // Allocate device memory
        var dedicatedRequirements = VkMemoryDedicatedRequirements()
        dedicatedRequirements.sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS
        var memoryRequirements  = VkMemoryRequirements2()
        memoryRequirements.sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2
        withUnsafeMutablePointer(to: &dedicatedRequirements) {
            memoryRequirements.pNext = UnsafeMutableRawPointer($0)
            var memoryRequirementsInfo = VkImageMemoryRequirementsInfo2()
            memoryRequirementsInfo.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2
            memoryRequirementsInfo.image = image
            vkGetImageMemoryRequirements2(device, &memoryRequirementsInfo, &memoryRequirements)
        }

        let memReqs = memoryRequirements.memoryRequirements
        let memProperties = VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue)
        guard let memoryTypeIndex = self.indexOfMemoryType(typeBits: memReqs.memoryTypeBits, properties: memProperties)
        else {
            fatalError("VulkanGraphicsDevice error: Unknown memory type!")
        }

        if dedicatedRequirements.prefersDedicatedAllocation != 0 {
            memory = self.memoryPools[memoryTypeIndex].allocDedicated(size: memReqs.size, image: image, buffer: nil)
        } else {
            memory = self.memoryPools[memoryTypeIndex].alloc(size: memReqs.size)
        }
        guard let mem = memory else {
            Log.error("Memory allocation failed.")
            return nil
        }
        result = vkBindImageMemory(self.device, image, mem.chunk!.memory, mem.offset)
        if result != VK_SUCCESS {
            Log.err("vkBindBufferMemory failed: \(result)")
            return nil
        }

        let imageObject = VulkanImage(device: self, memory: mem, image: image!, imageCreateInfo: imageCreateInfo)
        image = nil
        memory = nil

        return imageObject.makeImageView(format: desc.pixelFormat)
    }

    func makeTransientRenderTarget(type textureType: TextureType,
                                   pixelFormat: PixelFormat,
                                   width: Int,
                                   height: Int,
                                   depth: Int,
                                   sampleCount: Int) -> Texture? {
        var image: VkImage? = nil
        var memory: VulkanMemoryBlock? = nil

        defer {
            if image != nil {
                vkDestroyImage(self.device, image, self.allocationCallbacks)
            }
            if var memory {
                memory.chunk!.pool.dealloc(&memory)
            }
        }

        var imageCreateInfo = VkImageCreateInfo()
        imageCreateInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
        switch textureType {
        case .type1D:
            imageCreateInfo.imageType = VK_IMAGE_TYPE_1D
        case .type2D:
            imageCreateInfo.imageType = VK_IMAGE_TYPE_2D
        case .type3D:
            imageCreateInfo.imageType = VK_IMAGE_TYPE_3D
        case .typeCube:
            imageCreateInfo.imageType = VK_IMAGE_TYPE_2D
            imageCreateInfo.flags |= UInt32(VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT.rawValue)
        default:
            assertionFailure("Invalid texture type!")
            Log.err("VulkanGraphicsDevice.makeTransientRenderTarget: Invalid texture type!")
            return nil
        }

        if width < 1 || height < 1 || depth < 1 {
            Log.err("Texture dimensions (width, height, depth) value must be greater than or equal to 1.")
            return nil
        }
        if sampleCount.isPowerOfTwo == false {
            Log.err("VulkanGraphicsDevice.makeTransientRenderTarget: Sample count must be a power of two.")
            return nil
        }
        if sampleCount > 64 {
            Log.err("VulkanGraphicsDevice.makeTransientRenderTarget: Sample count must be less than or equal to 64.")
            return nil
        }

        imageCreateInfo.arrayLayers = 1
        imageCreateInfo.format = pixelFormat.vkFormat()
        assert(imageCreateInfo.format != VK_FORMAT_UNDEFINED, "Unsupported format!")

        imageCreateInfo.extent.width = UInt32(width)
        imageCreateInfo.extent.height = UInt32(height)
        imageCreateInfo.extent.depth = UInt32(depth)
        imageCreateInfo.mipLevels = UInt32(1)
        imageCreateInfo.samples = VkSampleCountFlagBits(rawValue: Int32(sampleCount))
        imageCreateInfo.tiling = VK_IMAGE_TILING_OPTIMAL
        imageCreateInfo.usage = UInt32(VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT.rawValue |
                                       VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT.rawValue)
        if pixelFormat.isDepthFormat || pixelFormat.isStencilFormat {
            imageCreateInfo.usage |= UInt32(VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue)
        } else {
            imageCreateInfo.usage |= UInt32(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue)
        }
        
        imageCreateInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        // Set initial layout of the image to undefined
        imageCreateInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED

        var result: VkResult = vkCreateImage(self.device, &imageCreateInfo, self.allocationCallbacks, &image)
        if result != VK_SUCCESS {
            Log.err("vkCreateImage failed: \(result)")
            return nil
        }

        // Allocate device memory
        var dedicatedRequirements = VkMemoryDedicatedRequirements()
        dedicatedRequirements.sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS
        var memoryRequirements  = VkMemoryRequirements2()
        memoryRequirements.sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2
        withUnsafeMutablePointer(to: &dedicatedRequirements) {
            memoryRequirements.pNext = UnsafeMutableRawPointer($0)
            var memoryRequirementsInfo = VkImageMemoryRequirementsInfo2()
            memoryRequirementsInfo.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2
            memoryRequirementsInfo.image = image
            vkGetImageMemoryRequirements2(device, &memoryRequirementsInfo, &memoryRequirements)
        }

        let memReqs = memoryRequirements.memoryRequirements
        // try lazily allocated memory type
        var memoryTypeIndex = self.indexOfMemoryType(
            typeBits: memReqs.memoryTypeBits, 
            properties: VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT.rawValue))
        if memoryTypeIndex == nil { // not supported.
            memoryTypeIndex = self.indexOfMemoryType(
                typeBits: memReqs.memoryTypeBits, 
                properties: VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue))
        }
        guard let memoryTypeIndex else {
            fatalError("VulkanGraphicsDevice error: Unknown memory type!")
        }

        if dedicatedRequirements.prefersDedicatedAllocation != 0 {
            memory = self.memoryPools[memoryTypeIndex].allocDedicated(size: memReqs.size, image: image, buffer: nil)
        } else {
            memory = self.memoryPools[memoryTypeIndex].alloc(size: memReqs.size)
        }
        guard let mem = memory else {
            Log.error("Memory allocation failed.")
            return nil
        }
        result = vkBindImageMemory(self.device, image, mem.chunk!.memory, mem.offset)
        if result != VK_SUCCESS {
            Log.err("vkBindBufferMemory failed: \(result)")
            return nil
        }

        let imageObject = VulkanImage(device: self, memory: mem, image: image!, imageCreateInfo: imageCreateInfo)
        image = nil
        memory = nil

        return imageObject.makeImageView(format: pixelFormat)
    }


    func makeSamplerState(descriptor desc: SamplerDescriptor) -> SamplerState? {
        let filter = { (f: SamplerMinMagFilter) -> VkFilter in
            switch f {
            case .nearest:      VK_FILTER_NEAREST
            case .linear:       VK_FILTER_LINEAR
            }
        }
        let mipmapMode = { (f: SamplerMipFilter) -> VkSamplerMipmapMode in
            switch f {
            case .notMipmapped,
                 .nearest:      VK_SAMPLER_MIPMAP_MODE_NEAREST
            case .linear:       VK_SAMPLER_MIPMAP_MODE_LINEAR
            }
        }
        let addressMode = { (m: SamplerAddressMode) -> VkSamplerAddressMode in
            switch m {
            case .clampToEdge:  VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
            case .repeat:       VK_SAMPLER_ADDRESS_MODE_REPEAT
            case .mirrorRepeat: VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT
            case .clampToZero:  VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER
            }
        }
        let compareOp = { (f: CompareFunction) -> VkCompareOp in
            switch f {
            case .never:        VK_COMPARE_OP_NEVER
            case .less:         VK_COMPARE_OP_LESS
            case .equal:        VK_COMPARE_OP_EQUAL
            case .lessEqual:    VK_COMPARE_OP_LESS_OR_EQUAL
            case .greater:      VK_COMPARE_OP_GREATER
            case .notEqual:     VK_COMPARE_OP_NOT_EQUAL
            case .greaterEqual: VK_COMPARE_OP_GREATER_OR_EQUAL
            case .always:       VK_COMPARE_OP_ALWAYS
            }
        }

        var createInfo = VkSamplerCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO
        createInfo.minFilter = filter(desc.minFilter)
        createInfo.magFilter = filter(desc.magFilter)
        createInfo.mipmapMode = mipmapMode(desc.mipFilter)
        createInfo.addressModeU = addressMode(desc.addressModeU)
        createInfo.addressModeV = addressMode(desc.addressModeV)
        createInfo.addressModeW = addressMode(desc.addressModeW)
        createInfo.mipLodBias = 0.0
        // createInfo.anisotropyEnable = desc.maxAnisotropy > 1 ? VK_TRUE : VK_FALSE
        createInfo.anisotropyEnable = VK_TRUE
        createInfo.maxAnisotropy = Float(desc.maxAnisotropy)
        createInfo.compareOp = compareOp(desc.compareFunction)
        createInfo.compareEnable = desc.compareFunction == .always ? VK_FALSE : VK_TRUE
        createInfo.minLod = desc.lodMinClamp
        createInfo.maxLod = desc.lodMaxClamp

        createInfo.borderColor = VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK

        createInfo.unnormalizedCoordinates = desc.normalizedCoordinates ? VK_FALSE : VK_TRUE
        if createInfo.unnormalizedCoordinates != 0 {
            createInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST
            createInfo.magFilter = createInfo.minFilter
            createInfo.minLod = 0
            createInfo.maxLod = 0
            createInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
            createInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
            createInfo.anisotropyEnable = VK_FALSE
            createInfo.compareEnable = VK_FALSE
        }

        var sampler: VkSampler? = nil
        let result = vkCreateSampler(self.device, &createInfo, self.allocationCallbacks, &sampler)
        if result != VK_SUCCESS {
            Log.err("vkCreateSampler failed: \(result)")
            return nil
        }

        return VulkanSampler(device: self, sampler: sampler!)
    }

    func makeEvent() -> GPUEvent? {
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

    func makeSemaphore() -> GPUSemaphore? {
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
            assert(chain.device === self)
            assert(chain.poolID == poolID)

            if let allocationInfo = chain.allocateDescriptorSet(layout: layout) {
                return VulkanDescriptorSet(device: self,
                                           descriptorPool: allocationInfo.descriptorPool,
                                           descriptorSet: allocationInfo.descriptorSet)
            }
        }
        return nil
    }

    func releaseDescriptorSets(_ sets: [VkDescriptorSet], pool: VulkanDescriptorPool) {
        let poolID = pool.poolID
        assert(poolID.mask != 0)

        guard sets.isEmpty == false else { return }

        let index: Int = Int(poolID.hash % UInt32(descriptorPoolChainMaps.count))

        let cleanupThresholdAllChains = 2000
        let cleanupThreshold = 100

        self.descriptorPoolChainMaps[index].lock.withLock {
            pool.release(descriptorSets: sets)
            
            var numChainPools = 0
            if cleanupThresholdAllChains > 0 {
                self.descriptorPoolChainMaps[index].poolChainMap.forEach {
                    numChainPools += $0.value.descriptorPools.count
                }
            }

            if numChainPools > cleanupThresholdAllChains {
                var emptyChainIDs: [VulkanDescriptorPoolID] = []
                emptyChainIDs.reserveCapacity(self.descriptorPoolChainMaps[index].poolChainMap.count)
                self.descriptorPoolChainMaps[index].poolChainMap.forEach {
                    if $0.value.cleanup() == 0 {
                        emptyChainIDs.append($0.key)
                    }                    
                }
                for poolID in emptyChainIDs {
                     self.descriptorPoolChainMaps[index].poolChainMap[poolID] = nil
                }
            } else {
                let chain = self.descriptorPoolChainMaps[index].poolChainMap[poolID]!
                if chain.descriptorPools.count > cleanupThreshold && chain.cleanup() == 0 {
                    self.descriptorPoolChainMaps[index].poolChainMap[poolID] = nil
                }
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
            let module = f.module //as! VulkanShaderModule

            numPushConstantRanges += module.pushConstantLayouts.count
        }

        var pushConstantRanges: [VkPushConstantRange] = []
        pushConstantRanges.reserveCapacity(numPushConstantRanges)

        var maxDescriptorBindings = 0   // maximum number of descriptor
        var maxDescriptorSets = 0       // maximum number of sets

        for fn in functions {
            let f = fn as! VulkanShaderFunction
            let module = f.module //as! VulkanShaderModule

            for layout in module.pushConstantLayouts {
                if layout.size > 0 {
                    var range = VkPushConstantRange()
                    range.stageFlags = module.stage.vkFlags()

                    // VUID-VkGraphicsPipelineCreateInfo-layout-07987                
                    let begin = layout.members.reduce(layout.offset) {
                        (result, member) in
                        min(result, member.offset)
                    }
                    let end = layout.members.reduce(layout.offset + layout.size) {
                        (result, member) in
                        max(result, member.offset + member.size)
                    }
                    range.offset = UInt32(begin)
                    range.size = UInt32(end - begin)
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
                let module = f.module //as! VulkanShaderModule

                for desc in module.descriptors {
                    if desc.set > setIndex { break }

                    if desc.set == setIndex {
                        var newBinding = true

                        for (i, var b) in descriptorBindings.enumerated() {
                            if b.binding == desc.binding {  // exist binding!! (conflict)
                                newBinding = false
                                if b.descriptorType == desc.type.vkType() {
                                    b.descriptorCount = max(b.descriptorCount, UInt32(desc.count))
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
                                binding: UInt32(desc.binding),
                                descriptorType: desc.type.vkType(),
                                descriptorCount: UInt32(desc.count),
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
                vkGetDescriptorSetLayoutSupport(device, &setLayoutCreateInfo, &layoutSupport)
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

    func addCompletionHandler(fence: VkFence, op: @escaping @Sendable ()->Void) {
        self.fenceCompletionLock.withLock {
            let cb = FenceCallback(fence: fence, operation: op)
            self.pendingFenceCallbacks.append(cb)
        }
    }

    func fence() -> VkFence {
        var fence: VkFence? = self.fenceCompletionLock.withLock {
            if self.reusableFences.count > 0 {
                return self.reusableFences.removeFirst()
            }
            return nil
        }
        if fence == nil {
            var fenceCreateInfo = VkFenceCreateInfo()
            fenceCreateInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO

            let err = vkCreateFence(self.device, &fenceCreateInfo, self.allocationCallbacks, &fence)
            if err != VK_SUCCESS {
                Log.err("vkCreateFence failed: \(err)")
                assertionFailure("vkCreateFence failed: \(err)")
            }
            self.numberOfFences += 1
            Log.verbose("VulkanQueueCompletionHandlerFence: \(self.numberOfFences) fences created.")
        }
        return fence!
    }
}
#endif //if ENABLE_VULKAN
