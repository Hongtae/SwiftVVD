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
    float cornerRadius0;
    float cornerRadius1;
    float mixWeight0;
    float mixWeight1;
    float distanceScale;
    uint kind;
    uint mode;
};
[[vk::push_constant]] ConstantBuffer<Constants> constants;

// Keep each coverage rounding point without requiring a 16-bit shader feature.
float roundHalf(float x) { return f16tof32(f32tof16(x)); }
float cubic(float t) { return roundHalf(roundHalf(t * t) * roundHalf(mad(t, -2.0, 3.0))); }

float continuousLength(float2 value, float radius)
{
    float lengthValue = length(value);
    float a = min(abs(value.x), abs(value.y));
    float b = mad(max(radius - lengthValue, 0.0), 0.25, max(abs(value.x), abs(value.y)));
    float denominator = dot(float2(a, b), float2(0.361, 0.639));
    float t = denominator != 0.0 ? a / denominator : 0.0;
    float polynomial = t * t * t * mad(t, mad(t, -0.538410, 1.346025), -0.897350);
    return mad(polynomial, radius, lengthValue);
}

PRIMITIVE_OUTPUT_TYPE primitive_color(FragmentInput input) : SV_Target0
{
    if (constants.kind == 1) return PRIMITIVE_OUTPUT_TYPE(input.color);
    float2 q = abs(input.position) - constants.edges;
    float d = max(q.x, q.y);
    if (constants.kind == 3)
        d = length(max(q, 0.0)) + min(d, 0.0) - constants.cornerRadius0;
    else if (constants.kind == 4)
        d = continuousLength(max(q, 0.0), constants.cornerRadius0) + min(d, 0.0) - constants.cornerRadius0;
    else if (constants.kind == 5)
        d = length(input.position) - constants.cornerRadius0;
    else if (constants.kind == 6 || constants.kind == 7)
    {
        float4 cornerRadii = float4(constants.cornerRadius0, constants.cornerRadius1,
                                    constants.mixWeight0, constants.mixWeight1);
        uint corner = input.position.y < 0.0
            ? (input.position.x < 0.0 ? 0 : 1)
            : (input.position.x < 0.0 ? 3 : 2);
        float radius = cornerRadii[corner];
        q = abs(input.position) + radius - constants.edges;
        d = max(q.x, q.y);
        if (constants.kind == 6)
            d = length(max(q, 0.0)) + min(d, 0.0) - radius;
        else
            d = continuousLength(max(q, 0.0), radius) + min(d, 0.0) - radius;
    }
    else if (constants.kind == 10)
    {
        float2 continuousVector = max(q + constants.cornerRadius0, 0.0);
        float continuous = continuousLength(continuousVector, constants.cornerRadius0) - constants.cornerRadius0;
        float2 circularVector = q + constants.cornerRadius1;
        float circular = length(max(circularVector, 0.0)) - constants.cornerRadius1;
        float2 direction = circularVector * rsqrt(dot(circularVector, circularVector));
        float weight = saturate(dot(direction, float2(constants.mixWeight0, constants.mixWeight1)));
        d = lerp(continuous, circular, weight * weight);
    }

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
