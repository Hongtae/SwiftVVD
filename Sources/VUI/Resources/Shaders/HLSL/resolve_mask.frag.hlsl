//
//  File: resolve_mask.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "image.hlsli"

float4 resolve_mask(FragmentInput input) : SV_Target0
{
    float4 color = sampleImage(input.textureCoordinate) * input.color;
    // The render target is expected to use an R8-unorm format.
    return color.aaaa;
}
