//
//  File: VulkanRenderCommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

fileprivate let flipViewportY = true

extension VkDynamicState: @retroactive Hashable {}

final class VulkanRenderCommandEncoder: RenderCommandEncoder {

    struct EncodingState {
        var pipelineState: VulkanRenderPipelineState? = nil
        var depthStencilState: VulkanDepthStencilState? = nil
        var imageLayouts: VulkanDescriptorSet.ImageLayoutMap = [:]
        var imageViewLayouts: VulkanDescriptorSet.ImageViewLayoutMap = [:]
    }
    
    struct RenderContext {
        var renderingInfo: VkRenderingInfo
        var viewport: VkViewport
        var scissorRect: VkRect2D
        var colorAttachments: [(VulkanImageView, VkAttachmentLoadOp)]
        var colorResolveTargets: [VulkanImageView]
        var depthStencilAttachment: (VulkanImageView, VkAttachmentLoadOp)?
        var depthStencilResolveTarget: VulkanImageView?
        var _bufferHolder: TemporaryBufferHolder
    }

    final class Encoder: VulkanCommandEncoder {
        unowned let commandBuffer: VulkanCommandBuffer
        let device: VulkanGraphicsDevice
        let context: RenderContext

        var pipelineStateObjects: [VulkanRenderPipelineState] = []
        var descriptorSets: [VulkanDescriptorSet] = []
        var buffers: [GPUBuffer] = []
        var events: [GPUEvent] = []
        var semaphores: [GPUSemaphore] = []

        var framebuffer: VkFramebuffer?
        var renderPass: VkRenderPass?

        typealias Command = (VkCommandBuffer, inout EncodingState)->Void
        var commands: [Command] = []
        var setupCommands: [Command] = []
        var cleanupCommands: [Command] = []

        var drawCount = 0
        var setDynamicStates: Set<VkDynamicState> = []

        init(commandBuffer: VulkanCommandBuffer, context: RenderContext) {   
            self.commandBuffer = commandBuffer
            self.context = context
            self.device = commandBuffer.device as! VulkanGraphicsDevice
            super.init()

            self.commands.reserveCapacity(self.initialNumberOfCommands)
            self.setupCommands.reserveCapacity(self.initialNumberOfCommands)
            self.cleanupCommands.reserveCapacity(self.initialNumberOfCommands)

            let colorAttachments = context.colorAttachments.map(\.0) + context.colorResolveTargets
            let depthStencilAttachments = [context.depthStencilAttachment?.0, context.depthStencilResolveTarget].compactMap { $0 }

            for rt in colorAttachments {
                if rt.image != nil {
                    if let semaphore = rt.waitSemaphore {
                        self.addWaitSemaphore(semaphore, value: 0, flags: VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT)
                    }
                    if let semaphore = rt.signalSemaphore {
                        self.addSignalSemaphore(semaphore, value: 0, flags: VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT)
                    }
                }
            }
            for rt in depthStencilAttachments {
                if rt.image != nil {
                    if let semaphore = rt.waitSemaphore {
                        self.addWaitSemaphore(semaphore, value: 0, flags: VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT)
                    }
                    if let semaphore = rt.signalSemaphore {
                        self.addSignalSemaphore(semaphore, value: 0, flags: VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT)
                    }
                }
            }
        }

        deinit {
            if let renderPass = self.renderPass {
                vkDestroyRenderPass(device.device, renderPass, device.allocationCallbacks)
            }
            if let framebuffer = self.framebuffer {
                vkDestroyFramebuffer(device.device, framebuffer, device.allocationCallbacks)
            }
        }

