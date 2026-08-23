//
//  File: filter_linearToSrgb.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "image.hlsli"

struct Constants
{
    row_major float3x3 matrix;
};

[[vk::push_constant]] ConstantBuffer<Constants> constants;

float3 selectComponents(bool3 condition, float3 trueValue, float3 falseValue)
{
    return float3(
        condition.x ? trueValue.x : falseValue.x,
        condition.y ? trueValue.y : falseValue.y,
        condition.z ? trueValue.z : falseValue.z
    );
}

float3 linearToSrgb(float3 color)
{
    float3 linearSegment = color * 12.92;
    float3 powerSegment = 1.055 * pow(color, float3(1.0 / 2.4, 1.0 / 2.4, 1.0 / 2.4)) - 0.055;
    return selectComponents(color <= float3(0.0031308, 0.0031308, 0.0031308), linearSegment, powerSegment);
}

float4 filter_linearToSrgb(FragmentInput input) : SV_Target0
{
    float4 source = sampleImage(input.textureCoordinate) * input.color;
    if (source.a != 0.0)
        source.rgb /= source.a;
    return float4(linearToSrgb(source.rgb) * source.a, source.a);
}
