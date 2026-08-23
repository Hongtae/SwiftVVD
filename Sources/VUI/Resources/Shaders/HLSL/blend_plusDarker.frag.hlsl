//
//  File: blend_plusDarker.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "blend.hlsli"

float3 blend(float3 src, float3 dst) {
    return max(float3(0.0, 0.0, 0.0), 1 - ((1 - dst) + (1 - src)));
}

float4 blend_plusDarker(FragmentInput input) : SV_Target0
{
    float4 outFragColor;
    float4 src = sampleSource(input.textureCoordinate) * input.color;
    float4 dst = sampleDestination(input.textureCoordinate);

    float3 rgb = (1.0 - dst.a) * src.rgb + dst.a * blend(src.rgb, dst.rgb);
    outFragColor = lerp(dst, float4(rgb, 1.0), src.a);
    return outFragColor;
}
