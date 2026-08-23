//
//  File: custom_passthrough.frag.hlsl
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
[[vk::binding(0, 0)]] Texture2D<float4> sourceTexture;
[[vk::binding(16, 0)]] SamplerState sourceSampler;

float4 custom_passthrough(FragmentInput input) : SV_Target0
{
    return sourceTexture.Sample(sourceSampler, input.textureCoordinate)
        * arguments.tint
        * input.color;
}
