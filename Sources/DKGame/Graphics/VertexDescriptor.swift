public enum VertexFormat {
    case invalid
    
    case uchar2
    case uchar3
    case uchar4
    
    case char2
    case char3
    case char4
    
    case uchar2Normalized
    case uchar3Normalized
    case uchar4Normalized
    
    case char2Normalized
    case char3Normalized
    case char4Normalized
    
    case ushort2
    case ushort3
    case ushort4
    
    case short2
    case short3
    case short4
    
    case ushort2Normalized
    case ushort3Normalized
    case ushort4Normalized
    
    case short2Normalized
    case short3Normalized
    case short4Normalized
    
    case half2
    case half3
    case half4
    
    case float
    case float2
    case float3
    case float4
    
    case int
    case int2
    case int3
    case int4
    
    case uint
    case uint2
    case uint3
    case uint4
    
    case int1010102Normalized
    case uint1010102Normalized
}

public enum VertexStepRate {
    case vertex
    case instance
}

public struct VertexBufferLayoutDescriptor {
    var step: VertexStepRate
    var stride: UInt32
    var bufferIndex: UInt32
}

public struct VertexAttributeDescriptor {
    var format: VertexFormat
    var offset: UInt32
    var bufferIndex: UInt32
    var location: UInt32
}

public struct VertexDescriptor {
    var attributes: [VertexAttributeDescriptor]
    var layouts: [VertexBufferLayoutDescriptor]
}
