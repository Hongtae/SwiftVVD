//
//  File: blend_sourceAtop.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "blend.hlsli"

float4 blend(float4 src, float4 dst) {
    return src * dst.a + dst * (1.0 - src.a);
}

float4 blend_sourceAtop(FragmentInput input) : SV_Target0
{
    float4 outFragColor;
    float4 src = sampleSource(input.textureCoordinate) * input.color;
    float4 dst = sampleDestination(input.textureCoordinate);

    float4 rgba = blend(src, dst);
    outFragColor = lerp(dst, rgba, src.a);
    return outFragColor;
}
