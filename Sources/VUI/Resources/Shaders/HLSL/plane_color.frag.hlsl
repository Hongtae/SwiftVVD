//
//  File: plane_color.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#ifndef PRIMITIVE_OUTPUT_TYPE
#define PRIMITIVE_OUTPUT_TYPE float4
#endif

struct FragmentInput
{
    [[vk::location(1)]] float4 color : COLOR0;
};

PRIMITIVE_OUTPUT_TYPE plane_color(FragmentInput input) : SV_Target0
{
    return PRIMITIVE_OUTPUT_TYPE(input.color);
}
