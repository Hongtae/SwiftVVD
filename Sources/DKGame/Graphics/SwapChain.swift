public protocol SwapChain {
    var pixelFormat: PixelFormat { get set }

    func currentRenderPassDescriptor() -> RenderPassDescriptor
    var maximumBufferCount: UInt64 { get }

    func present(waitEvents: [Event]) -> Bool
}

extension SwapChain {
    public func present() -> Bool {
        return present(waitEvents:[])
    }
}