        override func encode(commandBuffer: VkCommandBuffer) -> Bool {
            var state = EncodingState()

            // collect image layout transition
            for ds in self.descriptorSets {
                ds.collectImageViewLayouts(&state.imageLayouts, &state.imageViewLayouts)
            }
            for cmd in self.setupCommands {
                cmd(commandBuffer, &state)
            }
            // Set image layout transition
            state.imageLayouts.forEach { (key, value) in
                let image = value.image
                let layout = value.layout
                let accessMask = VulkanImage.commonAccessMask(forLayout: layout)

                image.setLayout(layout,
                                discardOldLayout: false,
                                accessMask: accessMask,
                                stageBegin: VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
                                stageEnd: VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
                                queueFamilyIndex: self.commandBuffer.queueFamily.familyIndex,
                                commandBuffer: commandBuffer)
            }

            // initialize attachment image layouts
            assert(context.colorAttachments.isEmpty == false || context.depthStencilAttachment != nil,
                   "RenderPass must have at least one color or depth/stencil attachment.")

            let discardOldLayoutFromLoadOp = { (loadOp: VkAttachmentLoadOp) in
                loadOp.rawValue & (VK_ATTACHMENT_LOAD_OP_DONT_CARE.rawValue | VK_ATTACHMENT_LOAD_OP_CLEAR.rawValue) != 0
            }

            for (colorAttachment, loadOp) in context.colorAttachments {
                if let image = colorAttachment.image {
                    image.setLayout(
                        VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                        discardOldLayout: discardOldLayoutFromLoadOp(loadOp),
                        accessMask: VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
                        stageBegin: VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                        stageEnd: VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                        queueFamilyIndex: self.commandBuffer.queueFamily.familyIndex,
                        commandBuffer: commandBuffer)
                }
            }
            for resolveTarget in context.colorResolveTargets {
                if let image = resolveTarget.image {
                    image.setLayout(
                        VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                        discardOldLayout: true,
                        accessMask: VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
                        stageBegin: VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                        stageEnd: VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                        queueFamilyIndex: self.commandBuffer.queueFamily.familyIndex,
                        commandBuffer: commandBuffer)
                }
            }
            if let (attachment, loadOp) = context.depthStencilAttachment {
                if let image = attachment.image {
                    image.setLayout(
                        VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
                        discardOldLayout: discardOldLayoutFromLoadOp(loadOp),
                        accessMask: VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                        stageBegin: VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
                        stageEnd: VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
                        queueFamilyIndex: self.commandBuffer.queueFamily.familyIndex,
                        commandBuffer: commandBuffer)
                }
            }
            if let image = context.depthStencilResolveTarget?.image {
                image.setLayout(
                    VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
                    discardOldLayout: true,
                    accessMask: VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                    stageBegin: VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
                    stageEnd: VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
                    queueFamilyIndex: self.commandBuffer.queueFamily.familyIndex,
                    commandBuffer: commandBuffer)
            }

            // begin render pass
            var renderingInfo = context.renderingInfo
            vkCmdBeginRendering(commandBuffer, &renderingInfo)

            // setup dynamic states to default.
            if setDynamicStates.contains(VK_DYNAMIC_STATE_VIEWPORT) == false {
                var viewport = context.viewport
                if flipViewportY {
                    viewport.y = viewport.y + viewport.height  // set origin to lower-left.
                    viewport.height = -(viewport.height) // negative height.
                }
                vkCmdSetViewport(commandBuffer, 0, 1, &viewport)
            }
            if setDynamicStates.contains(VK_DYNAMIC_STATE_SCISSOR) == false {
                var scissorRect = context.scissorRect
                vkCmdSetScissor(commandBuffer, 0, 1, &scissorRect)
            }
            if setDynamicStates.contains(VK_DYNAMIC_STATE_LINE_WIDTH) == false {
                vkCmdSetLineWidth(commandBuffer, 1.0)
            }
            if setDynamicStates.contains(VK_DYNAMIC_STATE_DEPTH_BIAS) == false {
                // NOTE - VkPipelineRasterizationStateCreateInfo.depthBiasEnable must be enabled.
                // vkCmdSetDepthBias(commandBuffer, 0, 0, 0)
            }
            if setDynamicStates.contains(VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE) == false {
                vkCmdSetDepthTestEnable(commandBuffer, VK_FALSE)
            }
            if setDynamicStates.contains(VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE) == false {
                vkCmdSetDepthWriteEnable(commandBuffer, VK_FALSE)
            }
            if setDynamicStates.contains(VK_DYNAMIC_STATE_DEPTH_COMPARE_OP) == false {
                vkCmdSetDepthCompareOp(commandBuffer, VK_COMPARE_OP_ALWAYS)
            }
            if setDynamicStates.contains(VK_DYNAMIC_STATE_STENCIL_TEST_ENABLE) == false {
                vkCmdSetStencilTestEnable(commandBuffer, VK_FALSE)
            }
            if setDynamicStates.contains(VK_DYNAMIC_STATE_STENCIL_OP) == false {
                vkCmdSetStencilOp(commandBuffer,
                                  VkStencilFaceFlags(VK_STENCIL_FACE_FRONT_AND_BACK.rawValue),
                                  VK_STENCIL_OP_KEEP, VK_STENCIL_OP_KEEP,
                                  VK_STENCIL_OP_KEEP, VK_COMPARE_OP_ALWAYS)
            }
            if setDynamicStates.contains(VK_DYNAMIC_STATE_DEPTH_BOUNDS_TEST_ENABLE) == false {
                vkCmdSetDepthBoundsTestEnable(commandBuffer, VK_FALSE)
            }
            if setDynamicStates.contains(VK_DYNAMIC_STATE_CULL_MODE) == false {
                vkCmdSetCullMode(commandBuffer, VkCullModeFlags(VK_CULL_MODE_NONE.rawValue))
            }
            if setDynamicStates.contains(VK_DYNAMIC_STATE_FRONT_FACE) == false {
                vkCmdSetFrontFace(commandBuffer, VK_FRONT_FACE_CLOCKWISE)
            }

            // recording commands
            for cmd in self.commands {
                cmd(commandBuffer, &state)
            }
            // end render pass
            vkCmdEndRendering(commandBuffer)

            // process post-renderpass commands
            for cmd in self.cleanupCommands {
                cmd(commandBuffer, &state)
            }

            return true
        }
    }

