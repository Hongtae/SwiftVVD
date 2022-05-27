
public struct CommandQueueFlags: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let render = CommandQueueFlags(rawValue: 0x1)   // render, copy commands
    public static let compute = CommandQueueFlags(rawValue: 0x2)  // compute, copy commands

    public static let copy: CommandQueueFlags = [] // copy(transfer) queue, always enabled.
}

public protocol CommandQueue {
    func makeCommandBuffer() -> CommandBuffer?
    func makeSwapChain(target: Window) -> SwapChain?

    var flags: CommandQueueFlags { get }
    var device: GraphicsDevice { get }
}
