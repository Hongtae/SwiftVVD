public enum ShaderDataType {
	case unknown
	case none

	case `struct`
	case texture
	case sampler

	case float
	case float2
	case float3
	case float4

	case float2x2
	case float2x3
	case float2x4

	case float3x2
	case float3x3
	case float3x4

	case float4x2
	case float4x3
	case float4x4

	case half
	case half2
	case half3
	case half4

	case half2x2
	case half2x3
	case half2x4

	case half3x2
	case half3x3
	case half3x4

	case half4x2
	case half4x3
	case half4x4

	case int
	case int2
	case int3
	case int4

	case uInt
	case uInt2
	case uInt3
	case uInt4

	case short
	case short2
	case short3
	case short4

	case uShort
	case uShort2
	case uShort3
	case uShort4

	case char
	case char2
	case char3
	case char4

	case uChar
	case uChar2
	case uChar3
	case uChar4

	case bool
	case bool2
	case bool3
	case bool4
}

public enum ShaderStage {
    case unknown
    case vertex
    case tessellationControl
    case tessellationEvaluation
    case geometry
    case fragment
    case compute
}

public struct ShaderResourceBuffer {
    var dataType : ShaderDataType
    var alignment : UInt32
    var size : UInt32
}

public struct ShaderResourceTexture {
    var dataType : ShaderDataType
    var textureType : TextureType
}

public struct ShaderResourceThreadgroup {
    var alignment : UInt32
    var size : UInt32
}

public struct ShaderResourceStructMember {
    var dataType : ShaderDataType
    var name : String
    var offset : UInt32
    var size : UInt32   // declared size
    var count : UInt32  // array length
    var stride : UInt32 // stride between array elements

    var members : [ShaderResourceStructMember]
}

public enum ShaderResourceType {
    case buffer
    case texture
    case sampler
    case textureSampler // texture and sampler (combined)
}

public enum ShaderResourceAccess {
    case readOnly
    case writeOnly
    case readWrite
}

public struct ShaderResource {
    var set : UInt32
    var binding : UInt32
    var name : String
    var type: ShaderResourceType
    var stages : [ShaderStage]

    var count : UInt32  // array length
    var stride : UInt32 // stride between array elements

    var enabled : Bool
    var access : ShaderResourceAccess

    // typeinfo
    var bufferTypeInfo : ShaderResourceBuffer?
    var textureTypeInfo : ShaderResourceTexture?
    var threadgroupTypeInfo : ShaderResourceThreadgroup?

    // struct members (struct only)
    var members : [ShaderResourceStructMember]
}

public struct ShaderPushConstantLayout {
    var name : String
    var offset : UInt32
    var size : UInt32
    var stages : [ShaderStage]
    var members : [ShaderResourceStructMember]
}
