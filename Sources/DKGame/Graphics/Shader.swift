import SPIRV_Cross

public struct ShaderAttribute {
    var name : String
    var location : UInt32
    var type : ShaderDataType
    var enabled : Bool
}

public class Shader {
    public enum DescriptorType {
        case uniformBuffer
        case storageBuffer
        case storageTexture
        case uniformTexelBuffer // readonly texture 'buffer'
        case storageTexelBuffer // writable texture 'buffer'
        case textureSampler     // texture, sampler combined
        case texture
        case sampler
    }
    public struct Descriptor {
        var set : UInt32
        var binding : UInt32
        var count : UInt32 // array size
        var type : DescriptorType
    }

    public init() {
        // spirv-cross test
        var context: spvc_context? = nil
        spvc_context_create(&context);
    }
}
