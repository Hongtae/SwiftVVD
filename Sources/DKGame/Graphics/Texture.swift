public enum TextureType {
    case unknown
    case type1D
    case type2D
    case type3D
    case typeCube
}

public struct TextureUsage: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

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
    var width: UInt32 { get }
    var height: UInt32 { get }
    var depth: UInt32 { get }
    var mipmapCount: UInt32 { get }
    var arrayLength: UInt32 { get }

    var type: TextureType { get }
    var pixelFormat: PixelFormat { get }

    var device: GraphicsDevice { get }
}

public struct TextureDescriptor {
    var textureType: TextureType
    var pixelFormat: PixelFormat
    
    var width: UInt32
    var height: UInt32
    var depth: UInt32
    var mipmapLevels: UInt32
    var sampleCount: UInt32
    var arrayLength: UInt32
    var usage: TextureUsage
}
