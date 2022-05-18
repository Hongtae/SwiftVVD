#if ENABLE_VULKAN
import Vulkan
import Foundation

fileprivate let flipViewportY = true

public class VulkanRenderCommandEncoder: RenderCommandEncoder {

    struct EncodingState {
        var pipelineState: VulkanRenderPipelineState? = nil
        var imageLayouts: VulkanDescriptorSet.ImageLayoutMap = [:]
        var imageViewLayouts: VulkanDescriptorSet.ImageViewLayoutMap = [:]
    }
    
    class Encoder: VulkanCommandEncoder {
        let renderPassDescriptor: RenderPassDescriptor
        unowned let commandBuffer: VulkanCommandBuffer

        var pipelineStateObjects: [VulkanRenderPipelineState] = []
        var descriptorSets: [VulkanDescriptorSet] = []
        var buffers: [Buffer] = []
        var events: [Event] = []
        var semaphores: [Semaphore] = []

        var framebuffer: VkFramebuffer?
        var renderPass: VkRenderPass?

        typealias Command = (VkCommandBuffer, inout EncodingState)->Void
        var commands: [Command] = []
        var setupCommands: [Command] = []
        var cleanupCommands: [Command] = []

        init(commandBuffer: VulkanCommandBuffer, descriptor: RenderPassDescriptor) {   
            self.commandBuffer = commandBuffer
            self.renderPassDescriptor = descriptor
            super.init()

            self.commands.reserveCapacity(self.initialNumberOfCommands)
            self.setupCommands.reserveCapacity(self.initialNumberOfCommands)
            self.cleanupCommands.reserveCapacity(self.initialNumberOfCommands)

            for colorAttachment in renderPassDescriptor.colorAttachments {
                if let rt = colorAttachment.renderTarget as? VulkanImageView, rt.image != nil {
                    if let semaphore = rt.waitSemaphore {
                        self.addWaitSemaphore(semaphore, value: 0, flags: UInt32(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue))
                    }
                    if let semaphore = rt.signalSemaphore {
                        self.addSignalSemaphore(semaphore, value: 0)
                    }
                }
            }
            if let rt = renderPassDescriptor.depthStencilAttachment.renderTarget as? VulkanImageView, rt.image != nil {
                if let semaphore = rt.waitSemaphore {
                    self.addWaitSemaphore(semaphore, value: 0, flags: UInt32(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue))
                }
                if let semaphore = rt.signalSemaphore {
                    self.addSignalSemaphore(semaphore, value: 0)
                }
            }
        }

        deinit {
            let device = self.commandBuffer.device as! VulkanGraphicsDevice

            if let renderPass = self.renderPass {
                vkDestroyRenderPass(device.device, renderPass, device.allocationCallbacks)
            }
            if let framebuffer = self.framebuffer {
                vkDestroyFramebuffer(device.device, framebuffer, device.allocationCallbacks)
            }
        }

