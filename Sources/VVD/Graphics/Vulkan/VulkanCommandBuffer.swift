//
//  File: VulkanCommandBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

class VulkanCommandEncoder {
    let initialNumberOfCommands = 128

    struct TimelineSemaphoreStageValue {
        var stages: VkPipelineStageFlags2 // wait before or signal after
        var value: UInt64   // 0 for non-timeline semaphore (binary semaphore)
    }

    var waitSemaphores: [VkSemaphore: TimelineSemaphoreStageValue] = [:]
    var signalSemaphores: [VkSemaphore: TimelineSemaphoreStageValue] = [:]

    func encode(commandBuffer: VkCommandBuffer) -> Bool { false }

    func addWaitSemaphore(_ semaphore: VkSemaphore, value: UInt64, flags: VkPipelineStageFlags2) {
        if var p = self.waitSemaphores[semaphore] {
            p.value = max(p.value, value)
            p.stages |= flags
            self.waitSemaphores[semaphore] = p
        } else {
            self.waitSemaphores[semaphore] = TimelineSemaphoreStageValue(stages: flags, value: value)
        }
    }

    func addSignalSemaphore(_ semaphore: VkSemaphore, value: UInt64, flags: VkPipelineStageFlags2) {
        if var p = self.signalSemaphores[semaphore] {
            p.value = max(p.value, value)
            p.stages |= flags
            self.signalSemaphores[semaphore] = p
        } else {
            self.signalSemaphores[semaphore] = TimelineSemaphoreStageValue(stages: flags, value: value)
        }
    }
}

final class VulkanCommandBuffer: CommandBuffer, @unchecked Sendable {

    let commandQueue: CommandQueue
    let device: GraphicsDevice   
    private let lock = NSLock()

    private let commandPool: VkCommandPool
    private var retainedCommandBuffers: [VkCommandBuffer] = []
    private var completedHandlers: [CommandBufferHandler] = []

    private var _status: CommandBufferStatus
    var status: CommandBufferStatus { self.lock.withLock { _status } }

    private enum Encoding {
        case encoder(VulkanCommandEncoder)
        case waitSemaphore(VulkanSemaphore)
        case signalSemaphore(VulkanSemaphore)
        case waitTimelineSemaphore(VulkanTimelineSemaphore, UInt64)
        case signalTimelineSemaphore(VulkanTimelineSemaphore, UInt64)
    }
    private var encodings: [Encoding] = []

    class Recovery: @unchecked Sendable {
        var handlers: [() -> Void] = []
        func addHandler(_ handler: @escaping () -> Void) {
            self.handlers.append(handler)
        }
    }
    @TaskLocal static var recovery: Recovery? = nil

    init(queue: VulkanCommandQueue, pool: VkCommandPool) {
        self.commandQueue = queue
        self.device = queue.device
        self.commandPool = pool
        self._status = .ready
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        if self.retainedCommandBuffers.isEmpty == false {
            var tmp = self.retainedCommandBuffers.map { Optional($0) }
            vkFreeCommandBuffers(device.device, commandPool, UInt32(tmp.count), &tmp)
        }
        vkDestroyCommandPool(device.device, commandPool, device.allocationCallbacks)
    }

