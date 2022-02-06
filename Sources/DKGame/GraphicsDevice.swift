public protocol GraphicsDevice {

    func createCommandQueue()
    func createShaderModule()
    func createBindingSet()

    func createRenderPipeline()
    func createComputePipeline()

    func createBuffer()
    func createTexture()
    func createSamplerState()

    func createEvent()
    func createSemaphore()
}
