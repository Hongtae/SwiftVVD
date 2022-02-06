public enum CpuCacheMode {
    case readWrite
    case writeOnly
}

public protocol GpuEvent {
    func device() -> GraphicsDevice
}

public protocol GpuSemaphore {
    func device() -> GraphicsDevice
}
