//
//  File: blend_softLight.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "blend.hlsli"

float softLight(float src, float dst) {
    if (src <= 0.5)
        return dst - (1 - 2 * src) * dst * (1 - dst);
    else {
        float d = (dst <= 0.25) ? ((16 * dst - 12) * dst + 4) * dst : sqrt(dst);
        return dst + (2 * src - 1) * (d - dst);
    }
}

float3 blend(float3 src, float3 dst) {
    return float3(softLight(src.r, dst.r), softLight(src.g, dst.g), softLight(src.b, dst.b));
}

float4 blend_softLight(FragmentInput input) : SV_Target0
{
    float4 outFragColor;
    float4 src = sampleSource(input.textureCoordinate) * input.color;
    float4 dst = sampleDestination(input.textureCoordinate);

    if (src.a != 0.0)   src.rgb /= src.a;
    if (dst.a != 0.0)   dst.rgb /= dst.a;

    float3 rgb = (1.0 - dst.a) * src.rgb + dst.a * blend(src.rgb, dst.rgb);
    outFragColor = lerp(float4(dst.rgb * dst.a, dst.a), float4(rgb, 1.0), src.a);
    return outFragColor;
}
