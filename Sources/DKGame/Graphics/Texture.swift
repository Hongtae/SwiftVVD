public enum TextureType {
    case unknown
    case type1D
    case type2D
    case type3D
    case typeCube
}

public enum TextureUsage {
    case unknown           
    case copySource        
    case copyDestination   
    case sampled           
    case storage           
    case shaderRead        
    case shaderWrite       
    case renderTarget      
    case pixelFormatView   
}

public protocol Texture {
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
    var usage: [TextureUsage]
}
