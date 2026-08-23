//
//  File: blend_hardLight.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "blend.hlsli"

float screen(float src, float dst) {
    return 1 - ((1 - src) * (1 - dst));
}

float hardLight(float src, float dst) {
    return src <= 0.5 ? (2.0 * src * dst) : screen(2.0 * src - 1.0, dst);
}

float3 blend(float3 src, float3 dst) {
    return float3(hardLight(src.r, dst.r), hardLight(src.g, dst.g), hardLight(src.b, dst.b));
}

float4 blend_hardLight(FragmentInput input) : SV_Target0
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
