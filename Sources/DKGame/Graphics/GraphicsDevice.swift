public enum CPUCacheMode {
    case readWrite
    case writeOnly
}

public protocol Event {
    var device: GraphicsDevice { get }
}

public protocol Semaphore {
    var device: GraphicsDevice { get }
}

public protocol GraphicsDevice {
    var name: String { get }

    func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue?
    func makeShaderModule(from: Shader) -> ShaderModule?
    func makeShaderBindingSet(layout: ShaderBindingSetLayout) -> ShaderBindingSet?

    func makeRenderPipelineState(descriptor: RenderPipelineDescriptor, reflection: UnsafeMutablePointer<PipelineReflection>?) -> RenderPipelineState?
    func makeRenderPipelineState(descriptor: RenderPipelineDescriptor) -> RenderPipelineState?

    func makeComputePipelineState(descriptor: ComputePipelineDescriptor, reflection: UnsafeMutablePointer<PipelineReflection>?) -> ComputePipelineState?
    func makeComputePipelineState(descriptor: ComputePipelineDescriptor) -> ComputePipelineState?

    func makeBuffer(length: Int, storageMode: GPUBufferStorageMode, cacheMode: CPUCacheMode) -> Buffer?
    func makeTexture(descriptor: TextureDescriptor) -> Texture?
    func makeSamplerState(descriptor: SamplerDescriptor) -> SamplerState?

    func makeEvent() -> Event?
    func makeSemaphore() -> Semaphore?
}

public extension GraphicsDevice {
    func makeRenderPipelineState(descriptor: RenderPipelineDescriptor) -> RenderPipelineState? {
        return self.makeRenderPipelineState(descriptor: descriptor, reflection: nil)
    }

    func makeComputePipelineState(descriptor: ComputePipelineDescriptor) -> ComputePipelineState? {
        return self.makeComputePipelineState(descriptor: descriptor, reflection: nil)
    }
}

public enum GraphicsAPI {
    case auto, vulkan, metal, d3d12
}

public func makeGraphicsDevice(api: GraphicsAPI = .auto) -> GraphicsDevice?  {
    var enableValidation = false
#if DEBUG
        enableValidation = true
#endif

    if api == .vulkan || api == .auto {
#if ENABLE_VULKAN        
        if let instance = VulkanInstance(enableValidation: enableValidation) {
            return instance.makeDevice()
        }
#endif
    }
    if api == .metal || api == .auto {
#if ENABLE_METAL

#endif        
    }
    return nil
}
