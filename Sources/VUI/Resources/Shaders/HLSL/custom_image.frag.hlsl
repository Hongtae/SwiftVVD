//
//  File: custom_image.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct FragmentInput
{
    [[vk::location(0)]] float2 textureCoordinate : TEXCOORD0;
    [[vk::location(1)]] float4 color : COLOR0;
};

[[vk::binding(0, 0)]] Texture2D<float4> imageTexture;
[[vk::binding(16, 0)]] SamplerState imageSampler;

float4 custom_image(FragmentInput input) : SV_Target0
{
    return imageTexture.Sample(imageSampler, input.textureCoordinate)
        * input.color;
}
