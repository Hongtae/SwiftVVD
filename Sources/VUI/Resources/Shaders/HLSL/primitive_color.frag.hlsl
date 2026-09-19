//
//  File: primitive_color.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#ifndef PRIMITIVE_OUTPUT_TYPE
#define PRIMITIVE_OUTPUT_TYPE float4
#endif

struct FragmentInput
{
    [[vk::location(0)]] float2 position : TEXCOORD0;
    [[vk::location(1)]] float4 color : COLOR0;
};

struct Constants
{
    float2 edges;
    float cornerRadius;
    float distanceScale;
    uint kind;
    uint mode;
};
[[vk::push_constant]] ConstantBuffer<Constants> constants;

// Keep each coverage rounding point without requiring a 16-bit shader feature.
float roundHalf(float x) { return f16tof32(f32tof16(x)); }
float cubic(float t) { return roundHalf(roundHalf(t * t) * roundHalf(mad(t, -2.0, 3.0))); }

PRIMITIVE_OUTPUT_TYPE primitive_color(FragmentInput input) : SV_Target0
{
    if (constants.kind == 1) return PRIMITIVE_OUTPUT_TYPE(input.color);
    float2 q = abs(input.position) - constants.edges;
    float d = max(q.x, q.y);
    if (constants.kind == 3)
        d = length(max(q, 0.0)) + min(d, 0.0) - constants.cornerRadius;
    else if (constants.kind == 5)
        d = length(input.position) - constants.cornerRadius;

    float coverage;
    if (constants.mode == 2)
    {
        float t = saturate(roundHalf(roundHalf(-d * constants.distanceScale) + 0.5));
        coverage = cubic(cubic(t));
    }
    else
    {
        float a = roundHalf(roundHalf(fwidth(d)) * 0.5);
        float t = saturate(roundHalf(roundHalf(a - roundHalf(d)) / roundHalf(a + a)));
        coverage = cubic(t);
    }
    return PRIMITIVE_OUTPUT_TYPE(roundHalf(input.color.r * coverage), roundHalf(input.color.g * coverage),
                                 roundHalf(input.color.b * coverage), roundHalf(input.color.a * coverage));
}
