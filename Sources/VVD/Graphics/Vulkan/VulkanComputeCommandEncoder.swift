//
//  File: VulkanComputeCommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanComputeCommandEncoder: ComputeCommandEncoder {

    struct EncodingState {
        var pipelineState: VulkanComputePipelineState?
        var imageLayouts: VulkanDescriptorSet.ImageLayoutMap = [:]
        var imageViewLayouts: VulkanDescriptorSet.ImageViewLayoutMap = [:]
    }

    final class Encoder: VulkanCommandEncoder {
        unowned let commandBuffer: VulkanCommandBuffer

        var pipelineStateObjects: [VulkanComputePipelineState] = []
        var descriptorSets: [VulkanDescriptorSet] = []
        var buffers: [GPUBuffer] = []
        var events: [GPUEvent] = []
        var semaphores: [GPUSemaphore] = []

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
                                discardOldLayout: false,
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
    let commandBuffer: CommandBuffer

    init(buffer: VulkanCommandBuffer) {   
        self.commandBuffer = buffer
        self.encoder = Encoder(commandBuffer: buffer)
    }

    func reset(descriptor: RenderPassDescriptor) {   
        self.encoder = Encoder(commandBuffer: self.commandBuffer as! VulkanCommandBuffer)
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
            let pipelineStages = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT
            self.encoder!.addWaitSemaphore(semaphore.semaphore, value: semaphore.nextWaitValue, flags: pipelineStages)
            self.encoder!.events.append(event)
        }
    }

    func signalEvent(_ event: GPUEvent) {
        assert(event is VulkanSemaphore)
        if let semaphore = event as? VulkanSemaphore {
            let pipelineStages = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT 
            self.encoder!.addSignalSemaphore(semaphore.semaphore, value: semaphore.nextWaitValue, flags: pipelineStages)
            self.encoder!.events.append(event)
        }
    }

    func waitSemaphoreValue(_ sema: GPUSemaphore, value: UInt64) {
        assert(sema is VulkanTimelineSemaphore)
        if let semaphore = sema as? VulkanTimelineSemaphore {
            let pipelineStages = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT 
            self.encoder!.addWaitSemaphore(semaphore.semaphore, value: value, flags: pipelineStages)
            self.encoder!.semaphores.append(sema)
        }
    }

    func signalSemaphoreValue(_ sema: GPUSemaphore, value: UInt64) {
        assert(sema is VulkanTimelineSemaphore)
        if let semaphore = sema as? VulkanTimelineSemaphore {
            let pipelineStages = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT 
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

    func setComputePipelineState(_ pso: ComputePipelineState) {
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

    func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: Int, data: D) {
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

    func memoryBarrier() {
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            var memoryBarrier = VkMemoryBarrier2()
            memoryBarrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2
            memoryBarrier.srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT
            memoryBarrier.srcAccessMask = VK_ACCESS_2_NONE
            memoryBarrier.dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT
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

    func dispatch(numGroupX: Int, numGroupY: Int, numGroupZ: Int) {
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            vkCmdDispatch(commandBuffer, UInt32(numGroupX), UInt32(numGroupY), UInt32(numGroupZ))
        }
        self.encoder!.commands.append(command)
    }
}
#endif //if ENABLE_VULKAN
