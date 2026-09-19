import Foundation
import VVD

/// Restricts a real device's advertised features while retaining GPU execution.
final class GraphicsDeviceFeatureMask: GraphicsDevice, @unchecked Sendable {
    let base: GraphicsDevice
    let features: GraphicsDeviceFeatures
    var name: String { base.name }
    private let lock = NSLock()
    private var outputs: [String: [ShaderDataType]] = [:]

    var loadedShaderOutputs: [String: [ShaderDataType]] {
        lock.lock()
        defer { lock.unlock() }
        return outputs
    }

    init(_ base: GraphicsDevice, features: GraphicsDeviceFeatures) {
        self.base = base
        self.features = base.features.intersection(features)
    }

    func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue? {
        base.makeCommandQueue(flags: flags).map { Queue(base: $0, owner: self) }
    }

    func makeShaderModule(from shader: VVD.Shader) -> ShaderModule? {
        lock.lock()
        outputs[shader.name] = shader.outputAttributes.map(\.type)
        lock.unlock()
        return base.makeShaderModule(from: shader)
    }

    func makeShaderBindingSet(layout: ShaderBindingSetLayout) -> ShaderBindingSet? {
        base.makeShaderBindingSet(layout: layout)
    }
    func makeRenderPipelineState(descriptor: RenderPipelineDescriptor,
                                 reflection: UnsafeMutablePointer<PipelineReflection>?) -> RenderPipelineState? {
        base.makeRenderPipelineState(descriptor: descriptor, reflection: reflection)
    }
    func makeComputePipelineState(descriptor: ComputePipelineDescriptor,
                                  reflection: UnsafeMutablePointer<PipelineReflection>?) -> ComputePipelineState? {
        base.makeComputePipelineState(descriptor: descriptor, reflection: reflection)
    }
    func makeDepthStencilState(descriptor: DepthStencilDescriptor) -> DepthStencilState? {
        base.makeDepthStencilState(descriptor: descriptor)
    }
    func makeBuffer(length: Int, storageMode: StorageMode, cpuCacheMode: CPUCacheMode) -> GPUBuffer? {
        base.makeBuffer(length: length, storageMode: storageMode, cpuCacheMode: cpuCacheMode)
    }
    func makeTexture(descriptor: TextureDescriptor) -> Texture? {
        base.makeTexture(descriptor: descriptor)
    }
    func makeTransientRenderTarget(type: TextureType, pixelFormat: PixelFormat,
                                   width: Int, height: Int, depth: Int, sampleCount: Int) -> Texture? {
        base.makeTransientRenderTarget(type: type, pixelFormat: pixelFormat, width: width,
            height: height, depth: depth, sampleCount: sampleCount)
    }
    func makeSamplerState(descriptor: SamplerDescriptor) -> SamplerState? {
        base.makeSamplerState(descriptor: descriptor)
    }
    func makeEvent() -> GPUEvent? { base.makeEvent() }
    func makeSemaphore() -> GPUSemaphore? { base.makeSemaphore() }

    private final class Queue: CommandQueue {
        let base: CommandQueue
        let owner: GraphicsDeviceFeatureMask
        var device: GraphicsDevice { owner }
        var flags: CommandQueueFlags { base.flags }

        init(base: CommandQueue, owner: GraphicsDeviceFeatureMask) {
            self.base = base
            self.owner = owner
        }
        func makeCommandBuffer() -> CommandBuffer? {
            base.makeCommandBuffer().map { Buffer(base: $0, queue: self) }
        }
        @MainActor
        func makeSwapChain(target: any Window) -> SwapChain? { base.makeSwapChain(target: target) }
    }

    private final class Buffer: CommandBuffer {
        let base: CommandBuffer
        let queue: Queue
        var commandQueue: CommandQueue { queue }
        var device: GraphicsDevice { queue.device }
        var status: CommandBufferStatus { base.status }

        init(base: CommandBuffer, queue: Queue) {
            self.base = base
            self.queue = queue
        }
        func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder? {
            base.makeRenderCommandEncoder(descriptor: descriptor)
        }
        func makeComputeCommandEncoder() -> ComputeCommandEncoder? { base.makeComputeCommandEncoder() }
        func makeCopyCommandEncoder() -> CopyCommandEncoder? { base.makeCopyCommandEncoder() }
        func encodeWaitEvent(_ event: GPUEvent) { base.encodeWaitEvent(event) }
        func encodeSignalEvent(_ event: GPUEvent) { base.encodeSignalEvent(event) }
        func encodeWaitSemaphore(_ semaphore: GPUSemaphore, value: UInt64) {
            base.encodeWaitSemaphore(semaphore, value: value)
        }
        func encodeSignalSemaphore(_ semaphore: GPUSemaphore, value: UInt64) {
            base.encodeSignalSemaphore(semaphore, value: value)
        }
        func addCompletedHandler(_ handler: @escaping CommandBufferHandler) {
            base.addCompletedHandler { [self] _ in handler(self) }
        }
        @discardableResult func commit() -> Bool { base.commit() }
    }
}
