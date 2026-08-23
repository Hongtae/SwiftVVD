//
//  File: vertex_color.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct FragmentInput
{
    [[vk::location(0)]] float2 textureCoordinate : TEXCOORD0;
    [[vk::location(1)]] float4 color : COLOR0;
};

float4 vertex_color(FragmentInput input) : SV_Target0
{
    return input.color;
}
