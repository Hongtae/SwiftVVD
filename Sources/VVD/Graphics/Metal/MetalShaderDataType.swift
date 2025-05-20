//
//  File: MetalShaderDataType.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

extension ShaderDataType {
    static func from(mtlDataType dataType: MTLDataType) -> ShaderDataType {
        switch dataType {
        case .`struct`:     .`struct`
        case .texture:      .texture
        case .sampler:      .sampler
            
        case .bool:         .bool
        case .bool2:        .bool2
        case .bool3:        .bool3
        case .bool4:        .bool4
            
        case .char:         .char
        case .char2:        .char2
        case .char3:        .char3
        case .char4:        .char4
            
        case .uchar:        .uchar
        case .uchar2:       .uchar2
        case .uchar3:       .uchar3
        case .uchar4:       .uchar4
            
        case .short:        .short
        case .short2:       .short2
        case .short3:       .short3
        case .short4:       .short4
            
        case .ushort:       .ushort
        case .ushort2:      .ushort2
        case .ushort3:      .ushort3
        case .ushort4:      .ushort4
            
        case .int:          .int
        case .int2:         .int2
        case .int3:         .int3
        case .int4:         .int4
            
        case .uint:         .uint
        case .uint2:        .uint2
        case .uint3:        .uint3
        case .uint4:        .uint4
            
        case .half:         .half
        case .half2:        .half2
        case .half3:        .half3
        case .half4:        .half4
        case .half2x2:      .half2x2
        case .half3x2:      .half3x2
        case .half4x2:      .half4x2
        case .half2x3:      .half2x3
        case .half3x3:      .half3x3
        case .half4x3:      .half4x3
        case .half2x4:      .half2x4
        case .half3x4:      .half3x4
        case .half4x4:      .half4x4
            
        case .float:        .float
        case .float2:       .float2
        case .float3:       .float3
        case .float4:       .float4
        case .float2x2:     .float2x2
        case .float3x2:     .float3x2
        case .float4x2:     .float4x2
        case .float2x3:     .float2x3
        case .float3x3:     .float3x3
        case .float4x3:     .float4x3
        case .float2x4:     .float2x4
        case .float3x4:     .float3x4
        case .float4x4:     .float4x4
        default:
                .none
        }
    }

    func mtlDataType() -> MTLDataType {
        switch self {
        case .`struct`:     .`struct`
        case .texture:      .texture
        case .sampler:      .sampler

        case .bool:         .bool
        case .bool2:        .bool2
        case .bool3:        .bool3
        case .bool4:        .bool4

        case .char:         .char
        case .char2:        .char2
        case .char3:        .char3
        case .char4:        .char4

        case .uchar:        .uchar
        case .uchar2:       .uchar2
        case .uchar3:       .uchar3
        case .uchar4:       .uchar4

        case .short:        .short
        case .short2:       .short2
        case .short3:       .short3
        case .short4:       .short4

        case .ushort:       .ushort
        case .ushort2:      .ushort2
        case .ushort3:      .ushort3
        case .ushort4:      .ushort4

        case .int:          .int
        case .int2:         .int2
        case .int3:         .int3
        case .int4:         .int4

        case .uint:         .uint
        case .uint2:        .uint2
        case .uint3:        .uint3
        case .uint4:        .uint4

        case .half:         .half
        case .half2:        .half2
        case .half3:        .half3
        case .half4:        .half4
        case .half2x2:      .half2x2
        case .half3x2:      .half3x2
        case .half4x2:      .half4x2
        case .half2x3:      .half2x3
        case .half3x3:      .half3x3
        case .half4x3:      .half4x3
        case .half2x4:      .half2x4
        case .half3x4:      .half3x4
        case .half4x4:      .half4x4

        case .float:        .float
        case .float2:       .float2
        case .float3:       .float3
        case .float4:       .float4
        case .float2x2:     .float2x2
        case .float3x2:     .float3x2
        case .float4x2:     .float4x2
        case .float2x3:     .float2x3
        case .float3x3:     .float3x3
        case .float4x3:     .float4x3
        case .float2x4:     .float2x4
        case .float3x4:     .float3x4
        case .float4x4:     .float4x4

        case .double:       fallthrough
        case .double2:      fallthrough
        case .double3:      fallthrough
        case .double4:      fallthrough
        case .double2x2:    fallthrough
        case .double3x2:    fallthrough
        case .double4x2:    fallthrough
        case .double2x3:    fallthrough
        case .double3x3:    fallthrough
        case .double4x3:    fallthrough
        case .double2x4:    fallthrough
        case .double3x4:    fallthrough
        case .double4x4:
            assertionFailure("Unsupported data type: double")
            fallthrough
        default:
                .none
        }
    }

    func mtlAlignment() -> Int {
        if let components = self.components() {
            func stride<T>(of type: T.Type) -> Int {
                MemoryLayout<T>.stride
            }
            let row = components.rows == 3 ? 4 : components.rows
            let alignment = stride(of: components.type) * row
            assert(alignment.isPowerOfTwo)
            return alignment
        }
        return 0
    }
}
#endif //if ENABLE_METAL
