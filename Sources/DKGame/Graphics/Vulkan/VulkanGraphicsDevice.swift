//
//  File: VulkanGraphicsDevice.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

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

    private struct FenceCallback {
        let fence: VkFence
        let operation: () -> Void
    }
    private var pendingFenceCallbacks: [FenceCallback] = []
    private var reusableFences: [VkFence] = []
    private var numberOfFences: UInt = 0
    private var fenceCompletionLock = SpinLock()

    public var autoIncrementTimelineEvent = false

    private struct DescriptorPoolChainMap {
        var poolChainMap: [VulkanDescriptorPoolID: VulkanDescriptorPoolChain] = [:]
        let lock: SpinLock = SpinLock()
    }
    private var descriptorPoolChainMaps: [DescriptorPoolChainMap] = .init(repeating: DescriptorPoolChainMap(), count: 7)
    private var task: Task<Void, Never>?

    public init?(instance: VulkanInstance,
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
            return nil
        }

        var requiredExtensions = requiredExtensions
        var optionalExtensions = optionalExtensions

        requiredExtensions.append(VK_KHR_SWAPCHAIN_EXTENSION_NAME)
        requiredExtensions.append(VK_KHR_MAINTENANCE1_EXTENSION_NAME)
        requiredExtensions.append(VK_KHR_TIMELINE_SEMAPHORE_EXTENSION_NAME)
        // requiredExtensions.append(VK_EXT_EXTENDED_DYNAMIC_STATE_EXTENSION_NAME)

        optionalExtensions.append(VK_KHR_MAINTENANCE2_EXTENSION_NAME)
        optionalExtensions.append(VK_KHR_MAINTENANCE3_EXTENSION_NAME)

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
#if VK_USE_PLATFORM_WIN32_KHR
            supportPresentation = instance.extensionProc
                .vkGetPhysicalDeviceWin32PresentationSupportKHR?(
                    physicalDevice.device,
                    $0.queueFamilyIndex) ?? VkBool32(VK_FALSE)
                != VkBool32(VK_FALSE)
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
                        display) ?? VkBool32(VK_FALSE)
                    != VkBool32(VK_FALSE)
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

        self.loadPipelineCache()

        self.task = .detached(priority: .background) { [weak self] in
            numberOfThreadsToWaitBeforeExiting.increment()
            defer { numberOfThreadsToWaitBeforeExiting.decrement() }

            Log.info("VulkanGraphicsDevice Helper task is started.")

            var err: VkResult = VK_SUCCESS
            var fences: [VkFence?] = []
            var waitingFences: [FenceCallback] = []
            var completionHandlers: [()->Void] = []

            let fenceWaitInterval = 0.01
            var timer = TickCounter()

            mainLoop: while true {
                guard let self = self else { break }
                if Task.isCancelled { break }

                synchronizedBy(locking: self.fenceCompletionLock) {
                    waitingFences.append(contentsOf: self.pendingFenceCallbacks)
                    self.pendingFenceCallbacks.removeAll(keepingCapacity: true)
                }

                if waitingFences.isEmpty == false {
                    fences.removeAll(keepingCapacity: true)
                    fences.reserveCapacity(waitingFences.count)
                    waitingFences.forEach { fences.append($0.fence) }

                    err = vkWaitForFences(self.device, UInt32(fences.count), fences, VkBool32(VK_FALSE), 0)
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
                        synchronizedBy(locking: self.fenceCompletionLock) {
                            self.reusableFences.append(contentsOf: fences.compactMap{ $0 })
                        }
                        fences.removeAll(keepingCapacity: true)
                    }

                    if err == VK_TIMEOUT {
                        while timer.elapsed < fenceWaitInterval {
                            if Task.isCancelled {
                                break mainLoop
                            }
                            await Task.yield()
                        }
                    }
                    timer.reset()
                }
            }
            assert(completionHandlers.isEmpty, "completionHandlers must be empty!")
            Log.info("VulkanGraphicsDevice Helper task is finished.")
        }
    }
    
    deinit {
        Log.debug("VulkanGraphicsDevice is being destroyed.")

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

    private func indexOfMemoryType(typeBits: UInt32, properties: VkMemoryPropertyFlags) -> UInt32 {
        for i in 0..<self.deviceMemoryTypes.count {
            if (typeBits & (1 << i)) != 0 && (self.deviceMemoryTypes[i].propertyFlags & properties) == properties {
                    return UInt32(i)
                }
        }
        assertionFailure("VulkanGraphicsDevice error: Unknown memory type!")
        return UInt32.max
    }

    public func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue? {
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
    public func makeShaderModule(from shader: Shader) -> ShaderModule? {
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
                    assert(chain.device === self)
                    assert(chain.poolID == poolID)
                }
            }
#endif
            // create layout!
            var layoutBindings: [VkDescriptorSetLayoutBinding] = []
            layoutBindings.reserveCapacity(layout.bindings.count)
            for binding in layout.bindings {
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

        var result: VkResult = VK_SUCCESS

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
        var shaderStageCreateInfos: [VkPipelineShaderStageCreateInfo] = []
        shaderStageCreateInfos.reserveCapacity(shaderFunctions.count)

        for fn in shaderFunctions {
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
            shaderStageCreateInfos.append(shaderStageCreateInfo)
        }
        pipelineCreateInfo.stageCount = UInt32(shaderStageCreateInfos.count)
        pipelineCreateInfo.pStages = unsafePointerCopy(collection: shaderStageCreateInfos, holder: tempHolder)

        pipelineLayout = makePipelineLayout(
            functions: shaderFunctions,
            layoutDefaultStageFlags: VkShaderStageFlags(VK_SHADER_STAGE_ALL.rawValue))
        if pipelineLayout == nil { return nil }
        pipelineCreateInfo.layout = pipelineLayout

        // vertex input state
        var vertexBindingDescriptions: [VkVertexInputBindingDescription] = []
        vertexBindingDescriptions.reserveCapacity(desc.vertexDescriptor.layouts.count)
        for layout in desc.vertexDescriptor.layouts {   // buffer layout
            var binding = VkVertexInputBindingDescription()
            binding.binding = UInt32(layout.bufferIndex)
            binding.stride = UInt32(layout.stride)
            switch layout.step {
            case .vertex:
                binding.inputRate = VK_VERTEX_INPUT_RATE_VERTEX
            case .instance:
                binding.inputRate = VK_VERTEX_INPUT_RATE_INSTANCE
            }
            vertexBindingDescriptions.append(binding)
        }

        var vertexAttributeDescriptions: [VkVertexInputAttributeDescription] = []
        vertexAttributeDescriptions.reserveCapacity(desc.vertexDescriptor.attributes.count)
        for attrDesc in desc.vertexDescriptor.attributes {
            var attr = VkVertexInputAttributeDescription()
            attr.location = UInt32(attrDesc.location)
            attr.binding = UInt32(attrDesc.bufferIndex)
            attr.format = attrDesc.format.vkFormat()
            attr.offset = UInt32(attrDesc.offset)
            vertexAttributeDescriptions.append(attr)
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
        switch desc.primitiveTopology {
        case .point:            inputAssemblyState.topology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST
        case .line:             inputAssemblyState.topology = VK_PRIMITIVE_TOPOLOGY_LINE_LIST
        case .lineStrip:        inputAssemblyState.topology = VK_PRIMITIVE_TOPOLOGY_LINE_STRIP
        case .triangle:         inputAssemblyState.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
        case .triangleStrip:    inputAssemblyState.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP
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

        switch desc.cullMode {
        case .none:  rasterizationState.cullMode = VkCullModeFlags(VK_CULL_MODE_NONE.rawValue)
        case .front: rasterizationState.cullMode = VkCullModeFlags(VK_CULL_MODE_FRONT_BIT.rawValue)
        case .back:  rasterizationState.cullMode = VkCullModeFlags(VK_CULL_MODE_BACK_BIT.rawValue)
        }

        switch desc.frontFace {
        case .cw:   rasterizationState.frontFace = VK_FRONT_FACE_CLOCKWISE
        case .ccw:  rasterizationState.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE
        }

        rasterizationState.depthClampEnable = VkBool32(VK_FALSE)
        if desc.depthClipMode == .clamp {
            if self.features.depthClamp != 0 {
                rasterizationState.depthClampEnable = VkBool32(VK_TRUE)
            } else {
                Log.warn("VulkanGraphicsDevice.\(#function): DepthClamp not supported for this hardware.")
            }
        }
        rasterizationState.rasterizerDiscardEnable = VkBool32(desc.rasterizationEnabled ? VK_FALSE : VK_TRUE)
        rasterizationState.depthBiasEnable = VkBool32(VK_FALSE)
        rasterizationState.lineWidth = 1.0
        pipelineCreateInfo.pRasterizationState = unsafePointerCopy(from: rasterizationState, holder: tempHolder)

        // setup multisampling
        var multisampleState = VkPipelineMultisampleStateCreateInfo()
        multisampleState.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
        multisampleState.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT
        multisampleState.pSampleMask = nil
        pipelineCreateInfo.pMultisampleState = unsafePointerCopy(from: multisampleState, holder: tempHolder)

        // setup depth-stencil
        var depthStencilState = VkPipelineDepthStencilStateCreateInfo()
        depthStencilState.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
        let compareOp = { (fn: CompareFunction) -> VkCompareOp in
            switch fn {
            case .never:            return VK_COMPARE_OP_NEVER
            case .less:             return VK_COMPARE_OP_LESS
            case .equal:            return VK_COMPARE_OP_EQUAL
            case .lessEqual:        return VK_COMPARE_OP_LESS_OR_EQUAL
            case .greater:          return VK_COMPARE_OP_GREATER
            case .notEqual:         return VK_COMPARE_OP_NOT_EQUAL
            case .greaterEqual:     return VK_COMPARE_OP_GREATER_OR_EQUAL
            case .always:           return VK_COMPARE_OP_ALWAYS
            }
        }
        let stencilOp = { (op: StencilOperation) -> VkStencilOp in
            switch op {
            case .keep:             return VK_STENCIL_OP_KEEP
            case .zero:             return VK_STENCIL_OP_ZERO
            case .replace:          return VK_STENCIL_OP_REPLACE
            case .incrementClamp:   return VK_STENCIL_OP_INCREMENT_AND_CLAMP
            case .decrementClamp:   return VK_STENCIL_OP_DECREMENT_AND_CLAMP
            case .invert:           return VK_STENCIL_OP_INVERT
            case .incrementWrap:    return VK_STENCIL_OP_INCREMENT_AND_WRAP
            case .decrementWrap:    return VK_STENCIL_OP_DECREMENT_AND_WRAP
            }
        }
        let setStencilOpState = { (state: inout VkStencilOpState, stencil: StencilDescriptor) in
            state.failOp = stencilOp(stencil.stencilFailureOperation)
            state.passOp = stencilOp(stencil.depthStencilPassOperation)
            state.depthFailOp = stencilOp(stencil.depthFailOperation)
            state.compareOp = compareOp(stencil.stencilCompareFunction)
            state.compareMask = stencil.readMask
            state.writeMask = stencil.writeMask
            state.reference = 0 // use dynamic state (VK_DYNAMIC_STATE_STENCIL_REFERENCE)
        }
        depthStencilState.depthTestEnable = VkBool32(VK_TRUE)
        depthStencilState.depthWriteEnable = VkBool32(desc.depthStencilDescriptor.isDepthWriteEnabled ? VK_TRUE:VK_FALSE)
        depthStencilState.depthCompareOp = compareOp(desc.depthStencilDescriptor.depthCompareFunction)
        depthStencilState.depthBoundsTestEnable = VkBool32(VK_FALSE)
        setStencilOpState(&depthStencilState.front, desc.depthStencilDescriptor.frontFaceStencil)
        setStencilOpState(&depthStencilState.back, desc.depthStencilDescriptor.backFaceStencil)
        depthStencilState.stencilTestEnable = VkBool32(VK_TRUE)

        if depthStencilState.front.failOp == VK_STENCIL_OP_KEEP &&
           depthStencilState.front.passOp == VK_STENCIL_OP_KEEP &&
           depthStencilState.front.depthFailOp == VK_STENCIL_OP_KEEP &&
           depthStencilState.back.failOp == VK_STENCIL_OP_KEEP &&
           depthStencilState.back.passOp == VK_STENCIL_OP_KEEP &&
           depthStencilState.back.depthFailOp == VK_STENCIL_OP_KEEP {
            depthStencilState.stencilTestEnable = VkBool32(VK_FALSE)
        }
        if depthStencilState.depthWriteEnable == VK_FALSE &&
           depthStencilState.depthCompareOp == VK_COMPARE_OP_ALWAYS {
            depthStencilState.depthTestEnable = VkBool32(VK_FALSE)
        }

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
        ]
        var dynamicState = VkPipelineDynamicStateCreateInfo()
        dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
        dynamicState.pDynamicStates = unsafePointerCopy(collection: dynamicStateEnables, holder: tempHolder)
        dynamicState.dynamicStateCount = UInt32(dynamicStateEnables.count)
        pipelineCreateInfo.pDynamicState = unsafePointerCopy(from: dynamicState, holder: tempHolder)

        // render pass
        var renderPassCreateInfo = VkRenderPassCreateInfo()
        renderPassCreateInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
        var subpassDesc = VkSubpassDescription()
        subpassDesc.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
        var attachmentDescriptions: [VkAttachmentDescription] = []
        let subpassInputAttachmentRefs: [VkAttachmentReference] = []
        var subpassColorAttachmentRefs: [VkAttachmentReference] = []
        let subpassResolveAttachmentRefs: [VkAttachmentReference] = []
        var colorBlendAttachmentStates: [VkPipelineColorBlendAttachmentState] = []

        attachmentDescriptions.reserveCapacity(desc.colorAttachments.count + 1)
        subpassColorAttachmentRefs.reserveCapacity(desc.colorAttachments.count)
        colorBlendAttachmentStates.reserveCapacity(desc.colorAttachments.count)

        let blendOperation = { (op: BlendOperation) -> VkBlendOp in
            switch op {
            case .add:              return VK_BLEND_OP_ADD
            case .subtract:         return VK_BLEND_OP_SUBTRACT
            case .reverseSubtract:  return VK_BLEND_OP_REVERSE_SUBTRACT
            case .min:              return VK_BLEND_OP_MIN
            case .max:              return VK_BLEND_OP_MAX
            }
        }
        let blendFactor = { (factor: BlendFactor) -> VkBlendFactor in
            switch factor {
            case .zero:                     return VK_BLEND_FACTOR_ZERO
            case .one:                      return VK_BLEND_FACTOR_ONE
            case .sourceColor:              return VK_BLEND_FACTOR_SRC_COLOR
            case .oneMinusSourceColor:      return VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR
            case .sourceAlpha:              return VK_BLEND_FACTOR_SRC_ALPHA
            case .oneMinusSourceAlpha:      return VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
            case .destinationColor:         return VK_BLEND_FACTOR_DST_COLOR
            case .oneMinusDestinationColor: return VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR
            case .destinationAlpha:         return VK_BLEND_FACTOR_DST_ALPHA
            case .oneMinusDestinationAlpha: return VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA
            case .sourceAlphaSaturated:     return VK_BLEND_FACTOR_SRC_ALPHA_SATURATE
            case .blendColor:               return VK_BLEND_FACTOR_CONSTANT_COLOR
            case .oneMinusBlendColor:       return VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR
            case .blendAlpha:               return VK_BLEND_FACTOR_CONSTANT_ALPHA
            case .oneMinusBlendAlpha:       return VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA
            }
        }

        var colorAttachmentRefCount = 0
        for attachment in desc.colorAttachments {
            assert(attachment.pixelFormat.isColorFormat())
            colorAttachmentRefCount = max(colorAttachmentRefCount, attachment.index + 1)
        }
        if colorAttachmentRefCount > self.properties.limits.maxColorAttachments {
            Log.err("The number of colors attached exceeds the device limit. (\(colorAttachmentRefCount) > \(self.properties.limits.maxColorAttachments))")
            return nil
        }
        subpassColorAttachmentRefs.append(contentsOf: 
            [VkAttachmentReference](repeating: VkAttachmentReference(attachment: VK_ATTACHMENT_UNUSED, layout: VK_IMAGE_LAYOUT_UNDEFINED),
                                    count: Int(colorAttachmentRefCount)))

        for (index, attachment) in desc.colorAttachments.enumerated() {
            var attachmentDesc = VkAttachmentDescription()
            attachmentDesc.format = attachment.pixelFormat.vkFormat()
            attachmentDesc.samples = VK_SAMPLE_COUNT_1_BIT
            attachmentDesc.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
            attachmentDesc.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
            attachmentDesc.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
            attachmentDesc.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
            attachmentDesc.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
            attachmentDesc.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
            attachmentDescriptions.append(attachmentDesc)

            var blendState = VkPipelineColorBlendAttachmentState()
            blendState.blendEnable = VkBool32(attachment.blendState.enabled ? VK_TRUE:VK_FALSE)
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
            colorBlendAttachmentStates.append(blendState)

            assert(subpassColorAttachmentRefs.count > attachment.index)
            subpassColorAttachmentRefs[Int(attachment.index)].attachment = UInt32(index) // index of render-pass-attachment 
            subpassColorAttachmentRefs[Int(attachment.index)].layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        }
        subpassDesc.colorAttachmentCount = UInt32(subpassColorAttachmentRefs.count)
        subpassDesc.pColorAttachments = unsafePointerCopy(collection: subpassColorAttachmentRefs, holder: tempHolder)
        subpassDesc.pResolveAttachments = unsafePointerCopy(collection: subpassResolveAttachmentRefs, holder: tempHolder)
        subpassDesc.inputAttachmentCount = UInt32(subpassInputAttachmentRefs.count)
        subpassDesc.pInputAttachments = unsafePointerCopy(collection: subpassInputAttachmentRefs, holder: tempHolder)

        if desc.depthStencilAttachmentPixelFormat.isDepthFormat() ||
           desc.depthStencilAttachmentPixelFormat.isStencilFormat() {

            var subpassDepthStencilAttachment = VkAttachmentReference()
            subpassDepthStencilAttachment.attachment = UInt32(attachmentDescriptions.count) // attachment index
            subpassDepthStencilAttachment.layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
            // add depth-stencil attachment description
            var attachmentDesc = VkAttachmentDescription()
            attachmentDesc.format = desc.depthStencilAttachmentPixelFormat.vkFormat()
            attachmentDesc.samples = VK_SAMPLE_COUNT_1_BIT
            attachmentDesc.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
            attachmentDesc.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
            attachmentDesc.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
            attachmentDesc.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
            attachmentDesc.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
            attachmentDesc.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
            attachmentDescriptions.append(attachmentDesc)
            subpassDesc.pDepthStencilAttachment = unsafePointerCopy(from: subpassDepthStencilAttachment, holder: tempHolder)
        }

        renderPassCreateInfo.attachmentCount = UInt32(attachmentDescriptions.count)
        renderPassCreateInfo.pAttachments = unsafePointerCopy(collection: attachmentDescriptions, holder: tempHolder)
        renderPassCreateInfo.subpassCount = 1
        renderPassCreateInfo.pSubpasses = unsafePointerCopy(from: subpassDesc, holder: tempHolder)

        result = vkCreateRenderPass(self.device, &renderPassCreateInfo, self.allocationCallbacks, &renderPass)
        if result != VK_SUCCESS {
            Log.err("vkCreateRenderPass failed: \(result)")
            return nil
        }
        pipelineCreateInfo.renderPass = renderPass

        // color blending
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
                    inputAttributes.reserveCapacity(module.inputAttributes.count)
                    for attr in module.inputAttributes {
                        if attr.enabled {
                            inputAttributes.append(attr)
                        }
                    }
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
                                                  layout: pipelineLayout!,
                                                  renderPass: renderPass!)
        return pipelineState
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
            reflection.pointee.resources = module.resources
        }

        pipelineState = VulkanComputePipelineState(device: self, pipeline: pipeline!, layout: pipelineLayout!)
        return pipelineState
    }

    public func makeBuffer(length: Int, storageMode: StorageMode, cpuCacheMode: CPUCacheMode) -> Buffer? {
        guard length > 0 else { return nil }

        var buffer: VkBuffer? = nil
        var memory: VkDeviceMemory? = nil

        defer {
            if buffer != nil {
                vkDestroyBuffer(self.device, buffer, self.allocationCallbacks)
            }
            if memory != nil {
                vkFreeMemory(self.device, memory, self.allocationCallbacks)
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

        var memReqs = VkMemoryRequirements()
        var memProperties: VkMemoryPropertyFlags
        switch storageMode {
        case .shared:
            memProperties = VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue | VK_MEMORY_PROPERTY_HOST_CACHED_BIT.rawValue)
        default:
            memProperties = VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue)
        }

        var memAllocInfo = VkMemoryAllocateInfo()
        memAllocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        vkGetBufferMemoryRequirements(device, buffer, &memReqs)
        memAllocInfo.allocationSize = memReqs.size
        memAllocInfo.memoryTypeIndex = self.indexOfMemoryType(typeBits: memReqs.memoryTypeBits, properties: memProperties)
        assert(memAllocInfo.allocationSize >= bufferCreateInfo.size)

        result = vkAllocateMemory(self.device, &memAllocInfo, self.allocationCallbacks, &memory)
        if result != VK_SUCCESS {
            Log.err("vkAllocateMemory failed: \(result)")
            return nil
        }
        result = vkBindBufferMemory(self.device, buffer, memory, 0)
        if result != VK_SUCCESS {
            Log.err("vkBindBufferMemory failed: \(result)")
            return nil
        }

        let memoryType: VkMemoryType = self.deviceMemoryTypes[Int(memAllocInfo.memoryTypeIndex)]
        let deviceMemory = VulkanDeviceMemory(device: self, memory: memory!, type: memoryType, size: memAllocInfo.allocationSize)
        memory = nil

        let bufferObject = VulkanBuffer(memory: deviceMemory, buffer: buffer!, bufferCreateInfo: bufferCreateInfo)
        buffer = nil

        return VulkanBufferView(buffer: bufferObject)
    }

    public func makeTexture(descriptor desc: TextureDescriptor) -> Texture? {
        var image: VkImage? = nil
        var memory: VkDeviceMemory? = nil

        defer {
            if image != nil {
                vkDestroyImage(self.device, image, self.allocationCallbacks)
            }
            if memory != nil {
                vkFreeMemory(self.device, memory, self.allocationCallbacks)
            }
        }

        var imageCreateInfo = VkImageCreateInfo()
        imageCreateInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
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

        assert(desc.sampleCount == 1, "Multisample is not implemented.")
        imageCreateInfo.samples = VK_SAMPLE_COUNT_1_BIT

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
            if desc.pixelFormat.isDepthFormat() || desc.pixelFormat.isStencilFormat() {
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
        var memReqs = VkMemoryRequirements()
        vkGetImageMemoryRequirements(self.device, image, &memReqs)
        var memAllocInfo = VkMemoryAllocateInfo()
        memAllocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        let memProperties = VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue)
        memAllocInfo.allocationSize = memReqs.size
        memAllocInfo.memoryTypeIndex = self.indexOfMemoryType(typeBits: memReqs.memoryTypeBits, properties: memProperties)
        result = vkAllocateMemory(self.device, &memAllocInfo, self.allocationCallbacks, &memory)
        if result != VK_SUCCESS {
            Log.err("vkAllocateMemory failed: \(result)")
            return nil
        }
        result = vkBindImageMemory(self.device, image, memory, 0)
        if result != VK_SUCCESS {
            Log.err("vkBindBufferMemory failed: \(result)")
            return nil
        }

        let memoryType = self.deviceMemoryTypes[Int(memAllocInfo.memoryTypeIndex)]
        let deviceMemory = VulkanDeviceMemory(device: self, memory: memory!, type: memoryType, size: memAllocInfo.allocationSize)
        memory = nil

        let imageObject = VulkanImage(memory: deviceMemory, image: image!, imageCreateInfo: imageCreateInfo)
        image = nil

        if imageCreateInfo.usage & (UInt32(VK_IMAGE_USAGE_SAMPLED_BIT.rawValue) |
                                    UInt32(VK_IMAGE_USAGE_STORAGE_BIT.rawValue) |
                                    UInt32(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue) |
                                    UInt32(VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue)) != 0 {

            var imageViewCreateInfo = VkImageViewCreateInfo()
            imageViewCreateInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
            imageViewCreateInfo.image = imageObject.image

            switch desc.textureType {
            case .type1D:
                if desc.arrayLength > 1 {
                    imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_1D_ARRAY
                } else {
                    imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_1D
                }
            case .type2D:
                if desc.arrayLength > 1 {
                    imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_2D_ARRAY
                } else {
                    imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
                }
            case .type3D:
                imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_3D
            case .typeCube:
                if desc.arrayLength > 1 {
                    imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_CUBE_ARRAY
                } else {
                    imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_CUBE
                }
            default:
                assertionFailure("Unknown texture type!")
                return nil
            }

            imageViewCreateInfo.format = imageCreateInfo.format
            imageViewCreateInfo.components = VkComponentMapping(
                r: VK_COMPONENT_SWIZZLE_R,
                g: VK_COMPONENT_SWIZZLE_G,
                b: VK_COMPONENT_SWIZZLE_B,
                a: VK_COMPONENT_SWIZZLE_A)
            
            if desc.pixelFormat.isColorFormat() {
                imageViewCreateInfo.subresourceRange.aspectMask |= UInt32(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
            }
            if desc.pixelFormat.isDepthFormat() {
                imageViewCreateInfo.subresourceRange.aspectMask |= UInt32(VK_IMAGE_ASPECT_DEPTH_BIT.rawValue)
            }
            if desc.pixelFormat.isStencilFormat() {
                imageViewCreateInfo.subresourceRange.aspectMask |= UInt32(VK_IMAGE_ASPECT_STENCIL_BIT.rawValue)
            }

            imageViewCreateInfo.subresourceRange.baseMipLevel = 0
            imageViewCreateInfo.subresourceRange.baseArrayLayer = 0
            imageViewCreateInfo.subresourceRange.layerCount = imageCreateInfo.arrayLayers
            imageViewCreateInfo.subresourceRange.levelCount = imageCreateInfo.mipLevels

            var imageView: VkImageView? = nil
            result = vkCreateImageView(self.device, &imageViewCreateInfo, self.allocationCallbacks, &imageView)
            if result != VK_SUCCESS {
               Log.err("vkCreateImageView failed: \(result)")
               return nil
            }

            return VulkanImageView(image: imageObject, imageView: imageView!, imageViewCreateInfo: imageViewCreateInfo)
        }
        return nil
    }
    public func makeSamplerState(descriptor desc: SamplerDescriptor) -> SamplerState? {
        let filter = { (f: SamplerMinMagFilter) -> VkFilter in
            switch f {
            case .nearest:      return VK_FILTER_NEAREST
            case .linear:       return VK_FILTER_LINEAR
                }
        }
        let mipmapMode = { (f: SamplerMipFilter) -> VkSamplerMipmapMode in
            switch f {
            case .notMipmapped,
                 .nearest:      return VK_SAMPLER_MIPMAP_MODE_NEAREST
            case .linear:       return VK_SAMPLER_MIPMAP_MODE_LINEAR
            }
        }
        let addressMode = { (m: SamplerAddressMode) -> VkSamplerAddressMode in
            switch m {
            case .clampToEdge:  return VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
            case .repeat:       return VK_SAMPLER_ADDRESS_MODE_REPEAT
            case .mirrorRepeat: return VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT
            case .clampToZero:  return VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER
            }
        }
        let compareOp = { (f: CompareFunction) -> VkCompareOp in
            switch f {
            case .never:        return VK_COMPARE_OP_NEVER
            case .less:         return VK_COMPARE_OP_LESS
            case .equal:        return VK_COMPARE_OP_EQUAL
            case .lessEqual:    return VK_COMPARE_OP_LESS_OR_EQUAL
            case .greater:      return VK_COMPARE_OP_GREATER
            case .notEqual:     return VK_COMPARE_OP_NOT_EQUAL
            case .greaterEqual: return VK_COMPARE_OP_GREATER_OR_EQUAL
            case .always:       return VK_COMPARE_OP_ALWAYS
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
        createInfo.compareEnable = createInfo.compareOp != VK_COMPARE_OP_NEVER ? VK_TRUE : VK_FALSE
        createInfo.minLod = desc.minLod
        createInfo.maxLod = desc.maxLod

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

        synchronizedBy(locking: self.descriptorPoolChainMaps[index].lock) {
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
                    range.offset = UInt32(layout.offset)
                    range.size = UInt32(layout.size)
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

    public func addCompletionHandler(fence: VkFence, op: @escaping ()->Void) {
        synchronizedBy(locking: self.fenceCompletionLock) {
            let cb = FenceCallback(fence: fence, operation: op)
            self.pendingFenceCallbacks.append(cb)
        }
    }

    public func fence(device: VulkanGraphicsDevice) -> VkFence {
        var fence: VkFence? = synchronizedBy(locking: self.fenceCompletionLock) {
            if self.reusableFences.count > 0 {
                return self.reusableFences.removeFirst()
            }
            return nil
        }
        if fence == nil {
            var fenceCreateInfo = VkFenceCreateInfo()
            fenceCreateInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO

            let err = vkCreateFence(device.device, &fenceCreateInfo, device.allocationCallbacks, &fence)
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
