#if ENABLE_VULKAN
import Vulkan
import Foundation

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
                let image: VulkanImage = value.image
                let layout: VkImageLayout = value.layout
                let accessMask: VkAccessFlags = VulkanImage.commonAccessMask(forLayout: layout)

                image.setLayout(layout,
                                accessMask: accessMask,
                                stageBegin: UInt32(VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT.rawValue),
                                stageEnd: UInt32(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT.rawValue),
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
        assert(event as? VulkanSemaphore != nil)
        if let semaphore = event as? VulkanSemaphore {
            let pipelineStages: VkPipelineStageFlags = VkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue)
            self.encoder!.addWaitSemaphore(semaphore.semaphore, value: semaphore.nextWaitValue, flags: pipelineStages)
            self.encoder!.events.append(event)
        }
    }
    public func signalEvent(_ event: Event) {
        assert(event as? VulkanSemaphore != nil)
        if let semaphore = event as? VulkanSemaphore {
            self.encoder!.addSignalSemaphore(semaphore.semaphore, value: semaphore.nextWaitValue)
            self.encoder!.events.append(event)
        }
    }

    public func waitSemaphoreValue(_ sema: Semaphore, value: UInt64) {
        assert(sema as? VulkanTimelineSemaphore != nil)
        if let semaphore = sema as? VulkanTimelineSemaphore {
            let pipelineStages: VkPipelineStageFlags = VkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue)
            self.encoder!.addWaitSemaphore(semaphore.semaphore, value: value, flags: pipelineStages)
            self.encoder!.semaphores.append(sema)
        }
    }
    public func signalSemaphoreValue(_ sema: Semaphore, value: UInt64) {
        assert(sema as? VulkanTimelineSemaphore != nil)
        if let semaphore = sema as? VulkanTimelineSemaphore {
            self.encoder!.addSignalSemaphore(semaphore.semaphore, value: value)
            self.encoder!.semaphores.append(sema)
        }
    }
    
    public func setResource(_ set: ShaderBindingSet, atIndex index: UInt32) {
        var descriptorSet: VulkanDescriptorSet? = nil
        assert(set as? VulkanShaderBindingSet != nil)
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

    public func setComputePipelineState(_ pso: ComputePipelineState) {
        assert(pso as? VulkanComputePipelineState != nil)
        if let pipeline = pso as? VulkanComputePipelineState {
            let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
                vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.pipeline)
                state.pipelineState = pipeline
            }
            self.encoder!.commands.append(command)
            self.encoder!.pipelineStateObjects.append(pipeline)
        }
    }

    public func pushConstant<D: DataProtocol>(stages: [ShaderStage], offset: UInt32, data: D) {
        var stageFlags: UInt32 = 0
        for stage in stages {
            stageFlags |= stage.vkFlags()
        }

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

    public func dispatch(numGroupX: UInt32, numGroupY: UInt32, numGroupZ: UInt32) {
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            vkCmdDispatch(commandBuffer, numGroupX, numGroupY, numGroupZ)
        }
        self.encoder!.commands.append(command)
    }
}

#endif //if ENABLE_VULKAN
