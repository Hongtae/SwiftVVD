//
//  File: image.hlsli
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#ifndef IMAGE_SHADER_COMMON_HLSLI
#define IMAGE_SHADER_COMMON_HLSLI

struct FragmentInput
{
    [[vk::location(0)]] float2 textureCoordinate : TEXCOORD0;
    [[vk::location(1)]] float4 color : COLOR0;
};

// The fixed pipeline exposes a single combined texture-sampler descriptor.
[[vk::combinedImageSampler]]
[[vk::binding(0, 0)]]
Texture2D<float4> imageTexture;

[[vk::combinedImageSampler]]
[[vk::binding(0, 0)]]
SamplerState imageSampler;

float4 sampleImage(float2 textureCoordinate)
{
    return imageTexture.Sample(imageSampler, textureCoordinate);
}

#endif
