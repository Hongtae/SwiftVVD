public enum GpuBufferStorageMode {
    case shared     // accessible to both the CPU and the GPU
    case `private`  // only accessible to the GPU
}

public protocol GpuBuffer {
    func contents() -> UnsafeMutableRawPointer
    func flush()
    var length: Int { get }
}
