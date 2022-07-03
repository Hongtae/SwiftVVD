//
//  File: CopyCommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct TextureSize {
    public var width: Int
    public var height: Int
    public var depth: Int

    public init(width: Int, height: Int, depth: Int) {
        self.width = width
        self.height = height
        self.depth = depth
    }
}

public struct TextureOrigin {
    public var layer: Int
    public var level: Int
    // pixel offset
    public var x: Int
    public var y: Int
    public var z: Int

    public init(layer: Int, level: Int, x: Int, y: Int, z: Int) {
        self.layer = layer
        self.level = level
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct BufferImageOrigin {
    public var offset: Int      // buffer offset (bytes)
    public var imageWidth: Int  // buffer image's width (pixels)
    public var imageHeight: Int // buffer image's height (pixels)

    public init(offset: Int, imageWidth: Int, imageHeight: Int) {
        self.offset = offset
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }
}

public protocol CopyCommandEncoder: CommandEncoder {
    func copy(from: Buffer, sourceOffset: Int, to: Buffer, destinationOffset: Int, size: Int)
    func copy(from: Buffer, sourceOffset: BufferImageOrigin, to: Texture, destinationOffset: TextureOrigin, size: TextureSize)
    func copy(from: Texture, sourceOffset: TextureOrigin, to: Buffer, destinationOffset: BufferImageOrigin, size: TextureSize)
    func copy(from: Texture, sourceOffset: TextureOrigin, to: Texture, destinationOffset: TextureOrigin, size: TextureSize)

    func fill(buffer: Buffer, offset: Int, length: Int, value: UInt8)
}
