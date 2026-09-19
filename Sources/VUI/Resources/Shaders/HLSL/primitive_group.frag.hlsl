//
//  File: primitive_group.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "image.hlsli"

#ifndef PRIMITIVE_OUTPUT_TYPE
#define PRIMITIVE_OUTPUT_TYPE float4
#endif

PRIMITIVE_OUTPUT_TYPE primitive_group(FragmentInput input, float4 position : SV_Position) : SV_Target0
{
    // Read the group at this framebuffer pixel without filtering its neighbors.
    float4 layer = f16tof32(f32tof16(imageTexture.Load(int3(int2(position.xy), 0))));
    return PRIMITIVE_OUTPUT_TYPE(f16tof32(f32tof16(layer * input.color.a)));
}
