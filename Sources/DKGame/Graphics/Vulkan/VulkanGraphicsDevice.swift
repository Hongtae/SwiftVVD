import Vulkan
import Foundation

private protocol QueueCompletionHandler {
    func destroy(device: VulkanGraphicsDevice)
}

private class QueueCompletionTimelineSemaphore: QueueCompletionHandler {

    struct TimelineSemaphoreCounter {
        let semaphore: VkSemaphore
        var timeline: UInt64 = 0    // signal value from GPU
    }
    struct TimelineSemaphoreCompletionHandler {
        let value: UInt64
        let operation: () -> Void
    }
    struct QueueSubmissionSemaphore {
        let queue: VkQueue
        let semaphore: VkSemaphore
        var timeline: UInt64 = 0
        var waitValue: UInt64 = 0
        var handlers: [TimelineSemaphoreCompletionHandler] = []
    }
    var dispatchQueue: DispatchQueue? = nil
    var deviceEventSemaphore: TimelineSemaphoreCounter
    var queueCompletionSemaphoreHandlers: [QueueSubmissionSemaphore] = []

    var queueCompletionThreadRunning: Bool = false
    var queueCompletionThreadRequestTerminate: Bool = false
    var queueCompletionHandlerLock = NSCondition()

    init(device: VulkanGraphicsDevice, dispatchQueue: DispatchQueue? = nil) {
        let createTimelineSemaphore = { (initialValue: UInt64) -> VkSemaphore in
            var semaphore: VkSemaphore? = nil
            var createInfo = VkSemaphoreCreateInfo()
            createInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO

            var typeCreateInfo = VkSemaphoreTypeCreateInfoKHR()
            typeCreateInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO_KHR
            typeCreateInfo.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE_KHR
            typeCreateInfo.initialValue = initialValue

            let result = withUnsafePointer(to: typeCreateInfo) { pointer -> VkResult in
                createInfo.pNext = UnsafeRawPointer(pointer)
                return vkCreateSemaphore(device.device, &createInfo, device.allocationCallbacks, &semaphore)
            }
            if result != VK_SUCCESS {
                fatalError("ERROR: vkCreateSemaphore failed: \(result.rawValue)")
            }
            return semaphore!
        }

        self.dispatchQueue = dispatchQueue
        self.deviceEventSemaphore = TimelineSemaphoreCounter(semaphore: createTimelineSemaphore(0))

        var numQueues = 0
        for queueFamily in device.queueFamilies {
            numQueues += queueFamily.freeQueues.count
        }
        self.queueCompletionSemaphoreHandlers.reserveCapacity(numQueues)

        for queueFamily in device.queueFamilies {
            for queue in queueFamily.freeQueues {
                let s = QueueSubmissionSemaphore(queue: queue,
                                                 semaphore: createTimelineSemaphore(0))
                self.queueCompletionSemaphoreHandlers.append(s)
            }
        }
        // create semaphore completion thread
        self.queueCompletionThreadRequestTerminate = false
        Thread.detachNewThread {
            self.queueCompletionThreadProc(device: device.device)
        }
        synchronizedBy(locking: self.queueCompletionHandlerLock) {
            while self.queueCompletionThreadRunning == false {
                self.queueCompletionHandlerLock.wait()
            }
        }
    }
    private func queueCompletionThreadProc(device: VkDevice) {

        var timelineSemaphores: [VkSemaphore?] = []
        var timelineValues: [UInt64] = []
        var completionHandlers: [()->Void] = []

        for s in self.queueCompletionSemaphoreHandlers {
            timelineSemaphores.append(s.semaphore)
            timelineValues.append(s.timeline)
        }
        timelineSemaphores.append(self.deviceEventSemaphore.semaphore)
        timelineValues.append(self.deviceEventSemaphore.timeline)

        let numSemaphores = timelineSemaphores.count

        synchronizedBy(locking: self.queueCompletionHandlerLock) {
            self.queueCompletionThreadRunning = true
            self.queueCompletionHandlerLock.broadcast()
        }

        NSLog("Vulkan Queue Completion Helper thread is started.");

        var result: VkResult = VK_SUCCESS
        var running = true
        while running {
            if result == VK_SUCCESS {
                for i in 0 ..< numSemaphores {
                    timelineValues[i] += 1
                }
            }
            var waitInfo = VkSemaphoreWaitInfoKHR()
            waitInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO
            waitInfo.flags = UInt32(VK_SEMAPHORE_WAIT_ANY_BIT.rawValue)
            waitInfo.semaphoreCount = UInt32(numSemaphores)
            result = timelineSemaphores.withUnsafeBufferPointer {
                semaphores -> VkResult in
                waitInfo.pSemaphores = semaphores.baseAddress
                return timelineValues.withUnsafeBufferPointer {
                    values -> VkResult in
                    waitInfo.pValues = values.baseAddress

                    let sec2ns = { (s: Double) -> UInt64 in UInt64(s * 1000000.0) * 1000 }
                    return vkWaitSemaphores(device, &waitInfo, sec2ns(0.1))
                }
            }
            if result == VK_SUCCESS {
                // update semaphore values.
                for i in 0 ..< numSemaphores {
                    let r = vkGetSemaphoreCounterValue(device, timelineSemaphores[i], &timelineValues[i])
                    if r != VK_SUCCESS {
                        NSLog("ERROR: vkGetSemaphoreCounterValue failed: \(r.rawValue)")
                    }
                }
                // update queues and handlers.
                synchronizedBy(locking: self.queueCompletionHandlerLock) {

                    // queueCompletionSemaphoreHandlers must be immutable!
                    if numSemaphores != self.queueCompletionSemaphoreHandlers.count + 1 {
                        fatalError("ERROR! wrong semaphore count")
                    }

                    for index in 0 ..< self.queueCompletionSemaphoreHandlers.count {
                        let s = self.queueCompletionSemaphoreHandlers[index]
                        if s.semaphore != timelineSemaphores[index] {
                            fatalError("Invalid semaphore!")
                        }
                        let timeline = timelineValues[index]
                        var handlersToProcess = 0
                        while handlersToProcess < s.handlers.count {
                            let handler = s.handlers[handlersToProcess]
                            if handler.value > timeline {
                                break
                            }
                            completionHandlers.append(handler.operation)
                            handlersToProcess += 1
                        }

                        self.queueCompletionSemaphoreHandlers[index].timeline = timeline
                        self.queueCompletionSemaphoreHandlers[index].handlers.removeFirst(handlersToProcess)
                    }

                    if self.deviceEventSemaphore.semaphore != timelineSemaphores.last {
                        fatalError("Invalid semaphore!")
                    }
                    self.deviceEventSemaphore.timeline = timelineValues.last!

                    running = self.queueCompletionThreadRequestTerminate == false
                }
            } else if result == VK_TIMEOUT {
                running = synchronizedBy(locking: self.queueCompletionHandlerLock) {
                    self.queueCompletionThreadRequestTerminate == false
                }
            } else {
                NSLog("ERROR: vkWaitSemaphores failed: \(result.rawValue)")
            }

            // execute handlers.
            if completionHandlers.isEmpty == false {
                if let dispatchQueue = self.dispatchQueue {
                    for handler in completionHandlers {
                        dispatchQueue.async { handler() }
                    }
                } else {
                    for handler in completionHandlers {
                        handler()
                    }
                }
                completionHandlers.removeAll(keepingCapacity: true)

                // update thread state again.
                running = synchronizedBy(locking: self.queueCompletionHandlerLock) {
                    self.queueCompletionThreadRequestTerminate == false
                }
            }
        }

        if completionHandlers.isEmpty == false {
            fatalError("ERROR: completionHandlers must be empty!")
        }

        synchronizedBy(locking: self.queueCompletionHandlerLock) {
            self.queueCompletionThreadRunning = false
            self.queueCompletionHandlerLock.broadcast()
        }
        NSLog("Vulkan Queue Completion Helper thread is finished.");
    }

