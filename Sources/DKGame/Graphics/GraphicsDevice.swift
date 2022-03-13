public enum CPUCacheMode {
    case readWrite
    case writeOnly
}

public protocol Event {
    func device() -> GraphicsDevice
}

public protocol Semaphore {
    func device() -> GraphicsDevice
}

public protocol GraphicsDevice {
    var name: String { get }

    func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue?
    func makeShaderModule() -> ShaderModule?
    func makeBindingSet() -> ShaderBindingSet?

    func makeRenderPipelineState() -> RenderPipelineState?
    func makeComputePipelineState() -> ComputePipelineState?

    func makeBuffer() -> Buffer?
    func makeTexture() -> Texture?
    func makeSamplerState() -> SamplerState?

    func makeEvent() -> Event?
    func makeSemaphore() -> Semaphore?
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
