public protocol GraphicsDevice {

    func makeCommandQueue() -> CommandQueue?
    // func makeShaderModule() -> ShaderModule?
    // func makeBindingSet() -> ShaderBindingSet?

    // func makeRenderPipeline() -> RenderPipelineState?
    // func makeComputePipeline() -> ComputePipelineState?

    // func makeBuffer() -> GpuBuffer?
    // func makeTexture() -> Texture?
    // func makeSamplerState() -> SamplerState?

    // func makeEvent() -> GpuEvent?
    // func makeSemaphore() -> GpuSemaphore?
}

public enum GraphicsAPI {
    case auto, vulkan, metal, d3d12
}

public func makeGraphicsDevice(api: GraphicsAPI = .auto) -> GraphicsDevice?  {
    return VulkanGraphicsDevice()
}