    func setQueueCompletionHandler(queue: VkQueue, op: @escaping ()->Void) -> TimelineSemaphoreCounter {
        let lowerBound = {
            (value: VkQueue, cmp: (_ lhs: VkQueue, _ rhs: VkQueue) -> Bool ) -> Int in

            var begin = 0
            var count = self.queueCompletionSemaphoreHandlers.count
            var mid = begin
            while count > 0 {
                mid = count / 2
                if cmp(self.queueCompletionSemaphoreHandlers[begin + mid].queue, value) {
                    begin += mid + 1
                    count -= mid + 1
                } else {
                    count = mid
                }
            }
            return begin
        }
        let index = lowerBound(queue) { a, b in UInt(bitPattern: a) < UInt(bitPattern: b) }
        if self.queueCompletionSemaphoreHandlers[index].queue != queue {
            fatalError("Invalid queue!")
        }

        return synchronizedBy(locking: self.queueCompletionHandlerLock) {
            if self.queueCompletionThreadRunning == false {
                fatalError("Thread is not running!")
            }
            var s = self.queueCompletionSemaphoreHandlers[index]
            s.waitValue += 1 

            let semaphore = s.semaphore
            let timeline = s.waitValue
            let handler = TimelineSemaphoreCompletionHandler(value: timeline, operation: op)

            // update next wait (timeline) value & handler.
            self.queueCompletionSemaphoreHandlers[index].waitValue = s.waitValue
            self.queueCompletionSemaphoreHandlers[index].handlers.append(handler)

            return TimelineSemaphoreCounter(semaphore: semaphore, timeline: timeline)
        }
    }

