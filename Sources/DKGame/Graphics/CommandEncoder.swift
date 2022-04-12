public protocol CommandEncoder {
    func endEncoding()
    var isCompleted: Bool { get }

    func waitEvent(_ event: Event)
    func signalEvent(_ event: Event)

    func waitSemaphoreValue(_ semaphore: Semaphore, value: UInt64)
    func signalSemaphoreValue(_ semaphore: Semaphore, value: UInt64)

    var commandBuffer: CommandBuffer { get }
}