    func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder? {
        let queue = self.commandQueue as! VulkanCommandQueue
        if queue.family.properties.queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue) != 0 {
            self.lock.lock()
            defer { self.lock.unlock() }

            if self._status != .ready {
                Log.err("CommandBuffer.makeRenderCommandEncoder failed: CommandBuffer is not in ready state.")
                return nil
            }

            if descriptor.colorAttachments.isEmpty && descriptor.depthStencilAttachment.renderTarget == nil {
                Log.err("RenderPassDescriptor must have at least one color or depth/stencil attachment.")
                return nil
            }
            
            // initialize render pass
            let tempHolder = TemporaryBufferHolder(label: "VulkanRenderCommandEncoder.Encoder.encode")
            var renderContext = VulkanRenderCommandEncoder.RenderContext(
                renderingInfo: VkRenderingInfo(),
                viewport: VkViewport(),
                scissorRect: VkRect2D(),
                colorAttachments: [],
                colorResolveTargets: [],
                depthStencilAttachment: nil,
                depthStencilResolveTarget: nil,
                _bufferHolder: tempHolder
            )

            renderContext.renderingInfo.sType = VK_STRUCTURE_TYPE_RENDERING_INFO
            renderContext.renderingInfo.flags = 0
            renderContext.renderingInfo.layerCount = 1

            var frameWidth: Int = 0
            var frameHeight: Int = 0

            var colorAttachments: [VkRenderingAttachmentInfo] = []
            for colorAttachment in descriptor.colorAttachments {
                var attachment = VkRenderingAttachmentInfo()
                attachment.sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO
                attachment.imageView = nil
                attachment.imageLayout = VK_IMAGE_LAYOUT_UNDEFINED
                attachment.resolveMode = VK_RESOLVE_MODE_NONE
                attachment.resolveImageView = nil
                attachment.resolveImageLayout = VK_IMAGE_LAYOUT_UNDEFINED 

                attachment.loadOp = switch colorAttachment.loadAction {
                case .load:     VK_ATTACHMENT_LOAD_OP_LOAD
                case .clear:    VK_ATTACHMENT_LOAD_OP_CLEAR
                default:        VK_ATTACHMENT_LOAD_OP_DONT_CARE
                }

                attachment.storeOp = switch colorAttachment.storeAction {
                case .dontCare: VK_ATTACHMENT_STORE_OP_DONT_CARE
                case .store:    VK_ATTACHMENT_STORE_OP_STORE
                }

                attachment.clearValue.color.float32 = (Float32(colorAttachment.clearColor.r),
                                                    Float32(colorAttachment.clearColor.g),
                                                    Float32(colorAttachment.clearColor.b),
                                                    Float32(colorAttachment.clearColor.a))

                if let renderTarget = colorAttachment.renderTarget {
                    assert(renderTarget is VulkanImageView)
                    let imageView = renderTarget as! VulkanImageView

                    if imageView.isTransient {
                        // transient image cannot be loaded or stored.
                        assert(attachment.loadOp != VK_ATTACHMENT_LOAD_OP_LOAD,  "Transient texture must not be loaded.")
                        assert(attachment.storeOp != VK_ATTACHMENT_STORE_OP_STORE, "Transient texture must not be stored.")
                    }

                    attachment.imageView = imageView.imageView
                    attachment.imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL

                    renderContext.colorAttachments.append((imageView, attachment.loadOp))

                    if let image = imageView.image {
                        assert(image.pixelFormat.isColorFormat)

                        frameWidth = (frameWidth > 0) ? min(frameWidth, image.width) : image.width
                        frameHeight = (frameHeight > 0) ? min(frameHeight, image.height) : image.height
                    }

                    if let resolveTarget = colorAttachment.resolveTarget {
                        assert(resolveTarget is VulkanImageView)
                        assert(resolveTarget.isTransient == false, "Resolve target must not be transient.")
                        assert(resolveTarget.sampleCount == 1, "Resolve target must be single-sampled.")

                        let imageView = resolveTarget as! VulkanImageView
                        //attachment.resolveMode = VK_RESOLVE_MODE_AVERAGE_BIT
                        attachment.resolveImageView = imageView.imageView
                        attachment.resolveImageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL

                        renderContext.colorResolveTargets.append(imageView)

                        if let image = imageView.image {
                            assert(image.pixelFormat.isColorFormat)

                            if image.pixelFormat.isIntegerFormat {
                                attachment.resolveMode = VK_RESOLVE_MODE_SAMPLE_ZERO_BIT
                            } else {
                                attachment.resolveMode = VK_RESOLVE_MODE_AVERAGE_BIT
                            }
                        }
                    }
                }
                colorAttachments.append(attachment)
            }
            if colorAttachments.isEmpty == false {
                renderContext.renderingInfo.colorAttachmentCount = UInt32(colorAttachments.count)
                renderContext.renderingInfo.pColorAttachments = unsafePointerCopy(collection: colorAttachments, holder: tempHolder)
            }

            if let renderTarget = descriptor.depthStencilAttachment.renderTarget {
                assert(renderTarget is VulkanImageView)
                let imageView = renderTarget as! VulkanImageView

                var depthStencilAttachment = VkRenderingAttachmentInfo()
                depthStencilAttachment.sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO

                // VUID-VkRenderingInfo-pDepthAttachment-06085
                depthStencilAttachment.imageView = imageView.imageView
                depthStencilAttachment.imageLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
                depthStencilAttachment.resolveMode = VK_RESOLVE_MODE_NONE
                depthStencilAttachment.resolveImageView = nil
                depthStencilAttachment.resolveImageLayout = VK_IMAGE_LAYOUT_UNDEFINED 

                depthStencilAttachment.loadOp = switch descriptor.depthStencilAttachment.loadAction {
                case .load:     VK_ATTACHMENT_LOAD_OP_LOAD
                case .clear:    VK_ATTACHMENT_LOAD_OP_CLEAR
                default:        VK_ATTACHMENT_LOAD_OP_DONT_CARE
                }
                
                depthStencilAttachment.storeOp = switch descriptor.depthStencilAttachment.storeAction {
                case .store:    VK_ATTACHMENT_STORE_OP_STORE
                default:        VK_ATTACHMENT_STORE_OP_DONT_CARE
                }

                depthStencilAttachment.clearValue.depthStencil.depth = Float(descriptor.depthStencilAttachment.clearDepth)
                depthStencilAttachment.clearValue.depthStencil.stencil = descriptor.depthStencilAttachment.clearStencil

                renderContext.depthStencilAttachment = (imageView, depthStencilAttachment.loadOp)

                if let image = imageView.image {
                    assert(image.pixelFormat.isDepthFormat || image.pixelFormat.isStencilFormat)

                    if image.isTransient {
                        // transient image cannot be loaded or stored.
                        assert(depthStencilAttachment.loadOp != VK_ATTACHMENT_LOAD_OP_LOAD, "Transient texture must not be loaded.")
                        assert(depthStencilAttachment.storeOp != VK_ATTACHMENT_STORE_OP_STORE, "Transient texture must not be stored.")
                    }

                    let p = unsafePointerCopy(from: depthStencilAttachment, holder: tempHolder)
                    if image.pixelFormat.isDepthFormat {
                        renderContext.renderingInfo.pDepthAttachment = p
                    }
                    if image.pixelFormat.isStencilFormat {
                        renderContext.renderingInfo.pStencilAttachment = p
                    }

                    frameWidth = (frameWidth > 0) ? min(frameWidth, image.width) : image.width
                    frameHeight = (frameHeight > 0) ? min(frameHeight, image.height) : image.height
                }
                if let resolveTarget = descriptor.depthStencilAttachment.resolveTarget {
                    assert(resolveTarget is VulkanImageView)
                    assert(resolveTarget.isTransient == false, "Resolve target must not be transient.")
                    assert(resolveTarget.sampleCount == 1, "Resolve target must be single-sampled.")

                    let imageView = resolveTarget as! VulkanImageView

                    let resolveFilter = descriptor.depthStencilAttachment.resolveFilter
                    depthStencilAttachment.resolveMode = switch resolveFilter {
                    case .sample0:  VK_RESOLVE_MODE_SAMPLE_ZERO_BIT
                    case .min:      VK_RESOLVE_MODE_MIN_BIT
                    case .max:      VK_RESOLVE_MODE_MAX_BIT
                    }
                    
                    depthStencilAttachment.resolveImageView = imageView.imageView
                    depthStencilAttachment.resolveImageLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL

                    renderContext.depthStencilResolveTarget = imageView

                    if let image = imageView.image {
                        assert(image.pixelFormat.isDepthFormat || image.pixelFormat.isStencilFormat)
                    }
                }
            }

            assert(frameWidth > 0 && frameHeight > 0, "Render target must have a valid size.")

            renderContext.renderingInfo.renderArea.offset.x = 0
            renderContext.renderingInfo.renderArea.offset.y = 0
            renderContext.renderingInfo.renderArea.extent.width = UInt32(frameWidth)
            renderContext.renderingInfo.renderArea.extent.height = UInt32(frameHeight)
            renderContext.viewport = VkViewport(x: 0.0,
                                                y: 0.0,
                                                width: Float(frameWidth),
                                                height: Float(frameHeight),
                                                minDepth: 0.0,
                                                maxDepth: 1.0)
            renderContext.scissorRect = VkRect2D(offset: VkOffset2D(x: 0, y: 0),
                                                extent: VkExtent2D(width: UInt32(frameWidth),
                                                                    height: UInt32(frameHeight)))

            self._status = .encoding
            return VulkanRenderCommandEncoder(buffer: self, context: renderContext)
        }
        Log.err("CommandBuffer.makeRenderCommandEncoder failed: CommandQueue does not support graphics operations.")
        return nil
    }

    func makeComputeCommandEncoder() -> ComputeCommandEncoder? {
        let queue = self.commandQueue as! VulkanCommandQueue
        if queue.family.properties.queueFlags & UInt32(VK_QUEUE_COMPUTE_BIT.rawValue) != 0 {
            self.lock.lock()
            defer { self.lock.unlock() }

            if self._status != .ready {
                Log.err("CommandBuffer.makeComputeCommandEncoder failed: CommandBuffer is not in ready state.")
                return nil
            }
            self._status = .encoding
            return VulkanComputeCommandEncoder(buffer: self)
        }
        Log.err("CommandBuffer.makeComputeCommandEncoder failed: CommandQueue does not support compute operations.")
        return nil
    }

    func makeCopyCommandEncoder() -> CopyCommandEncoder? {
        self.lock.lock()
        defer { self.lock.unlock() }

        if self._status != .ready {
            Log.err("CommandBuffer.makeCopyCommandEncoder failed: CommandBuffer is not in ready state.")
            return nil
        }
        self._status = .encoding
        return VulkanCopyCommandEncoder(buffer: self)
    }

    func encodeWaitEvent(_ event: GPUEvent) {
        assert(event is VulkanSemaphore)
        self.lock.lock()
        defer { self.lock.unlock() }

        assert(self._status == .ready, "CommandBuffer must be in ready state.")
        if let semaphore = event as? VulkanSemaphore {
            self.encodings.append(.waitSemaphore(semaphore))
        }
    }

    func encodeSignalEvent(_ event: GPUEvent) {
        assert(event is VulkanSemaphore)
        self.lock.lock()
        defer { self.lock.unlock() }

        assert(self._status == .ready, "CommandBuffer must be in ready state.")
        if let semaphore = event as? VulkanSemaphore {
            self.encodings.append(.signalSemaphore(semaphore))
        }
    }

    func encodeWaitSemaphore(_ sema: GPUSemaphore, value: UInt64) {
        assert(sema is VulkanTimelineSemaphore)
        self.lock.lock()
        defer { self.lock.unlock() }

        assert(self._status == .ready, "CommandBuffer must be in ready state.")
        if let semaphore = sema as? VulkanTimelineSemaphore {
            self.encodings.append(.waitTimelineSemaphore(semaphore, value))
        }
    }

    func encodeSignalSemaphore(_ sema: GPUSemaphore, value: UInt64) {    
        assert(sema is VulkanTimelineSemaphore)
        self.lock.lock()
        defer { self.lock.unlock() }

        assert(self._status == .ready, "CommandBuffer must be in ready state.")
        if let semaphore = sema as? VulkanTimelineSemaphore {
            self.encodings.append(.signalTimelineSemaphore(semaphore, value))
        }
    }

    func addCompletedHandler(_ handler: @escaping CommandBufferHandler) {
        self.lock.withLock {
            completedHandlers.append(handler)
        }
    }

    @discardableResult
    func commit() -> Bool {
        let device = self.device as! VulkanGraphicsDevice
        
        self.lock.lock()
        defer { self.lock.unlock() }

        if self._status != .ready {
            Log.err("VulkanCommandBuffer.commit failed: CommandBuffer is not in ready state.")
            return false
        }

        let bufferHolder = TemporaryBufferHolder(label: "VulkanCommandBuffer")
        var submitInfos: [VkSubmitInfo2] = []
        var commandBuffer: VkCommandBuffer? = nil

        let cleanup = { @Sendable [self] in
            if self.retainedCommandBuffers.isEmpty == false {
                var tmp = self.retainedCommandBuffers.map { Optional($0) }
                vkFreeCommandBuffers(device.device, commandPool, UInt32(tmp.count), &tmp)
            }
            self.retainedCommandBuffers.removeAll(keepingCapacity: true)
        }

        let recovery = Recovery()
        let revertChanges = {
            recovery.handlers.forEach { $0() }
            recovery.handlers.removeAll()
        }

        // for use across multiple submissions
        var waitSemaphores: [VkSemaphore: VulkanCommandEncoder.TimelineSemaphoreStageValue] = [:]
        var signalSemaphores: [VkSemaphore: VulkanCommandEncoder.TimelineSemaphoreStageValue] = [:]

        // for use within a single submission (batch)
        var batchWaitSemaphores: [VkSemaphore: VulkanCommandEncoder.TimelineSemaphoreStageValue] = [:]
        var batchSignalSemaphores: [VkSemaphore: VulkanCommandEncoder.TimelineSemaphoreStageValue] = [:]

        let closeSubmission = {
            var commandBufferSubmitInfos: [VkCommandBufferSubmitInfo] = []
            if commandBuffer != nil {
                vkEndCommandBuffer(commandBuffer)

                var cbufferSubmitInfo = VkCommandBufferSubmitInfo()
                cbufferSubmitInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO
                cbufferSubmitInfo.commandBuffer = commandBuffer
                cbufferSubmitInfo.deviceMask = 0
                commandBufferSubmitInfos.append(cbufferSubmitInfo)

                commandBuffer = nil
            }

            var batchSignal = signalSemaphores
            batchSignal.merge(batchSignalSemaphores) { (current, new) in
                var merged = current
                merged.value = max(current.value, new.value)
                merged.stages |= new.stages
                return merged
            }

            if commandBufferSubmitInfos.isEmpty == false || batchSignal.isEmpty == false {
                var submitInfo = VkSubmitInfo2()
                submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO_2

                if commandBufferSubmitInfos.isEmpty == false {
                    submitInfo.commandBufferInfoCount = UInt32(commandBufferSubmitInfos.count)
                    submitInfo.pCommandBufferInfos = unsafePointerCopy(collection: commandBufferSubmitInfos, holder: bufferHolder)
                }

                let transformSemaphoreSubmitInfo = {
                    (semaphore: VkSemaphore, stageValue: VulkanCommandEncoder.TimelineSemaphoreStageValue) in
                    let stages = stageValue.stages
                    let value = stageValue.value // timeline-value

                    assert((stages & VK_PIPELINE_STAGE_2_HOST_BIT) == 0)

                    var semaphoreSubmitInfo = VkSemaphoreSubmitInfo()
                    semaphoreSubmitInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO
                    semaphoreSubmitInfo.semaphore = semaphore
                    semaphoreSubmitInfo.value = value
                    semaphoreSubmitInfo.stageMask = stages
                    semaphoreSubmitInfo.deviceIndex = 0
                    return semaphoreSubmitInfo
                }

                var batchWait = waitSemaphores
                batchWait.merge(batchWaitSemaphores) { (current, new) in
                    var merged = current
                    merged.value = max(current.value, new.value)
                    merged.stages |= new.stages
                    return merged
                }

                if batchWait.isEmpty == false {
                    let waitSemaphoreInfos = batchWait.map(transformSemaphoreSubmitInfo)
                    submitInfo.waitSemaphoreInfoCount = UInt32(waitSemaphoreInfos.count)
                    submitInfo.pWaitSemaphoreInfos = unsafePointerCopy(collection: waitSemaphoreInfos, holder: bufferHolder)
                }
                if batchSignal.isEmpty == false {
                    let signalSemaphoreInfos = batchSignal.map(transformSemaphoreSubmitInfo)
                    submitInfo.signalSemaphoreInfoCount = UInt32(signalSemaphoreInfos.count)
                    submitInfo.pSignalSemaphoreInfos = unsafePointerCopy(collection: signalSemaphoreInfos, holder: bufferHolder)
                }
                submitInfos.append(submitInfo)

                batchWaitSemaphores.removeAll(keepingCapacity: true)
                batchSignalSemaphores.removeAll(keepingCapacity: true)
                signalSemaphores.removeAll(keepingCapacity: true)
            }
        }

        cleanup()
        for encoding in self.encodings {
            switch encoding {
            case .waitSemaphore(let semaphore):
                if signalSemaphores.isEmpty == false {
                    closeSubmission()
                }
                waitSemaphores[semaphore.semaphore] = .init(
                    stages: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                    value: 0)
            case .signalSemaphore(let semaphore):
                signalSemaphores[semaphore.semaphore] = .init(
                    stages: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                    value: 0)
            case .waitTimelineSemaphore(let semaphore, let value):
                if signalSemaphores.isEmpty == false {
                    closeSubmission()
                }
                if var p = waitSemaphores[semaphore.semaphore] {
                    p.value = max(p.value, value)
                    p.stages |= VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
                    waitSemaphores[semaphore.semaphore] = p
                } else {
                    waitSemaphores[semaphore.semaphore] = .init(
                        stages: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                        value: value)
                }
            case .signalTimelineSemaphore(let semaphore, let value):
                if var p = signalSemaphores[semaphore.semaphore] {
                    p.value = max(p.value, value)
                    p.stages |= VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
                    signalSemaphores[semaphore.semaphore] = p
                } else {
                    signalSemaphores[semaphore.semaphore] = .init(
                        stages: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                        value: value)
                }
            case .encoder(let encoder):
                if signalSemaphores.isEmpty == false {
                    closeSubmission()
                }
                if encoder.waitSemaphores.isEmpty == false {
                    closeSubmission()
                }

                assert(signalSemaphores.isEmpty)
                assert(batchSignalSemaphores.isEmpty)

                // merge wait semaphores
                batchWaitSemaphores.merge(encoder.waitSemaphores) { (current, new) in
                    var merged = current
                    merged.value = max(current.value, new.value)
                    merged.stages |= new.stages
                    return merged
                }
                batchSignalSemaphores = encoder.signalSemaphores

                if commandBuffer == nil {
                    var bufferInfo = VkCommandBufferAllocateInfo()
                    bufferInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
                    bufferInfo.commandPool = self.commandPool
                    bufferInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
                    bufferInfo.commandBufferCount = 1

                    let err = vkAllocateCommandBuffers(device.device, &bufferInfo, &commandBuffer)
                    if err != VK_SUCCESS {
                        Log.err("vkAllocateCommandBuffers failed: \(err)")
                        revertChanges()
                        cleanup()
                        return false
                    }

                    self.retainedCommandBuffers.append(commandBuffer!)

                    var commandBufferBeginInfo = VkCommandBufferBeginInfo()
                    commandBufferBeginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
                    commandBufferBeginInfo.flags = .init(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT.rawValue)
                    vkBeginCommandBuffer(commandBuffer, &commandBufferBeginInfo)
                }

                let result = Self.$recovery.withValue(recovery) {
                    encoder.encode(commandBuffer: commandBuffer!)
                }
                if result == false {
                    Log.err("CommandBuffer commit failed: Encoder error.")
                    revertChanges()
                    cleanup()
                    return false
                }

                if batchSignalSemaphores.isEmpty == false {
                    closeSubmission()
                }
            }
        }
        closeSubmission()

        if submitInfos.isEmpty == false {
            let commandQueue = self.commandQueue as! VulkanCommandQueue
            let result = commandQueue.submit(submitInfos) {
                let handlers = self.lock.withLock {
                    cleanup()
                    assert(self._status == .committed)
                    self._status = .ready
                    return self.completedHandlers
                }
                handlers.forEach { $0(self) }
            }
            if result {
                self._status = .committed
                return true 
            }
            Log.err("CommandBuffer.commit failed.")
        }

        revertChanges()
        cleanup()

        return false
    }

    func endEncoder(_ encoder: VulkanCommandEncoder) {
        self.lock.withLock {
            if self._status != .encoding {
                Log.warning("CommandBuffer was not in encoding state.")
            }
            self._status = .ready
            self.encodings.append(.encoder(encoder))
        }
    }

    var queueFamily: VulkanQueueFamily {
        return (self.commandQueue as! VulkanCommandQueue).family
    }
}
#endif //if ENABLE_VULKAN