        override func encode(commandBuffer: VkCommandBuffer) -> Bool {
            var state = EncodingState()

            // initialize render pass
            var frameWidth: UInt32 = 0
            var frameHeight: UInt32 = 0

            var attachments: [VkAttachmentDescription] = []
            attachments.reserveCapacity(self.renderPassDescriptor.colorAttachments.count + 1)
            var colorReferences: [VkAttachmentReference] = []
            colorReferences.reserveCapacity(self.renderPassDescriptor.colorAttachments.count)
            var framebufferImageViews: [VkImageView] = []
            framebufferImageViews.reserveCapacity(self.renderPassDescriptor.colorAttachments.count + 1)
            var attachmentClearValues: [VkClearValue] = []
            attachmentClearValues.reserveCapacity(self.renderPassDescriptor.colorAttachments.count + 1)

            for colorAttachment in self.renderPassDescriptor.colorAttachments {
                if let rt = colorAttachment.renderTarget as? VulkanImageView,
                   let image = rt.image {
                    var attachment = VkAttachmentDescription()
                    attachment.format = image.format
                    attachment.samples = VK_SAMPLE_COUNT_1_BIT // 1 sample per pixel
                    switch colorAttachment.loadAction {
                    case .load:
                        attachment.loadOp = VK_ATTACHMENT_LOAD_OP_LOAD
                    case .clear:
                        attachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
                    default:
                        attachment.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
                    }
                    switch colorAttachment.storeAction {
                    case .dontCare:
                        attachment.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
                    case .store:
                        attachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE
                    }
                    attachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
                    attachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
                    attachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
                    attachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
                    let currentLayout = image.setLayout(attachment.finalLayout,
                        accessMask: VkAccessFlags(VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue),
                        stageBegin: UInt32(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue),
                        stageEnd: UInt32(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue))
                    if attachment.loadOp == VK_ATTACHMENT_LOAD_OP_LOAD {
                        attachment.initialLayout = currentLayout
                    }

                    var attachmentReference = VkAttachmentReference()
                    attachmentReference.attachment = UInt32(attachments.count)
                    attachmentReference.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL

                    attachments.append(attachment)
                    colorReferences.append(attachmentReference)

                    framebufferImageViews.append(rt.imageView)

                    var clearValue = VkClearValue()
                    clearValue.color.float32 = (Float32(colorAttachment.clearColor.r),
                                                Float32(colorAttachment.clearColor.g),
                                                Float32(colorAttachment.clearColor.b),
                                                Float32(colorAttachment.clearColor.a))
                    attachmentClearValues.append(clearValue)

                    frameWidth = (frameWidth > 0) ? min(frameWidth, rt.width) : rt.width
                    frameHeight = (frameHeight > 0) ? min(frameHeight, rt.height) : rt.height
                }
            }

            var depthStencilReference = VkAttachmentReference()
            depthStencilReference.attachment = VK_ATTACHMENT_UNUSED
            depthStencilReference.layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL

            if let rt = self.renderPassDescriptor.depthStencilAttachment.renderTarget as? VulkanImageView,
               let image = rt.image {
                var attachment = VkAttachmentDescription()
                attachment.format = image.format
                attachment.samples = VK_SAMPLE_COUNT_1_BIT
                switch self.renderPassDescriptor.depthStencilAttachment.loadAction {
                case .load:
                    attachment.loadOp = VK_ATTACHMENT_LOAD_OP_LOAD
                case .clear:
                    attachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
                default:
                    attachment.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
                }
                switch self.renderPassDescriptor.depthStencilAttachment.storeAction {
                case .store:
                    attachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE
                default:
                    attachment.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
                }
                attachment.stencilLoadOp = attachment.loadOp
                attachment.stencilStoreOp = attachment.storeOp
                attachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
                attachment.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
                let currentLayout = image.setLayout(attachment.finalLayout,
                    accessMask: VkAccessFlags(VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT.rawValue),
                    stageBegin: UInt32(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue),
                    stageEnd: UInt32(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT.rawValue))

                if attachment.loadOp == VK_ATTACHMENT_LOAD_OP_LOAD {
                    attachment.initialLayout = currentLayout
                }

                depthStencilReference.attachment = UInt32(attachments.count)
                attachments.append(attachment)

                framebufferImageViews.append(rt.imageView)

                var clearValue = VkClearValue()
                clearValue.depthStencil.depth = self.renderPassDescriptor.depthStencilAttachment.clearDepth
                clearValue.depthStencil.stencil = self.renderPassDescriptor.depthStencilAttachment.clearStencil
                attachmentClearValues.append(clearValue)

                frameWidth = (frameWidth > 0) ? min(frameWidth, rt.width) : rt.width
                frameHeight = (frameHeight > 0) ? min(frameHeight, rt.height) : rt.height
            }

            let tempHolder = TemporaryBufferHolder(label: "VulkanRenderCommandEncoder.Encoder.encode")

            var subpassDescription = VkSubpassDescription()
            subpassDescription.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
            subpassDescription.colorAttachmentCount = UInt32(colorReferences.count)
            subpassDescription.pColorAttachments = unsafePointerCopy(collection: colorReferences, holder: tempHolder)
            subpassDescription.pDepthStencilAttachment = unsafePointerCopy(from: depthStencilReference, holder: tempHolder)
            subpassDescription.inputAttachmentCount = 0
            subpassDescription.pInputAttachments = nil
            subpassDescription.preserveAttachmentCount = 0
            subpassDescription.pPreserveAttachments = nil
            subpassDescription.pResolveAttachments = nil

            var renderPassCreateInfo = VkRenderPassCreateInfo()
            renderPassCreateInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
            renderPassCreateInfo.attachmentCount = UInt32(attachments.count)
            renderPassCreateInfo.pAttachments = unsafePointerCopy(collection: attachments, holder: tempHolder)
            renderPassCreateInfo.subpassCount = 1
            renderPassCreateInfo.pSubpasses = unsafePointerCopy(from: subpassDescription, holder: tempHolder)

            let device = self.commandBuffer.device as! VulkanGraphicsDevice
            var err = vkCreateRenderPass(device.device, &renderPassCreateInfo, device.allocationCallbacks, &self.renderPass)
            if err != VK_SUCCESS {
                Log.err("vkCreateRenderPass failed: \(err)")
                return false
            }

            var framebufferCreateInfo = VkFramebufferCreateInfo()
            framebufferCreateInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
            framebufferCreateInfo.renderPass = self.renderPass;
            framebufferCreateInfo.attachmentCount = UInt32(framebufferImageViews.count)
            framebufferCreateInfo.pAttachments = unsafePointerCopy(collection: framebufferImageViews, holder: tempHolder)
            framebufferCreateInfo.width = frameWidth
            framebufferCreateInfo.height = frameHeight
            framebufferCreateInfo.layers = 1
            err = vkCreateFramebuffer(device.device, &framebufferCreateInfo, device.allocationCallbacks, &self.framebuffer)
            if err != VK_SUCCESS {
                Log.err("vkCreateFramebuffer failed: \(err)")
                return false
            }

            // collect image layout transition
            for ds in self.descriptorSets {
                ds.collectImageViewLayouts(&state.imageLayouts, &state.imageViewLayouts)
            }
            for cmd in self.setupCommands {
                cmd(commandBuffer, &state)
            }
            // Set image layout transition
            state.imageLayouts.forEach { (key, value) in
                let image: VulkanImage = value.image
                let layout: VkImageLayout = value.layout
                let accessMask: VkAccessFlags = VulkanImage.commonAccessMask(forLayout: layout)

                image.setLayout(layout,
                                accessMask: accessMask,
                                stageBegin: UInt32(VK_PIPELINE_STAGE_VERTEX_SHADER_BIT.rawValue),
                                stageEnd: UInt32(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT.rawValue),
                                queueFamilyIndex: self.commandBuffer.queueFamily.familyIndex,
                                commandBuffer: commandBuffer)
            }

            // begin render pass
            var renderPassBeginInfo = VkRenderPassBeginInfo()
            renderPassBeginInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
            renderPassBeginInfo.renderPass = self.renderPass
            renderPassBeginInfo.clearValueCount = UInt32(attachmentClearValues.count)
            renderPassBeginInfo.pClearValues = unsafePointerCopy(collection: attachmentClearValues, holder: tempHolder)
            renderPassBeginInfo.renderArea.offset.x = 0
            renderPassBeginInfo.renderArea.offset.y = 0
            renderPassBeginInfo.renderArea.extent.width = frameWidth
            renderPassBeginInfo.renderArea.extent.height = frameHeight
            renderPassBeginInfo.framebuffer = self.framebuffer
            vkCmdBeginRenderPass(commandBuffer, &renderPassBeginInfo, VK_SUBPASS_CONTENTS_INLINE)

            // setup viewport
            var viewport = VkViewport(x: 0.0,
                                      y: 0.0,
                                      width: Float(frameWidth),
                                      height: Float(frameHeight),
                                      minDepth: 0.0,
                                      maxDepth: 1.0)
            if flipViewportY {
                viewport.y = viewport.y + viewport.height  // set origin to lower-left.
                viewport.height = -(viewport.height) // negative height.
            }
            vkCmdSetViewport(commandBuffer, 0, 1, &viewport)

            // setup scissor
            var scissorRect = VkRect2D(offset: VkOffset2D(x: 0, y: 0),
                                       extent: VkExtent2D(width: frameWidth, height: frameHeight))
            vkCmdSetScissor(commandBuffer, 0, 1, &scissorRect)

            // recording commands
            for cmd in self.commands {
                cmd(commandBuffer, &state)
            }
            // end render pass
            vkCmdEndRenderPass(commandBuffer)

            // process post-renderpass commands
            for cmd in self.cleanupCommands {
                cmd(commandBuffer, &state)
            }
            return true
        }
    }
    private var encoder: Encoder?
    public let commandBuffer: CommandBuffer

