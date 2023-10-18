//
//  File: VulkanComputeCommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanComputeCommandEncoder: VulkanCommandEncoder, ComputeCommandEncoder {

    struct EncodingState {
        var pipelineState: VulkanComputePipelineState?
        var imageLayouts: VulkanDescriptorSet.ImageLayoutMap = [:]
        var imageViewLayouts: VulkanDescriptorSet.ImageViewLayoutMap = [:]
    }

    class Encoder: VulkanCommandEncoder {
        unowned let commandBuffer: VulkanCommandBuffer

        var pipelineStateObjects: [VulkanComputePipelineState] = []
        var descriptorSets: [VulkanDescriptorSet] = []
        var buffers: [Buffer] = []
        var events: [Event] = []
        var semaphores: [Semaphore] = []

        typealias Command = (VkCommandBuffer, inout EncodingState)->Void
        var commands: [Command] = []
        var setupCommands: [Command] = []
        var cleanupCommands: [Command] = []

        init(commandBuffer: VulkanCommandBuffer) {
            self.commandBuffer = commandBuffer
            super.init()

            self.commands.reserveCapacity(self.initialNumberOfCommands)
            self.setupCommands.reserveCapacity(self.initialNumberOfCommands)
            self.cleanupCommands.reserveCapacity(self.initialNumberOfCommands)
        }

        override func encode(commandBuffer: VkCommandBuffer) -> Bool {
            var state = EncodingState()
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
                                accessMask: accessMask,
                                stageBegin: VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                                stageEnd: VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                                queueFamilyIndex: self.commandBuffer.queueFamily.familyIndex,
                                commandBuffer: commandBuffer)
            }
            for cmd in self.commands {
                cmd(commandBuffer, &state)
            }
            for cmd in self.cleanupCommands {
                cmd(commandBuffer, &state)
            }
            return true
        }        
    }
    
    private var encoder: Encoder?
    public let commandBuffer: CommandBuffer

    public init(buffer: VulkanCommandBuffer) {   
        self.commandBuffer = buffer
        self.encoder = Encoder(commandBuffer: buffer)
    }

    public func reset(descriptor: RenderPassDescriptor) {   
        self.encoder = Encoder(commandBuffer: self.commandBuffer as! VulkanCommandBuffer)
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
            let pipelineStages = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT
            self.encoder!.addWaitSemaphore(semaphore.semaphore, value: semaphore.nextWaitValue, flags: pipelineStages)
            self.encoder!.events.append(event)
        }
    }
    public func signalEvent(_ event: Event) {
        assert(event is VulkanSemaphore)
        if let semaphore = event as? VulkanSemaphore {
            let pipelineStages = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT 
            self.encoder!.addSignalSemaphore(semaphore.semaphore, value: semaphore.nextWaitValue, flags: pipelineStages)
            self.encoder!.events.append(event)
        }
    }

    public func waitSemaphoreValue(_ sema: Semaphore, value: UInt64) {
        assert(sema is VulkanTimelineSemaphore)
        if let semaphore = sema as? VulkanTimelineSemaphore {
            let pipelineStages = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT 
            self.encoder!.addWaitSemaphore(semaphore.semaphore, value: value, flags: pipelineStages)
            self.encoder!.semaphores.append(sema)
        }
    }
    public func signalSemaphoreValue(_ sema: Semaphore, value: UInt64) {
        assert(sema is VulkanTimelineSemaphore)
        if let semaphore = sema as? VulkanTimelineSemaphore {
            let pipelineStages = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT 
            self.encoder!.addSignalSemaphore(semaphore.semaphore, value: value, flags: pipelineStages)
            self.encoder!.semaphores.append(sema)
        }
    }
    
    public func setResource(_ set: ShaderBindingSet, atIndex index: Int) {
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
                                            VK_PIPELINE_BIND_POINT_COMPUTE,
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

    public func setComputePipelineState(_ pso: ComputePipelineState) {
        assert(pso is VulkanComputePipelineState)
        if let pipeline = pso as? VulkanComputePipelineState {
            let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.pipeline)
                state.pipelineState = pipeline
            }
            self.encoder!.commands.append(command)
            self.encoder!.pipelineStateObjects.append(pipeline)
        }
    }

    public func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: Int, data: D) {
        if stages.contains(.compute) && data.count > 0 {
            let stageFlags = stages.vkFlags()
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

    public func dispatch(numGroupX: Int, numGroupY: Int, numGroupZ: Int) {
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            vkCmdDispatch(commandBuffer, UInt32(numGroupX), UInt32(numGroupY), UInt32(numGroupZ))
        }
        self.encoder!.commands.append(command)
    }
}

#endif //if ENABLE_VULKAN
