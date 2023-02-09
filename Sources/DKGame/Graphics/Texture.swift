//
//  File: Texture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public enum TextureType {
    case unknown
    case type1D
    case type2D
    case type3D
    case typeCube
}

public struct TextureUsage: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let unknown: TextureUsage = []
    public static let copySource        = TextureUsage(rawValue: 1)
    public static let copyDestination   = TextureUsage(rawValue: 1<<1)
    public static let sampled           = TextureUsage(rawValue: 1<<2)
    public static let storage           = TextureUsage(rawValue: 1<<3)
    public static let shaderRead        = TextureUsage(rawValue: 1<<4)
    public static let shaderWrite       = TextureUsage(rawValue: 1<<5)
    public static let renderTarget      = TextureUsage(rawValue: 1<<6)
    public static let pixelFormatView   = TextureUsage(rawValue: 1<<7)
}

public protocol Texture: AnyObject {
    var width: Int { get }
    var height: Int { get }
    var depth: Int { get }
    var mipmapCount: Int { get }
    var arrayLength: Int { get }

    var type: TextureType { get }
    var pixelFormat: PixelFormat { get }

    var device: GraphicsDevice { get }
}

public struct TextureDescriptor {
    public var textureType: TextureType
    public var pixelFormat: PixelFormat

    public var width: Int
    public var height: Int
    public var depth: Int
    public var mipmapLevels: Int
    public var sampleCount: Int
    public var arrayLength: Int
    public var usage: TextureUsage

    public init(textureType: TextureType,
                pixelFormat: PixelFormat,
                width: Int,
                height: Int,
                depth: Int = 1,
                mipmapLevels: Int = 1,
                sampleCount: Int = 1,
                arrayLength: Int = 1,
                usage: TextureUsage) {
        self.textureType = textureType
        self.pixelFormat = pixelFormat
        self.width = width
        self.height = height
        self.depth = depth
        self.mipmapLevels = mipmapLevels
        self.sampleCount = sampleCount
        self.arrayLength = arrayLength
        self.usage = usage
    }
}
