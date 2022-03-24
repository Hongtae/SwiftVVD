public enum GPUBufferStorageMode {
    case shared     // accessible to both the CPU and the GPU
    case `private`  // only accessible to the GPU
}

public protocol Buffer {
    func contents() -> UnsafeMutableRawPointer?
    func flush()
    var length: UInt { get }
    var device: GraphicsDevice { get }
}
