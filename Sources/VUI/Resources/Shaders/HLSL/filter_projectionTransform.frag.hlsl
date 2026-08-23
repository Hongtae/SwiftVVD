//
//  File: filter_projectionTransform.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "image.hlsli"

struct Constants
{
    // row_major preserves the CPU-side field order in the Vulkan push constant.
    row_major float3x3 matrix;
};

[[vk::push_constant]] ConstantBuffer<Constants> constants;

float4 filter_projectionTransform(FragmentInput input) : SV_Target0
{
    // This ordering emits the same row-vector transform as the fixed pipeline contract.
    float3 projected = mul(constants.matrix, float3(input.textureCoordinate, 1.0));
    return sampleImage(projected.xy / projected.z) * input.color;
}