    func destroy(device: VulkanGraphicsDevice) {
        synchronizedBy(locking: self.queueCompletionHandlerLock) {
            if self.queueCompletionThreadRunning {
                var signalInfo = VkSemaphoreSignalInfoKHR()
                signalInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO
                signalInfo.semaphore = self.deviceEventSemaphore.semaphore
                signalInfo.value = self.deviceEventSemaphore.timeline + 1
                vkSignalSemaphore(device.device, &signalInfo)
                
                self.queueCompletionThreadRequestTerminate = true
                self.queueCompletionHandlerLock.broadcast()
                while self.queueCompletionThreadRunning {
                    self.queueCompletionHandlerLock.wait()
                }
            }
        }
        vkDestroySemaphore(device.device, self.deviceEventSemaphore.semaphore, device.allocationCallbacks)
        for handler in self.queueCompletionSemaphoreHandlers {
            vkDestroySemaphore(device.device, handler.semaphore, device.allocationCallbacks)
            if handler.handlers.isEmpty == false {
                fatalError("Handler must be empty!")
            }
        }
        self.queueCompletionSemaphoreHandlers = []
    }
}

private class QueueCompletionFence: QueueCompletionHandler {

    struct FenceCallback {
        let fence: VkFence
        let operation: () -> Void
    }

    var pendingFenceCallbacks: [FenceCallback] = []
    var reusableFences: [VkFence] = []
    var fenceCompletionCond: NSCondition = NSCondition()

    var queueCompletionThreadRunning: Bool = false
    var queueCompletionThread: Thread?

    init(device: VulkanGraphicsDevice, dispatchQueue: DispatchQueue? = nil) {
    }
    func destroy(device: VulkanGraphicsDevice) {

    }
    deinit {

    }
}

private let pipelineCacheDataKey = "_SavedSystemStates.Vulkan.PipelineCacheData"

public class VulkanGraphicsDevice : GraphicsDevice {

    public static var queueCompletionSyncTimelineSemaphore = true

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

    private var queueCompletionHandler: QueueCompletionHandler?

    public init?(instance: VulkanInstance,
                 physicalDevice: VulkanPhysicalDeviceDescription,
                 requiredExtensions: [String],
                 optionalExtensions: [String]) {

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
                NSLog("Warning: Vulkan-Device-Extension:\"\(ext)\" not supported, but required.")
            }
        }
        for ext in optionalExtensions {
            if physicalDevice.hasExtension(ext) {
                deviceExtensions.append(ext)
            } else {
                NSLog("Warning: Vulkan-Device-Extension:\"\(ext)\" not supported.")
            }
        }

        // features
        let enabledFeatures = physicalDevice.features // enable all features supported by a device
        var deviceCreateInfo = VkDeviceCreateInfo()
        deviceCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
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
                    NSLog("VkPhysicalDeviceExtendedDynamicStateFeaturesEXT[\(index)] \(ss)")
                }
            }

            deviceCreateInfo.pNext = UnsafeRawPointer(pointerCopy)
        }
#endif
        var device: VkDevice? = nil
        let err = vkCreateDevice(physicalDevice.device, &deviceCreateInfo, instance.allocationCallbacks, &device)
        if err != VK_SUCCESS {
            NSLog("Error: vkCreateDevice Failed: \(err.rawValue)")
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
                                     index: queueFamilyIndex,
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
        NSLog("Create Queue-Completion handler!")
        if Self.queueCompletionSyncTimelineSemaphore {
            self.queueCompletionHandler = QueueCompletionTimelineSemaphore(device: self, dispatchQueue: .main)
        } else {
            self.queueCompletionHandler = QueueCompletionFence(device: self, dispatchQueue: .main)
        }
    }
    
    deinit {
        vkDeviceWaitIdle(self.device)
        self.queueCompletionHandler!.destroy(device: self)
        self.queueCompletionHandler = nil

        if let pipelineCache = self.pipelineCache {
            vkDestroyPipelineCache(self.device, pipelineCache, self.allocationCallbacks)
            self.pipelineCache = nil
        }
        vkDestroyDevice(self.device, self.allocationCallbacks)
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
            NSLog("ERROR: vkCreatePipelineCache failed: \(err.rawValue)")
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

                    NSLog("Vulkan PipelineCache saved \(dataLength) bytes.")
                }
            } else {
                NSLog("ERROR: vkGetPipelineCacheData failed: \(result.rawValue)")
            }

        } else {
            NSLog("ERROR: VkPipelineCache is nil")            
        }
    }

    public func makeCommandQueue() -> CommandQueue? {
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
