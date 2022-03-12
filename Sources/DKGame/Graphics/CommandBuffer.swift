public enum CommandBufferStatus {
    case notEnqueued
    case enqueued
    case committed
    case scheduled
    case completed
    case error
}

public typealias CommandBufferHandler = (CommandBuffer) -> Void

public protocol CommandBuffer {
    func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder?
    func makeComputeCommandEncoder() -> ComputeCommandEncoder?
    func makeCopyCommandEncoder() -> CopyCommandEncoder?

    func addCompletedHandler(_ handler: CommandBufferHandler)

    var commandQueue: CommandQueue { get }
    var device: GraphicsDevice { get }
}
