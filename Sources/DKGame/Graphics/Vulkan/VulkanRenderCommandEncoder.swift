#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanRenderCommandEncoder: RenderCommandEncoder {

    struct EncodingState {
        var encoder: VulkanRenderCommandEncoder
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
        }

        override func encode(commandBuffer: VkCommandBuffer) -> Bool {
            false
        }
    }
    private var encoder: Encoder?
    public let commandBuffer: CommandBuffer

    let flipViewportY = true

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
        assert(pso as? VulkanRenderPipelineState != nil)
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
        if self.flipViewportY {
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
                assert(buffer as? VulkanBufferView != nil)
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
        assert(buffer as? VulkanBufferView != nil)
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
