//
//  File: blend_plusLighter.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "blend.hlsli"

float3 blend(float3 src, float3 dst) {
    return min(float3(1.0, 1.0, 1.0), src + dst);
}

float4 blend_plusLighter(FragmentInput input) : SV_Target0
{
    float4 outFragColor;
    float4 src = sampleSource(input.textureCoordinate) * input.color;
    float4 dst = sampleDestination(input.textureCoordinate);

    float3 rgb = (1.0 - dst.a) * src.rgb + dst.a * blend(src.rgb, dst.rgb);
    outFragColor = lerp(dst, float4(rgb, 1.0), src.a);
    return outFragColor;
}
