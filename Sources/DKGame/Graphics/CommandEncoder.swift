public protocol CommandEncoder {
    func endEncoding()
    var isCompleted: Bool { get }

    func waitEvent(_ event: GpuEvent)
    func signalEvent(_ event: GpuEvent)

    func waitSemaphoreValue(_ semaphore: GpuSemaphore, value: UInt64)
    func signalSemaphoreValue(_ semaphore: GpuSemaphore, value: UInt64)

    func commandBuffer() -> CommandBuffer
}
