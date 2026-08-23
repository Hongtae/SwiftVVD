//
//  File: blend_copy.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "blend.hlsli"

float4 blend(float4 src, float4 dst) {
    return src;
}

float4 blend_copy(FragmentInput input) : SV_Target0
{
    float4 outFragColor;
    float4 src = sampleSource(input.textureCoordinate);
    float4 dst = sampleDestination(input.textureCoordinate);

    float4 rgba = blend(src, dst);
    outFragColor = lerp(float4(dst.rgb * dst.a, dst.a), rgba, src.a * input.color.a);
    return outFragColor;
}
