#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanRenderCommandEncoder: RenderCommandEncoder {

    struct EncodingState {
        var encoder: VulkanRenderCommandEncoder
        var pipelineState: VulkanRenderPipelineState? = nil
        var imageLayouts: VulkanDescriptorSet.ImageLayoutMap = [:]
        var imageViewLayouts: VulkanDescriptorSet.ImageViewLayoutMap = [:]
        var bindingSets: [ObjectIdentifier: VulkanDescriptorSet] = [:]
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

        init(buffer: VulkanCommandBuffer, descriptor: RenderPassDescriptor) {   
            self.commandBuffer = buffer
            self.renderPassDescriptor = descriptor
        }

        override func encode(commandBuffer: VkCommandBuffer) -> Bool {
            false
        }
    }
    private var encoder: Encoder?
    public let commandBuffer: CommandBuffer

    public init(buffer: VulkanCommandBuffer, descriptor: RenderPassDescriptor) {   
        self.commandBuffer = buffer
        self.encoder = Encoder(buffer: buffer, descriptor: descriptor)
    }

    public func reset(descriptor: RenderPassDescriptor) {   
        self.encoder = Encoder(buffer: self.commandBuffer as! VulkanCommandBuffer, descriptor: descriptor)
    }

    public func endEncoding() {
        let commandBuffer = self.commandBuffer as! VulkanCommandBuffer
        commandBuffer.endEncoder(self.encoder!)
        self.encoder = nil
    }

    public var isCompleted: Bool { self.encoder == nil }

    public func waitEvent(_ event: Event) {
    }

    public func signalEvent(_ event: Event) {
    }

    public func waitSemaphoreValue(_ semaphore: Semaphore, value: UInt64) {
    }

    public func signalSemaphoreValue(_ semaphore: Semaphore, value: UInt64) {
    }

    public func setResource(set: UInt32, _: ShaderBindingSet) {
    }

    public func setViewport(_: Viewport) {
    }

    public func setRenderPipelineState(_: RenderPipelineState) {
    }

    public func setVertexBuffer(_: Buffer, offset: UInt64, index: UInt32) {
    }

    public func setVertexBuffers(_: [Buffer], offset: [UInt64], index: UInt32) {
    }

    public func setIndexBuffer(_: Buffer, offset: UInt64, type: IndexType) {
    }
 
    public func pushConstant(stages: [ShaderStage], offset: UInt32, data: UnsafeRawPointer) {
    }
 
    public func draw(numVertices: UInt32, numInstances: UInt32, baseVertex: UInt32, baseInstance: UInt32) {
    }

    public func drawIndexed(numIndices: UInt32, numInstance: UInt32, indexOffset: UInt32, vertexOffset: UInt32, baseInstance: UInt32) {
    }
}

#endif //if ENABLE_VULKAN