    private var encoder: Encoder?
    let commandBuffer: CommandBuffer

    init(buffer: VulkanCommandBuffer, context: RenderContext) {   
        self.commandBuffer = buffer
        self.encoder = Encoder(commandBuffer: buffer, context: context)
    }

    func endEncoding() {
        let commandBuffer = self.commandBuffer as! VulkanCommandBuffer
        commandBuffer.endEncoder(self.encoder!)
        self.encoder = nil
    }

    var isCompleted: Bool { self.encoder == nil }

    func waitEvent(_ event: GPUEvent) {
        assert(event is VulkanSemaphore)
        if let semaphore = event as? VulkanSemaphore {
            let pipelineStages = VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT
            self.encoder!.addWaitSemaphore(semaphore.semaphore, value: semaphore.nextWaitValue, flags: pipelineStages)
            self.encoder!.events.append(event)
        }
    }

    func signalEvent(_ event: GPUEvent) {
        assert(event is VulkanSemaphore)
        if let semaphore = event as? VulkanSemaphore {
            let pipelineStages = VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT 
            self.encoder!.addSignalSemaphore(semaphore.semaphore, value: semaphore.nextWaitValue, flags: pipelineStages)
            self.encoder!.events.append(event)
        }
    }

    func waitSemaphoreValue(_ sema: GPUSemaphore, value: UInt64) {
        assert(sema is VulkanTimelineSemaphore)
        if let semaphore = sema as? VulkanTimelineSemaphore {
            let pipelineStages = VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT
            self.encoder!.addWaitSemaphore(semaphore.semaphore, value: value, flags: pipelineStages)
            self.encoder!.semaphores.append(sema)
        }
    }
    
    func signalSemaphoreValue(_ sema: GPUSemaphore, value: UInt64) {
        assert(sema is VulkanTimelineSemaphore)
        if let semaphore = sema as? VulkanTimelineSemaphore {
            let pipelineStages = VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT
            self.encoder!.addSignalSemaphore(semaphore.semaphore, value: value, flags: pipelineStages)
            self.encoder!.semaphores.append(sema)
        }
    }
    
