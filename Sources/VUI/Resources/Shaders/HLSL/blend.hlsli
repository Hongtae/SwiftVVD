//
//  File: blend.hlsli
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#ifndef BLEND_SHADER_COMMON_HLSLI
#define BLEND_SHADER_COMMON_HLSLI

struct FragmentInput
{
    [[vk::location(0)]] float2 textureCoordinate : TEXCOORD0;
    [[vk::location(1)]] float4 color : COLOR0;
};

[[vk::combinedImageSampler]]
[[vk::binding(0, 0)]]
Texture2D<float4> sourceTexture;

[[vk::combinedImageSampler]]
[[vk::binding(0, 0)]]
SamplerState sourceSampler;

[[vk::combinedImageSampler]]
[[vk::binding(1, 0)]]
Texture2D<float4> destinationTexture;

[[vk::combinedImageSampler]]
[[vk::binding(1, 0)]]
SamplerState destinationSampler;

float4 sampleSource(float2 textureCoordinate)
{
    return sourceTexture.Sample(sourceSampler, textureCoordinate);
}

float4 sampleDestination(float2 textureCoordinate)
{
    return destinationTexture.Sample(destinationSampler, textureCoordinate);
}

#endif
