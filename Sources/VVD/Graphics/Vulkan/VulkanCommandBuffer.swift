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
    let lock = NSLock()

    private let commandPool: VkCommandPool

    private var encoders: [VulkanCommandEncoder] = []
    private var submitInfos: [VkSubmitInfo2] = []
    private var commandBufferSubmitInfos: [VkCommandBufferSubmitInfo] = []

    private var bufferHolder: TemporaryBufferHolder?

    private var completedHandlers: [CommandBufferHandler] = []

    init(queue: VulkanCommandQueue, pool: VkCommandPool) {
        self.commandQueue = queue
        self.device = queue.device
        self.commandPool = pool
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        if self.commandBufferSubmitInfos.isEmpty == false {
            var tmp = self.commandBufferSubmitInfos.map { $0.commandBuffer }
            vkFreeCommandBuffers(device.device, commandPool, UInt32(tmp.count), &tmp)
        }
        vkDestroyCommandPool(device.device, commandPool, device.allocationCallbacks)
    }

    func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder? {
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

                renderContext.colorAttachments.append(imageView)

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

            renderContext.depthStencilAttachment = imageView

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

        let queue = self.commandQueue as! VulkanCommandQueue
        if queue.family.properties.queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue) != 0 {
            return VulkanRenderCommandEncoder(buffer: self, context: renderContext)
        }
        return nil
    }

    func makeComputeCommandEncoder() -> ComputeCommandEncoder? {
         let queue = self.commandQueue as! VulkanCommandQueue
        if queue.family.properties.queueFlags & UInt32(VK_QUEUE_COMPUTE_BIT.rawValue) != 0 {
            return VulkanComputeCommandEncoder(buffer: self)
        }
        return nil
    }

    func makeCopyCommandEncoder() -> CopyCommandEncoder? {
        return VulkanCopyCommandEncoder(buffer: self)
    }

    func addCompletedHandler(_ handler: @escaping CommandBufferHandler) {
        completedHandlers.append(handler)
    }

    @discardableResult
    func commit() -> Bool {
        let device = self.device as! VulkanGraphicsDevice

        self.lock.lock()
        defer { self.lock.unlock() }

        let cleanup = {
            if self.commandBufferSubmitInfos.isEmpty == false {
                var tmp = self.commandBufferSubmitInfos.map { $0.commandBuffer }
                vkFreeCommandBuffers(device.device,
                                     self.commandPool,
                                     UInt32(tmp.count),
                                     &tmp)
            }

            self.submitInfos = []
            self.commandBufferSubmitInfos = []
            self.bufferHolder = nil
        }

        if self.submitInfos.count != self.encoders.count {
            cleanup()

            let bufferHolder = TemporaryBufferHolder(label: "VulkanCommandBuffer")
            self.bufferHolder = bufferHolder

            var waitSemaphores: [VkSemaphoreSubmitInfo] = []
            var signalSemaphores: [VkSemaphoreSubmitInfo] = []

            // reserve storage for semaphores.
            let numWaitSemaphores = self.encoders.reduce(0) { max($0, $1.waitSemaphores.count) }
            let numSignalSemaphores = self.encoders.reduce(0) { max($0, $1.signalSemaphores.count) }
            waitSemaphores.reserveCapacity(numWaitSemaphores)
            signalSemaphores.reserveCapacity(numSignalSemaphores)

            self.commandBufferSubmitInfos.reserveCapacity(self.encoders.count)
            self.submitInfos.reserveCapacity(self.encoders.count)

            for encoder in self.encoders {
                waitSemaphores.removeAll(keepingCapacity: true)
                signalSemaphores.removeAll(keepingCapacity: true)

                let commandBuffersOffset = self.commandBufferSubmitInfos.count

                var bufferInfo = VkCommandBufferAllocateInfo()
                bufferInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
                bufferInfo.commandPool = self.commandPool
                bufferInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
                bufferInfo.commandBufferCount = 1

                var commandBuffer: VkCommandBuffer? = nil
                let err = vkAllocateCommandBuffers(device.device, &bufferInfo, &commandBuffer)
                if err != VK_SUCCESS {
                    Log.err("vkAllocateCommandBuffers failed: \(err)")
                    cleanup()
                    return false
                }
                var cbufferSubmitInfo = VkCommandBufferSubmitInfo()
                cbufferSubmitInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO
                cbufferSubmitInfo.commandBuffer = commandBuffer
                cbufferSubmitInfo.deviceMask = 0
                self.commandBufferSubmitInfos.append(cbufferSubmitInfo)

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
                waitSemaphores.append(contentsOf: encoder.waitSemaphores.map(transformSemaphoreSubmitInfo))
                signalSemaphores.append(contentsOf: encoder.signalSemaphores.map(transformSemaphoreSubmitInfo))

                // encode all commands.
                var commandBufferBeginInfo = VkCommandBufferBeginInfo()
                commandBufferBeginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO

                vkBeginCommandBuffer(commandBuffer, &commandBufferBeginInfo)
                let result = encoder.encode(commandBuffer: commandBuffer!)
                vkEndCommandBuffer(commandBuffer)

                if result == false {
                    cleanup()
                    return false
                }

                var submitInfo = VkSubmitInfo2()
                submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO_2

                if self.commandBufferSubmitInfos.count > commandBuffersOffset {
                    let count = self.commandBufferSubmitInfos.count - commandBuffersOffset
                    let commandBufferInfos = self.commandBufferSubmitInfos[commandBuffersOffset ..< commandBuffersOffset + count]
                    submitInfo.commandBufferInfoCount = UInt32(count)
                    submitInfo.pCommandBufferInfos = unsafePointerCopy(collection: commandBufferInfos, holder: bufferHolder)                  
                }

                if waitSemaphores.isEmpty == false {
                    submitInfo.waitSemaphoreInfoCount = UInt32(waitSemaphores.count)
                    submitInfo.pWaitSemaphoreInfos = unsafePointerCopy(collection: waitSemaphores, holder: bufferHolder)
                }
                if signalSemaphores.isEmpty == false {
                    submitInfo.signalSemaphoreInfoCount = UInt32(signalSemaphores.count)
                    submitInfo.pSignalSemaphoreInfos = unsafePointerCopy(collection: signalSemaphores, holder: bufferHolder)
                }
                self.submitInfos.append(submitInfo)
            }
        }

        if self.submitInfos.isEmpty == false {
            assert(self.submitInfos.count == self.encoders.count)

            let commandQueue = self.commandQueue as! VulkanCommandQueue
            return commandQueue.submit(self.submitInfos) {
                self.completedHandlers.forEach { $0(self) }
            }
        }

        return false
    }

    func endEncoder(_ encoder: VulkanCommandEncoder) {
        self.encoders.append(encoder)
    }

    var queueFamily: VulkanQueueFamily {
        return (self.commandQueue as! VulkanCommandQueue).family
    }
}
#endif //if ENABLE_VULKAN