    func setResource(_ set: ShaderBindingSet, index: Int) {
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
                                            UInt32(index),
                                            1,
                                            &ds,
                                            0,      // dynamic offsets
                                            nil)
                }
            }
            self.encoder!.commands.append(command)
        }
    }

    func setRenderPipelineState(_ pso: RenderPipelineState) {
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

    func setViewport(_ v: Viewport) {
        var viewport = VkViewport(x: Float(v.x),
                                  y: Float(v.y),
                                  width: Float(v.width),
                                  height: Float(v.height),
                                  minDepth: Float(v.nearZ),
                                  maxDepth: Float(v.farZ))
        if flipViewportY {
            viewport.y = viewport.y + viewport.height // set origin to lower-left.
            viewport.height = -(viewport.height) // negative height.
        }
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            vkCmdSetViewport(commandBuffer, 0, 1, &viewport)
        }
        self.encoder!.commands.append(command)
        if self.encoder!.drawCount == 0 {
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_VIEWPORT)
        }
    }

    func setScissorRect(_ r: ScissorRect) {
        var scissorRect = VkRect2D(offset: VkOffset2D(x: Int32(r.x),
                                                      y: Int32(r.y)),
                                   extent: VkExtent2D(width: UInt32(r.width),
                                                      height: UInt32(r.height)))
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            vkCmdSetScissor(commandBuffer, 0, 1, &scissorRect)
        }
        self.encoder!.commands.append(command)
        if self.encoder!.drawCount == 0 {
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_SCISSOR)
        }
    }

    func setVertexBuffer(_ buffer: GPUBuffer, offset: Int, index: Int) {
        setVertexBuffers([buffer], offsets: [offset], index: index)
    }

    func setVertexBuffers(_ buffers: [GPUBuffer], offsets: [Int], index: Int) {
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
                    offsetArray.append(VkDeviceSize(offset))

                    self.encoder!.buffers.append(buffer)
                } else {
                    bufferArray.append(nil)
                    offsetArray.append(0)
                }
            }
            assert(bufferArray.count == count)
            assert(offsetArray.count == count)

            let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                vkCmdBindVertexBuffers(commandBuffer, UInt32(index), UInt32(count), &bufferArray, &offsetArray)
            }
            self.encoder!.commands.append(command)
        }
    }

    func setDepthStencilState(_ state: DepthStencilState?) {
        var depthStencilState: VulkanDepthStencilState? = nil
        if let state = state {
            assert(state is VulkanDepthStencilState)
            depthStencilState = state as? VulkanDepthStencilState
        }

        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            if let depthStencilState = depthStencilState {
                depthStencilState.bind(commandBuffer: commandBuffer)
            } else {
                // reset to default
                vkCmdSetDepthTestEnable(commandBuffer, VK_FALSE)
                vkCmdSetStencilTestEnable(commandBuffer, VK_FALSE)
                vkCmdSetDepthBoundsTestEnable(commandBuffer, VK_FALSE)
                
                if state.depthStencilState == nil {
                    vkCmdSetDepthCompareOp(commandBuffer, VK_COMPARE_OP_ALWAYS)
                    vkCmdSetDepthWriteEnable(commandBuffer, VK_FALSE)
                    vkCmdSetDepthBounds(commandBuffer, 0.0, 1.0)

                    let faceMask = VkStencilFaceFlags(VK_STENCIL_FACE_FRONT_AND_BACK.rawValue)
                    vkCmdSetStencilCompareMask(commandBuffer, faceMask, 0xffffffff)
                    vkCmdSetStencilWriteMask(commandBuffer, faceMask, 0xffffffff)
                    vkCmdSetStencilOp(commandBuffer, faceMask,
                                      VK_STENCIL_OP_KEEP, VK_STENCIL_OP_KEEP,
                                      VK_STENCIL_OP_KEEP, VK_COMPARE_OP_ALWAYS)
                }
            }
            state.depthStencilState = depthStencilState
        }
        self.encoder!.commands.append(command)
        if self.encoder!.drawCount == 0 {
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE)
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_STENCIL_TEST_ENABLE)
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_DEPTH_BOUNDS_TEST_ENABLE)

            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_DEPTH_COMPARE_OP)
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE)
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_DEPTH_BOUNDS)

            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK)
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_STENCIL_WRITE_MASK)
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_STENCIL_OP)
        }
    }

    func setDepthClipMode(_ mode: DepthClipMode) {

        if mode == .clamp && self.encoder!.device.features.depthClamp == 0 {
            Log.warn("\(#function): DepthClamp not supported for this hardware.")
        }

#if false
        // VK_EXT_extended_dynamic_state3

        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            switch mode {
            case .clip:
                vkCmdSetDepthClampEnableEXT(commandBuffer, VK_FALSE)
                vkCmdSetDepthClipEnableEXT(commandBuffer, VK_TRUE)
            case .clamp:
                vkCmdSetDepthClipEnableEXT(commandBuffer, VK_FALSE)
                vkCmdSetDepthClampEnableEXT(commandBuffer, VK_TRUE)
            }
        }
        self.encoder!.commands.append(command)
        if self.encoder!.drawCount == 0 {
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_DEPTH_CLIP_ENABLE_EXT)
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_DEPTH_CLAMP_ENABLE_EXT)
        }
