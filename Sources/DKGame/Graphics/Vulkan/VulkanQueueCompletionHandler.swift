#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanQueueCompletionHandlerTimelineSemaphore {

    public struct TimelineSemaphore {
        let semaphore: VkSemaphore
        var timeline: UInt64 = 0    // signal value from GPU
    }
    struct CompletionHandler {
        let value: UInt64
        let operation: () -> Void
    }
    struct QueueSubmissionSemaphore {
        let queue: VkQueue
        let semaphore: VkSemaphore
        var timeline: UInt64 = 0
        var waitValue: UInt64 = 0
        var handlers: [CompletionHandler] = []
    }
    var dispatchQueue: DispatchQueue? = nil
    var deviceEventSemaphore: TimelineSemaphore
    var queueCompletionSemaphoreHandlers: [QueueSubmissionSemaphore] = []

    var queueCompletionThreadRunning: Bool = false
    var queueCompletionThreadRequestTerminate: Bool = false
    var queueCompletionHandlerCond = NSCondition()

    init(device: VulkanGraphicsDevice, dispatchQueue: DispatchQueue? = nil) {
        let createTimelineSemaphore = { (initialValue: UInt64) -> VkSemaphore in
            var semaphore: VkSemaphore? = nil
            var createInfo = VkSemaphoreCreateInfo()
            createInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO

            var typeCreateInfo = VkSemaphoreTypeCreateInfo()
            typeCreateInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO
            typeCreateInfo.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE
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
        self.deviceEventSemaphore = TimelineSemaphore(semaphore: createTimelineSemaphore(0))

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
        let vkdevice: VkDevice = device.device //to capture VkDevice not VulkanGraphicsDevice
        Thread.detachNewThread {
            self.queueCompletionThreadProc(device: vkdevice)
        }
        synchronizedBy(locking: self.queueCompletionHandlerCond) {
            while self.queueCompletionThreadRunning == false {
                self.queueCompletionHandlerCond.wait()
            }
        }
    }

    public func destroy(device: VulkanGraphicsDevice) {
        synchronizedBy(locking: self.queueCompletionHandlerCond) {
            if self.queueCompletionThreadRunning {
                var signalInfo = VkSemaphoreSignalInfo()
                signalInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO
                signalInfo.semaphore = self.deviceEventSemaphore.semaphore
                signalInfo.value = self.deviceEventSemaphore.timeline + 1
                vkSignalSemaphore(device.device, &signalInfo)
                
                self.queueCompletionThreadRequestTerminate = true
                self.queueCompletionHandlerCond.broadcast()
                while self.queueCompletionThreadRunning {
                    self.queueCompletionHandlerCond.wait()
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

        synchronizedBy(locking: self.queueCompletionHandlerCond) {
            self.queueCompletionThreadRunning = true
            self.queueCompletionHandlerCond.broadcast()
        }

        let threadName = "VulkanQueueCompletionHandlerTimelineSemaphore"
        Log.info("Helper thread: \"\(threadName)\" is started.");

        var result: VkResult = VK_SUCCESS
        var running = true
        while running {
            if result == VK_SUCCESS {
                for i in 0 ..< numSemaphores {
                    timelineValues[i] += 1
                }
            }
            var waitInfo = VkSemaphoreWaitInfo()
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
                        Log.err("vkGetSemaphoreCounterValue failed: \(r.rawValue)")
                    }
                }
                // update queues and handlers.
                synchronizedBy(locking: self.queueCompletionHandlerCond) {

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
                running = synchronizedBy(locking: self.queueCompletionHandlerCond) {
                    self.queueCompletionThreadRequestTerminate == false
                }
            } else {
                Log.err("vkWaitSemaphores failed: \(result.rawValue)")
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
                running = synchronizedBy(locking: self.queueCompletionHandlerCond) {
                    self.queueCompletionThreadRequestTerminate == false
                }
            }
        }

        if completionHandlers.isEmpty == false {
            fatalError("ERROR: completionHandlers must be empty!")
        }

        Log.info("Helper thread: \"\(threadName)\" is finished.");

        synchronizedBy(locking: self.queueCompletionHandlerCond) {
            self.queueCompletionThreadRunning = false
            self.queueCompletionHandlerCond.broadcast()
        }
    }

    public func setQueueCompletionHandler(queue: VkQueue, op: @escaping ()->Void) -> TimelineSemaphore {
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

        return synchronizedBy(locking: self.queueCompletionHandlerCond) {
            if self.queueCompletionThreadRunning == false {
                fatalError("Thread is not running!")
            }
            var s = self.queueCompletionSemaphoreHandlers[index]
            s.waitValue += 1 

            let semaphore = s.semaphore
            let timeline = s.waitValue
            let handler = CompletionHandler(value: timeline, operation: op)

            // update next wait (timeline) value & handler.
            self.queueCompletionSemaphoreHandlers[index].waitValue = s.waitValue
            self.queueCompletionSemaphoreHandlers[index].handlers.append(handler)

            return TimelineSemaphore(semaphore: semaphore, timeline: timeline)
        }
    }
}

public class VulkanQueueCompletionHandlerFence {

    struct FenceCallback {
        let fence: VkFence
        let operation: () -> Void
    }

    var pendingFenceCallbacks: [FenceCallback] = []
    var reusableFences: [VkFence] = []
    var fenceCompletionCond: NSCondition = NSCondition()

    var queueCompletionThreadRunning: Bool = false
    var queueCompletionThreadRequestTerminate: Bool = false
    var queueCompletionHandlerCond = NSCondition()

    var dispatchQueue: DispatchQueue? = nil
    var numberOfFences: UInt = 0

    init(device: VulkanGraphicsDevice, dispatchQueue: DispatchQueue? = nil) {

        self.dispatchQueue = dispatchQueue

        // create completion thread
        self.queueCompletionThreadRequestTerminate = false
        let vkdevice: VkDevice = device.device //to capture VkDevice not VulkanGraphicsDevice
        Thread.detachNewThread {
            self.queueCompletionThreadProc(device: vkdevice)
        }
        synchronizedBy(locking: self.queueCompletionHandlerCond) {
            while self.queueCompletionThreadRunning == false {
                self.queueCompletionHandlerCond.wait()
            }
        }
    }

    public func destroy(device: VulkanGraphicsDevice) {
        synchronizedBy(locking: self.queueCompletionHandlerCond) {
            if self.queueCompletionThreadRunning {
                self.queueCompletionThreadRequestTerminate = true
                self.queueCompletionHandlerCond.broadcast()
                while self.queueCompletionThreadRunning {
                    self.queueCompletionHandlerCond.wait()
                }
            }
        }

        if self.pendingFenceCallbacks.isEmpty == false {
            fatalError("Handler must be empty!")
        }
        if self.reusableFences.count != self.numberOfFences {
            Log.warn("Some fences were not returned. \(self.reusableFences.count)/\(self.numberOfFences)")
        }
        for fence in self.reusableFences {
            vkDestroyFence(device.device, fence, device.allocationCallbacks)
        }     
    }

    private func queueCompletionThreadProc(device: VkDevice) {

        synchronizedBy(locking: self.queueCompletionHandlerCond) {
            self.queueCompletionThreadRunning = true
            self.queueCompletionHandlerCond.broadcast()
        }

        let threadName = "VulkanQueueCompletionHandlerFence"
        Log.info("Helper thread: \"\(threadName)\" is started.");

        let fenceWaitInterval = 0.002

        var err: VkResult = VK_SUCCESS
        var fences: [VkFence?] = []
        var waitingFences: [FenceCallback] = []
        var completionHandlers: [()->Void] = []

        synchronizedBy(locking: self.queueCompletionHandlerCond) {
            while queueCompletionThreadRequestTerminate == false {
                waitingFences.append(contentsOf: self.pendingFenceCallbacks)
                self.pendingFenceCallbacks.removeAll(keepingCapacity: true)

                if waitingFences.count > 0 {
                    // condition is unlocked from here.
                    self.queueCompletionHandlerCond.unlock()

                    fences.removeAll(keepingCapacity: true)
                    fences.reserveCapacity(waitingFences.count)
                    for cb in waitingFences {
                        fences.append(cb.fence)
                    }

                    err = vkWaitForFences(device, UInt32(fences.count), fences, VkBool32(VK_FALSE), 0)
                    fences.removeAll(keepingCapacity: true)

                    if err == VK_SUCCESS {
                        var waitingFencesCopy: [FenceCallback] = []
                        waitingFencesCopy.reserveCapacity(waitingFences.count)

                        for cb in waitingFences {
                            if vkGetFenceStatus(device, cb.fence) == VK_SUCCESS {
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
                            err = vkResetFences(device, UInt32(fences.count), fences)
                            if err != VK_SUCCESS {
                                fatalError("vkResetFences failed: \(err.rawValue)")
                            }
                        }
                    } else if err != VK_TIMEOUT {
                        fatalError("vkWaitForFences failed: \(err.rawValue)")
                    }

                    if completionHandlers.count > 0 {
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
                    }

                    // lock condition (requires to reset fences mutually exclusive)
                    self.queueCompletionHandlerCond.lock()
                    if fences.count > 0 {
                        self.reusableFences.append(contentsOf: fences.compactMap{ $0 })
                        fences.removeAll(keepingCapacity: true)
                    }
                    if err == VK_TIMEOUT {
                        if fenceWaitInterval > 0.0 {
                            _ = self.queueCompletionHandlerCond.wait(until: Date(timeIntervalSinceNow: fenceWaitInterval))
                        } else {
                            threadYield()
                        }
                    }
                } else {
                    self.queueCompletionHandlerCond.wait()
                }
            }
        }

        if completionHandlers.isEmpty == false {
            fatalError("ERROR: completionHandlers must be empty!")
        }

        Log.info("Helper thread: \"\(threadName)\" is finished.");

        synchronizedBy(locking: self.queueCompletionHandlerCond) {
            self.queueCompletionThreadRunning = false
            self.queueCompletionHandlerCond.broadcast()
        }
    }

    public func addCompletionHandler(fence: VkFence, op: @escaping ()->Void) {
        synchronizedBy(locking: self.queueCompletionHandlerCond) {
            let cb = FenceCallback(fence: fence, operation: op)
            self.pendingFenceCallbacks.append(cb)
            self.queueCompletionHandlerCond.broadcast()
        }
    }

    public func getFence(device: VulkanGraphicsDevice) -> VkFence {
        var fence: VkFence? = synchronizedBy(locking: self.queueCompletionHandlerCond) {
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
                fatalError("vkCreateFence failed: \(err.rawValue)")
            }
            self.numberOfFences += 1
            Log.verbose("VulkanQueueCompletionHandlerFence: \(self.numberOfFences) fences created.")
        }
        return fence!
    }
}
#endif //if ENABLE_VULKAN