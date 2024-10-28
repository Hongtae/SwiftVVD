//
//  File: MetalShaderDataType.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

extension ShaderDataType {
    static func from(mtlDataType dataType: MTLDataType) -> ShaderDataType {
        switch dataType {
        case .`struct`:     return .`struct`
        case .texture:      return .texture
        case .sampler:      return .sampler

        case .bool:         return .bool
        case .bool2:        return .bool2
        case .bool3:        return .bool3
        case .bool4:        return .bool4

        case .char:         return .char
        case .char2:        return .char2
        case .char3:        return .char3
        case .char4:        return .char4

        case .uchar:        return .uchar
        case .uchar2:       return .uchar2
        case .uchar3:       return .uchar3
        case .uchar4:       return .uchar4

        case .short:        return .short
        case .short2:       return .short2
        case .short3:       return .short3
        case .short4:       return .short4

        case .ushort:       return .ushort
        case .ushort2:      return .ushort2
        case .ushort3:      return .ushort3
        case .ushort4:      return .ushort4

        case .int:          return .int
        case .int2:         return .int2
        case .int3:         return .int3
        case .int4:         return .int4

        case .uint:         return .uint
        case .uint2:        return .uint2
        case .uint3:        return .uint3
        case .uint4:        return .uint4

        case .half:         return .half
        case .half2:        return .half2
        case .half3:        return .half3
        case .half4:        return .half4
        case .half2x2:      return .half2x2
        case .half3x2:      return .half3x2
        case .half4x2:      return .half4x2
        case .half2x3:      return .half2x3
        case .half3x3:      return .half3x3
        case .half4x3:      return .half4x3
        case .half2x4:      return .half2x4
        case .half3x4:      return .half3x4
        case .half4x4:      return .half4x4

        case .float:        return .float
        case .float2:       return .float2
        case .float3:       return .float3
        case .float4:       return .float4
        case .float2x2:     return .float2x2
        case .float3x2:     return .float3x2
        case .float4x2:     return .float4x2
        case .float2x3:     return .float2x3
        case .float3x3:     return .float3x3
        case .float4x3:     return .float4x3
        case .float2x4:     return .float2x4
        case .float3x4:     return .float3x4
        case .float4x4:     return .float4x4
        default:
            return .none
        }
    }

    func mtlDataType() -> MTLDataType {
        switch self {
        case .`struct`:     return .`struct`
        case .texture:      return .texture
        case .sampler:      return .sampler

        case .bool:         return .bool
        case .bool2:        return .bool2
        case .bool3:        return .bool3
        case .bool4:        return .bool4

        case .char:         return .char
        case .char2:        return .char2
        case .char3:        return .char3
        case .char4:        return .char4

        case .uchar:        return .uchar
        case .uchar2:       return .uchar2
        case .uchar3:       return .uchar3
        case .uchar4:       return .uchar4

        case .short:        return .short
        case .short2:       return .short2
        case .short3:       return .short3
        case .short4:       return .short4

        case .ushort:       return .ushort
        case .ushort2:      return .ushort2
        case .ushort3:      return .ushort3
        case .ushort4:      return .ushort4

        case .int:          return .int
        case .int2:         return .int2
        case .int3:         return .int3
        case .int4:         return .int4

        case .uint:         return .uint
        case .uint2:        return .uint2
        case .uint3:        return .uint3
        case .uint4:        return .uint4

        case .half:         return .half
        case .half2:        return .half2
        case .half3:        return .half3
        case .half4:        return .half4
        case .half2x2:      return .half2x2
        case .half3x2:      return .half3x2
        case .half4x2:      return .half4x2
        case .half2x3:      return .half2x3
        case .half3x3:      return .half3x3
        case .half4x3:      return .half4x3
        case .half2x4:      return .half2x4
        case .half3x4:      return .half3x4
        case .half4x4:      return .half4x4

        case .float:        return .float
        case .float2:       return .float2
        case .float3:       return .float3
        case .float4:       return .float4
        case .float2x2:     return .float2x2
        case .float3x2:     return .float3x2
        case .float4x2:     return .float4x2
        case .float2x3:     return .float2x3
        case .float3x3:     return .float3x3
        case .float4x3:     return .float4x3
        case .float2x4:     return .float2x4
        case .float3x4:     return .float3x4
        case .float4x4:     return .float4x4

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
            return .none
        }
    }

    func mtlAlignment() -> Int {
        if let components = self.components() {
            func stride<T>(of type: T.Type) -> Int {
                MemoryLayout<T>.stride
            }
            let size = stride(of: components.type) * components.columns
            return size * (components.rows == 3 ?  4 : components.rows)
        }
        return 0
    }
}
#endif //if ENABLE_METAL
