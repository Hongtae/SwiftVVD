public enum CommandQueueType {
    case graphics
    case compute
}

public protocol CommandQueue {
    func makeCommandBuffer() -> CommandBuffer
    func makeSwapChain() -> SwapChain

    var type : [CommandQueueType] { get }

    func device() -> GraphicsDevice    
}
