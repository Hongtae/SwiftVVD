//
//  File: VertexDescriptor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public enum VertexFormat {
    case invalid
    
    case uchar
    case uchar2
    case uchar3
    case uchar4
    
    case char
    case char2
    case char3
    case char4
    
    case ucharNormalized
    case uchar2Normalized
    case uchar3Normalized
    case uchar4Normalized
    
    case charNormalized
    case char2Normalized
    case char3Normalized
    case char4Normalized
    
    case ushort
    case ushort2
    case ushort3
    case ushort4
    
    case short
    case short2
    case short3
    case short4
    
    case ushortNormalized
    case ushort2Normalized
    case ushort3Normalized
    case ushort4Normalized
    
    case shortNormalized
    case short2Normalized
    case short3Normalized
    case short4Normalized
    
    case half
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
    public var step: VertexStepRate
    public var stride: Int
    public var bufferIndex: Int

    public init(step: VertexStepRate,
                stride: Int,
                bufferIndex: Int) {
        self.step = step
        self.stride = stride
        self.bufferIndex = bufferIndex
    }
}

public struct VertexAttributeDescriptor {
    public var format: VertexFormat
    public var offset: Int
    public var bufferIndex: Int
    public var location: Int

    public init(format: VertexFormat,
                offset: Int,
                bufferIndex: Int,
                location: Int) {
        self.format = format
        self.offset = offset
        self.bufferIndex = bufferIndex
        self.location = location
    }
}

public struct VertexDescriptor {
    public var attributes: [VertexAttributeDescriptor]
    public var layouts: [VertexBufferLayoutDescriptor]

    public init(attributes: [VertexAttributeDescriptor] = [],
                layouts: [VertexBufferLayoutDescriptor] = []) {
        self.attributes = attributes
        self.layouts = layouts
    }
}
