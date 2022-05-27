
public struct TextureSize {
    public var width: UInt32
    public var height: UInt32
    public var depth: UInt32

    public init(width: UInt32,
                height: UInt32,
                depth: UInt32) {
        self.width = width
        self.height = height
        self.depth = depth
    }
}

public struct TextureOrigin {
    public var layer: UInt32
    public var level: UInt32
    public var x: UInt32, y: UInt32, z: UInt32 // pixel offset

    public init(layer: UInt32,
                level: UInt32,
                x: UInt32, y: UInt32, z: UInt32) {
        self.layer = layer
        self.level = level
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct BufferImageOrigin {
    public var offset: UInt        // buffer offset (bytes)
    public var imageWidth: UInt32  // buffer image's width (pixels)
    public var imageHeight: UInt32 // buffer image's height (pixels)

    public init(offset: UInt,
                imageWidth: UInt32,
                imageHeight: UInt32) {
        self.offset = offset
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }
}

public protocol CopyCommandEncoder: CommandEncoder {
    func copy(from: Buffer, sourceOffset: UInt64, to: Buffer, destinationOffset: UInt64, size: UInt64)
    func copy(from: Buffer, sourceOffset: BufferImageOrigin, to: Texture, destinationOffset: TextureOrigin, size: TextureSize)
    func copy(from: Texture, sourceOffset: TextureOrigin, to: Buffer, destinationOffset: BufferImageOrigin, size: TextureSize)
    func copy(from: Texture, sourceOffset: TextureOrigin, to: Texture, destinationOffset: TextureOrigin, size: TextureSize)

    func fill(buffer: Buffer, offset: UInt64, length: UInt64, value: UInt8)
}
