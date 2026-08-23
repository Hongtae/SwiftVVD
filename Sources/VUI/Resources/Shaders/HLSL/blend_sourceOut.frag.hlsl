//
//  File: blend_sourceOut.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "blend.hlsli"

float4 blend(float4 src, float4 dst) {
    return src * (1 - dst.a);
}

float4 blend_sourceOut(FragmentInput input) : SV_Target0
{
    float4 outFragColor;
    float4 src = sampleSource(input.textureCoordinate);
    float4 dst = sampleDestination(input.textureCoordinate);

    if (any(src != float4(0.0, 0.0, 0.0, 0.0)))
        outFragColor = blend(src * input.color, dst);
    else
        outFragColor = dst;
    return outFragColor;
}