#else
        if (mode == .clamp) {
            Log.err("\(#function) failed: VK_EXT_extended_dynamic_state3 is not supported.")
        }
#endif
    }

    func setCullMode(_ mode: CullMode) {
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            let flags = switch mode {
            case .none:     VkCullModeFlags(VK_CULL_MODE_NONE.rawValue)
            case .front:    VkCullModeFlags(VK_CULL_MODE_FRONT_BIT.rawValue)
            case .back:     VkCullModeFlags(VK_CULL_MODE_BACK_BIT.rawValue)
            }
            vkCmdSetCullMode(commandBuffer, flags)
        }
        self.encoder!.commands.append(command)
        if self.encoder!.drawCount == 0 {
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_CULL_MODE)
        }
    }

    func setFrontFacing(_ winding: Winding) {
           let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            let frontFace = switch winding {
            case .clockwise:        VkFrontFace(VK_FRONT_FACE_CLOCKWISE.rawValue)
            case .counterClockwise: VkFrontFace(VK_FRONT_FACE_COUNTER_CLOCKWISE.rawValue)
            }
            vkCmdSetFrontFace(commandBuffer, frontFace)
        }
        self.encoder!.commands.append(command)
        if self.encoder!.drawCount == 0 {
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_FRONT_FACE)
        }
    }

    func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) {
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            let blendConstants = (red, green, blue, alpha)
            withUnsafeBytes(of: blendConstants) {
                vkCmdSetBlendConstants(commandBuffer, $0.bindMemory(to: Float.self).baseAddress)
            }
        }
        self.encoder!.commands.append(command)
        if self.encoder!.drawCount == 0 {
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_BLEND_CONSTANTS)
        }
    }

    func setStencilReferenceValue(_ value: UInt32) {
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            vkCmdSetStencilReference(commandBuffer, VkStencilFaceFlags(VK_STENCIL_FACE_FRONT_AND_BACK.rawValue), value)
        }
        self.encoder!.commands.append(command)
        if self.encoder!.drawCount == 0 {
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_STENCIL_REFERENCE)
        }
    }

    func setStencilReferenceValues(front: UInt32, back: UInt32) {
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            vkCmdSetStencilReference(commandBuffer, VkStencilFaceFlags(VK_STENCIL_FACE_FRONT_BIT.rawValue), front)
            vkCmdSetStencilReference(commandBuffer, VkStencilFaceFlags(VK_STENCIL_FACE_BACK_BIT.rawValue), back)
        }
        self.encoder!.commands.append(command)
        if self.encoder!.drawCount == 0 {
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_STENCIL_REFERENCE)
        }
    }

    func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            vkCmdSetDepthBias(commandBuffer, depthBias, clamp, slopeScale)
        }
        self.encoder!.commands.append(command)
        if self.encoder!.drawCount == 0 {
            self.encoder!.setDynamicStates.insert(VK_DYNAMIC_STATE_DEPTH_BIAS)
        }
    }

    func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: Int, data: D) {
        let stageFlags = stages.vkFlags()
        if stageFlags != 0 && data.count > 0 {
            var buffer: [UInt8] = .init(data)
            assert(buffer.count == data.count)

            let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                if let pipelineState = state.pipelineState {
                    vkCmdPushConstants(commandBuffer,
                                       pipelineState.layout,
                                       stageFlags,
                                       UInt32(offset),
                                       UInt32(buffer.count),
                                       &buffer)
                }
            }
            self.encoder!.commands.append(command)
        }
    }
 
    func memoryBarrier(after: RenderStages, before: RenderStages) {

        let stageMask = { (stages: RenderStages) in
            var mask: VkPipelineStageFlags2 = VK_PIPELINE_STAGE_2_NONE
            if stages.contains(.vertex) {
                mask |= VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT
            }
            if stages.contains(.fragment) {
                mask |= VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT
            }
            if stages.contains(.object) {
                mask |= VK_PIPELINE_STAGE_2_TASK_SHADER_BIT_EXT
            }
            if stages.contains(.mesh) {
                mask |= VK_PIPELINE_STAGE_2_MESH_SHADER_BIT_EXT
            }
            return mask
        }

        let srcStages = stageMask(after)
        let dstStages = stageMask(before)

        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            var memoryBarrier = VkMemoryBarrier2()
            memoryBarrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2
            memoryBarrier.srcStageMask = srcStages
            memoryBarrier.srcAccessMask = VK_ACCESS_2_NONE
            memoryBarrier.dstStageMask = dstStages
            memoryBarrier.dstAccessMask = VK_ACCESS_2_NONE

            withUnsafePointer(to: memoryBarrier) { pMemoryBarriers in
                var dependencyInfo = VkDependencyInfo()
                dependencyInfo.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO
                dependencyInfo.memoryBarrierCount = 1
                dependencyInfo.pMemoryBarriers = pMemoryBarriers
                vkCmdPipelineBarrier2(commandBuffer, &dependencyInfo)
            }
        }
        self.encoder!.commands.append(command)
    }

    func draw(vertexStart: Int, vertexCount: Int, instanceCount: Int, baseInstance: Int) {
        if vertexCount > 0 && instanceCount > 0 {
            assert(vertexStart >= 0)
            assert(baseInstance >= 0)
            let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                vkCmdDraw(commandBuffer,
                          UInt32(vertexCount),
                          UInt32(instanceCount),
                          UInt32(vertexStart),
                          UInt32(baseInstance))
            }
            self.encoder!.commands.append(command)
            self.encoder!.drawCount += 1
        }
    }

    func drawIndexed(indexCount: Int, indexType: IndexType, indexBuffer: GPUBuffer, indexBufferOffset: Int, instanceCount: Int, baseVertex: Int, baseInstance: Int) {
        if indexCount > 0 && instanceCount > 0 {
            assert(indexBufferOffset >= 0)
            assert(baseVertex >= 0)
            assert(baseInstance >= 0)      

            assert(indexBuffer is VulkanBufferView)
            guard let bufferView = indexBuffer as? VulkanBufferView else { return }
            assert(bufferView.buffer != nil)
            guard let buffer = bufferView.buffer else { return }

            let type = switch indexType {
            case .uint16:   VK_INDEX_TYPE_UINT16
            case .uint32:   VK_INDEX_TYPE_UINT32
            }

            let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                vkCmdBindIndexBuffer(commandBuffer, buffer.buffer, VkDeviceSize(indexBufferOffset), type)
                vkCmdDrawIndexed(commandBuffer,
                                 UInt32(indexCount),
                                 UInt32(instanceCount),
                                 0,  // firstIndex = 0
                                 Int32(baseVertex),
                                 UInt32(baseInstance))
            }
            self.encoder!.buffers.append(bufferView)
            self.encoder!.commands.append(command)
            self.encoder!.drawCount += 1
        }
    }
}
#endif //if ENABLE_VULKAN
