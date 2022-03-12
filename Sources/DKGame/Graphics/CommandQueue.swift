
public struct CommandQueueTypeMask: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let graphics = CommandQueueTypeMask(rawValue: 0x1) // Graphics and Copy(Blit) commands
    public static let compute = CommandQueueTypeMask(rawValue: 0x2)  // Compute and Copy(Blit) commands

    public static let copy: CommandQueueTypeMask = [] // copy(transfer) queue, always enabled.
}

public protocol CommandQueue {
    func makeCommandBuffer() -> CommandBuffer?
    func makeSwapChain() -> SwapChain?

    var queueTypeMask : CommandQueueTypeMask { get }
    var device: GraphicsDevice { get }
}
