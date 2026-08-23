//
//  File: blend_xor.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "blend.hlsli"

float4 blend(float4 src, float4 dst) {
    return src * (1 - dst.a) + dst * (1 - src.a);
}

float4 blend_xor(FragmentInput input) : SV_Target0
{
    float4 outFragColor;
    float4 src = sampleSource(input.textureCoordinate);
    float4 dst = sampleDestination(input.textureCoordinate);

    outFragColor = blend(src * input.color, dst);
    return outFragColor;
}
