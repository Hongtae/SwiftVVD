
public struct TextureSize {
    var width: UInt32
    var height: UInt32
    var depth: UInt32
}

public struct TextureOrigin {
    var layer: UInt32
    var level: UInt32
    var x: UInt32, y: UInt32, z: UInt32 // pixel offset
}

public struct BufferImageOrigin {
    var offset: UInt64      // buffer offset (bytes)
    var imageWidth: UInt32  // buffer image's width (pixels)
    var imageHeight: UInt32 // buffer image's height (pixels)
}

public protocol CopyCommandEncoder: CommandEncoder {
    func copy(from: Buffer, sourceOffset: UInt64, to: Buffer, destinationOffset: UInt64, size: UInt64)
    func copy(from: Buffer, sourceOffset: BufferImageOrigin, to: Texture, destinationOffset: TextureOrigin, size: TextureSize)
    func copy(from: Texture, sourceOffset: TextureOrigin, to: Buffer, destinationOffset: BufferImageOrigin, size: TextureSize)
    func copy(from: Texture, sourceOffset: TextureOrigin, to: Texture, destinationOffset: TextureOrigin, size: TextureSize)

    func fill(buffer: Buffer, offset: UInt64, length: UInt64, value: UInt8)
}
