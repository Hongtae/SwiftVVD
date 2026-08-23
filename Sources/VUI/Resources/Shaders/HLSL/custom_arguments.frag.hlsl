//
//  File: custom_arguments.frag.hlsl
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
    float weights[3];
    float4 colors[2];
    uint4 rawValue;
    float4 boundingRect;
};

[[vk::push_constant]] ConstantBuffer<Arguments> arguments;

float4 custom_arguments(FragmentInput input) : SV_Target0
{
    bool valid = arguments.rawValue.x == 1
        && arguments.boundingRect.z > 0.0
        && arguments.boundingRect.w > 0.0;
    float alpha = valid ? 1.0 : 0.0;
    return float4(
        arguments.weights[0],
        arguments.colors[0].y,
        arguments.colors[1].z,
        alpha
    ) * input.color;
}
