//
//  File: blend_colorBurn.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "blend.hlsli"

float colorBurn(float src, float dst) {
    if (src == 0.0)
        return 0.0;
    else
        return 1.0 - min(1.0, (1.0 - dst) / src);
}

float3 blend(float3 src, float3 dst) {
    return float3(colorBurn(src.r, dst.r), colorBurn(src.g, dst.g), colorBurn(src.b, dst.b));
}

float4 blend_colorBurn(FragmentInput input) : SV_Target0
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
