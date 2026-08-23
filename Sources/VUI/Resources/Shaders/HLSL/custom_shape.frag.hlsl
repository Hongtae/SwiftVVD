//
//  File: custom_shape.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct FragmentInput
{
    [[vk::location(0)]] float2 textureCoordinate : TEXCOORD0;
    [[vk::location(1)]] float4 color : COLOR0;
};

struct Arguments
{
    float4 tint;
    float4 boundingRect;
};

[[vk::push_constant]] ConstantBuffer<Arguments> arguments;

float4 custom_shape(FragmentInput input) : SV_Target0
{
    float hasArea = arguments.boundingRect.z > 0.0
        && arguments.boundingRect.w > 0.0 ? 1.0 : 0.0;
    return arguments.tint * input.color * hasArea;
}
