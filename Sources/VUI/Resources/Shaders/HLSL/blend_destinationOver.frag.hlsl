//
//  File: blend_destinationOver.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "blend.hlsli"

float4 blend(float4 src, float4 dst) {
    return src * (1 - dst.a) + dst;
}

float4 blend_destinationOver(FragmentInput input) : SV_Target0
{
    float4 outFragColor;
    float4 src = sampleSource(input.textureCoordinate) * input.color;
    float4 dst = sampleDestination(input.textureCoordinate);

    if (src.a != 0.0)   src.rgb /= src.a;
    if (dst.a != 0.0)   dst.rgb /= dst.a;

    float4 rgba = blend(src, dst);
    outFragColor = lerp(float4(dst.rgb * dst.a, dst.a), rgba, src.a);
    return outFragColor;
}
