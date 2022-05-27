public protocol SwapChain {
    var pixelFormat: PixelFormat { get set }
    var maximumBufferCount: UInt { get }

    func currentRenderPassDescriptor() -> RenderPassDescriptor
    func present(waitEvents: [Event]) -> Bool

    var commandQueue: CommandQueue { get }
}

extension SwapChain {
    @discardableResult
    public func present() -> Bool {
        return present(waitEvents:[])
    }
}