    public init(buffer: VulkanCommandBuffer, descriptor: RenderPassDescriptor) {   
        self.commandBuffer = buffer
        self.encoder = Encoder(commandBuffer: buffer, descriptor: descriptor)
    }

    public func reset(descriptor: RenderPassDescriptor) {   
        self.encoder = Encoder(commandBuffer: self.commandBuffer as! VulkanCommandBuffer, descriptor: descriptor)
    }

    public func endEncoding() {
        let commandBuffer = self.commandBuffer as! VulkanCommandBuffer
        commandBuffer.endEncoder(self.encoder!)
        self.encoder = nil
    }

    public var isCompleted: Bool { self.encoder == nil }

    public func waitEvent(_ event: Event) {
        assert(event is VulkanSemaphore)
        if let semaphore = event as? VulkanSemaphore {
            let pipelineStages: VkPipelineStageFlags = VkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue)
            self.encoder!.addWaitSemaphore(semaphore.semaphore, value: semaphore.nextWaitValue, flags: pipelineStages)
            self.encoder!.events.append(event)
        }
    }
    public func signalEvent(_ event: Event) {
        assert(event is VulkanSemaphore)
        if let semaphore = event as? VulkanSemaphore {
            self.encoder!.addSignalSemaphore(semaphore.semaphore, value: semaphore.nextWaitValue)
            self.encoder!.events.append(event)
        }
    }

    public func waitSemaphoreValue(_ sema: Semaphore, value: UInt64) {
        assert(sema is VulkanTimelineSemaphore)
        if let semaphore = sema as? VulkanTimelineSemaphore {
            let pipelineStages: VkPipelineStageFlags = VkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue)
            self.encoder!.addWaitSemaphore(semaphore.semaphore, value: value, flags: pipelineStages)
            self.encoder!.semaphores.append(sema)
        }
    }
    public func signalSemaphoreValue(_ sema: Semaphore, value: UInt64) {
        assert(sema is VulkanTimelineSemaphore)
        if let semaphore = sema as? VulkanTimelineSemaphore {
            self.encoder!.addSignalSemaphore(semaphore.semaphore, value: value)
            self.encoder!.semaphores.append(sema)
        }
    }
    
    public func setResource(_ set: ShaderBindingSet, atIndex index: UInt32) {
        assert(set is VulkanShaderBindingSet)
        var descriptorSet: VulkanDescriptorSet? = nil
        if let bindingSet = set as? VulkanShaderBindingSet {
            descriptorSet = bindingSet.makeDescriptorSet()
            self.encoder!.descriptorSets.append(descriptorSet!)
        }
        if let descriptorSet = descriptorSet {
            let preCommand = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                descriptorSet.updateImageViewLayouts(state.imageViewLayouts)
            }
            self.encoder!.setupCommands.append(preCommand)

            let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                if let pipelineState = state.pipelineState {
                    var ds: VkDescriptorSet? = descriptorSet.descriptorSet
                    vkCmdBindDescriptorSets(commandBuffer,
                                            VK_PIPELINE_BIND_POINT_GRAPHICS,
                                            pipelineState.layout,
                                            index,
                                            1,
                                            &ds,
                                            0,      // dynamic offsets
                                            nil)
                }
            }
            self.encoder!.commands.append(command)
        }
    }

    public func setRenderPipelineState(_ pso: RenderPipelineState) {
        assert(pso is VulkanRenderPipelineState)
        if let pipeline = pso as? VulkanRenderPipelineState {
            let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline)
                state.pipelineState = pipeline
            }
            self.encoder!.commands.append(command)
            self.encoder!.pipelineStateObjects.append(pipeline)
        }
    }

    public func setViewport(_ v: Viewport) {
        var viewport = VkViewport(x: v.x,
                                  y: v.y,
                                  width: v.width,
                                  height: v.height,
                                  minDepth: v.nearZ,
                                  maxDepth: v.farZ)
        if flipViewportY {
            viewport.y = viewport.y + viewport.height // set origin to lower-left.
            viewport.height = -(viewport.height) // negative height.
        }
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            vkCmdSetViewport(commandBuffer, 0, 1, &viewport)
        }
        self.encoder!.commands.append(command)
    }

    public func setVertexBuffer(_ buffer: Buffer, offset: UInt64, index: UInt32) {
        setVertexBuffers([buffer], offsets: [offset], index: index)
    }

    public func setVertexBuffers(_ buffers: [Buffer], offsets: [UInt64], index: UInt32) {
        assert(buffers.count == offsets.count)
        let count = min(buffers.count, offsets.count)
        if count > 0 {
            var bufferArray: [VkBuffer?] = []
            var offsetArray: [VkDeviceSize] = []
            bufferArray.reserveCapacity(count)
            offsetArray.reserveCapacity(count)

            for (buffer, offset) in zip(buffers, offsets) {
                assert(buffer is VulkanBufferView)
                if let bufferView = buffer as? VulkanBufferView {
                    assert(bufferView.buffer != nil)
                    bufferArray.append(bufferView.buffer!.buffer)
                    offsetArray.append(offset)

                    self.encoder!.buffers.append(buffer)
                } else {
                    bufferArray.append(nil)
                    offsetArray.append(0)
                }
            }
            assert(bufferArray.count == count)
            assert(offsetArray.count == count)

            let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                vkCmdBindVertexBuffers(commandBuffer, index, UInt32(count), &bufferArray, &offsetArray)
            }
            self.encoder!.commands.append(command)
        }
    }

    public func setIndexBuffer(_ buffer: Buffer, offset: UInt64, type: IndexType) {
        assert(buffer is VulkanBufferView)
        guard let bufferView = buffer as? VulkanBufferView else { return }
        assert(bufferView.buffer != nil)
        guard let buffer = bufferView.buffer else { return }

        var indexType: VkIndexType
        switch (type) {
            case .uint16:   indexType = VK_INDEX_TYPE_UINT16
            case .uint32:   indexType = VK_INDEX_TYPE_UINT32
        }
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            vkCmdBindIndexBuffer(commandBuffer, buffer.buffer, offset, indexType)
        }
        self.encoder!.buffers.append(bufferView)
        self.encoder!.commands.append(command)
    }
 
    public func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: UInt32, data: D) {
        let stageFlags = stages.vkFlags()
        if stageFlags != 0 && data.count > 0 {
            var buffer: [UInt8] = .init(data)
            assert(buffer.count == data.count)

            let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                if let pipelineState = state.pipelineState {
                    vkCmdPushConstants(commandBuffer,
                                       pipelineState.layout,
                                       stageFlags,
                                       offset,
                                       UInt32(buffer.count),
                                       &buffer)
                }
            }
            self.encoder!.commands.append(command)
        }       
    }
 
    public func draw(numVertices: UInt32, numInstances: UInt32, baseVertex: UInt32, baseInstance: UInt32) {
        if numInstances > 0 {
            let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                vkCmdDraw(commandBuffer, numVertices, numInstances, baseVertex, baseInstance)
            }
            self.encoder!.commands.append(command)
        }
    }

    public func drawIndexed(numIndices: UInt32, numInstances: UInt32, indexOffset: UInt32, vertexOffset: Int32, baseInstance: UInt32) {
        if numInstances > 0 {
            let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                vkCmdDrawIndexed(commandBuffer, numIndices, numInstances, indexOffset, vertexOffset, baseInstance)
            }
            self.encoder!.commands.append(command)            
        }
    }
}

#endif //if ENABLE_VULKAN
