//
//  File: filter_blur.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "image.hlsli"

struct Constants
{
    float resolution[2];
    float direction[2];
};

[[vk::push_constant]] ConstantBuffer<Constants> constants;

// Fast Gaussian blur coefficients from https://github.com/Jam3/glsl-fast-gaussian-blur.
float4 blur5(float2 uv, float2 resolution, float2 direction)
{
    float4 color = float4(0.0, 0.0, 0.0, 0.0);
    float2 offset1 = float2(1.3333333333333333, 1.3333333333333333) * direction;
    color += sampleImage(uv) * 0.29411764705882354;
    color += sampleImage(uv + (offset1 / resolution)) * 0.35294117647058826;
    color += sampleImage(uv - (offset1 / resolution)) * 0.35294117647058826;
    return color;
}

float4 blur9(float2 uv, float2 resolution, float2 direction)
{
    float4 color = float4(0.0, 0.0, 0.0, 0.0);
    float2 offset1 = float2(1.3846153846, 1.3846153846) * direction;
    float2 offset2 = float2(3.2307692308, 3.2307692308) * direction;
    color += sampleImage(uv) * 0.2270270270;
    color += sampleImage(uv + (offset1 / resolution)) * 0.3162162162;
    color += sampleImage(uv - (offset1 / resolution)) * 0.3162162162;
    color += sampleImage(uv + (offset2 / resolution)) * 0.0702702703;
    color += sampleImage(uv - (offset2 / resolution)) * 0.0702702703;
    return color;
}

float4 blur13(float2 uv, float2 resolution, float2 direction)
{
    float4 color = float4(0.0, 0.0, 0.0, 0.0);
    float2 offset1 = float2(1.411764705882353, 1.411764705882353) * direction;
    float2 offset2 = float2(3.2941176470588234, 3.2941176470588234) * direction;
    float2 offset3 = float2(5.176470588235294, 5.176470588235294) * direction;
    color += sampleImage(uv) * 0.1964825501511404;
    color += sampleImage(uv + (offset1 / resolution)) * 0.2969069646728344;
    color += sampleImage(uv - (offset1 / resolution)) * 0.2969069646728344;
    color += sampleImage(uv + (offset2 / resolution)) * 0.09447039785044732;
    color += sampleImage(uv - (offset2 / resolution)) * 0.09447039785044732;
    color += sampleImage(uv + (offset3 / resolution)) * 0.010381362401148057;
    color += sampleImage(uv - (offset3 / resolution)) * 0.010381362401148057;
    return color;
}

float4 filter_blur(FragmentInput input) : SV_Target0
{
    float2 resolution = float2(constants.resolution[0], constants.resolution[1]);
    float2 direction = float2(constants.direction[0], constants.direction[1]);
    return blur5(input.textureCoordinate, resolution, direction) * input.color;
}
