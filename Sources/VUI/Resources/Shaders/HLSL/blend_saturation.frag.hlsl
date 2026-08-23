//
//  File: blend_saturation.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "blend.hlsli"

float lum(float3 c) {
    return 0.3 * c.r + 0.59 * c.g + 0.11 * c.b;
}

float3 clipColor(float3 c) {
    float l = lum(c);
    float n = min(c.r, min(c.g, c.b));
    float x = max(c.r, max(c.g, c.b));
    if (n < 0.0)
        c = l + (((c - l) * l) / (l - n));
    if (x > 1.0)
        c = l + (((c - l) * (1.0 - l)) / (x - l));
    return c;
}

float3 set_lum(float3 c, float l) {
    float d = l - lum(c);
    return clipColor(c + d);
}

float sat(float3 c) {
    return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
}

void set_sat_inner(inout float cmin, inout float cmid, inout float cmax, float s) {
    if (cmax > cmin) {
        cmid = (((cmid - cmin) * s) / (cmax - cmin));
        cmax = s;
    } else {
        cmid = 0.0;
        cmax = 0.0;
    }
    cmin = 0.0;
}

float3 set_sat(float3 c, float s) {
    if (c.r <= c.g) {
        if (c.g <= c.b) {
            set_sat_inner(c.r, c.g, c.b, s);
        } else {
            if (c.r <= c.b) {
                set_sat_inner(c.r, c.b, c.g, s);
            } else {
                set_sat_inner(c.b, c.r, c.g, s);
            }
        }
    } else {
        if (c.r <= c.b) {
            set_sat_inner(c.g, c.r, c.b, s);
        } else {
            if (c.g <= c.b) {
                set_sat_inner(c.g, c.b, c.r, s);
            } else {
                set_sat_inner(c.b, c.g, c.r, s);
            }
        }
    }
    return c;
}

float3 blend(float3 src, float3 dst) {
    return set_lum(set_sat(dst, sat(src)), lum(dst));
}

float4 blend_saturation(FragmentInput input) : SV_Target0
{
    float4 outFragColor;
    float4 src = sampleSource(input.textureCoordinate) * input.color;
    float4 dst = sampleDestination(input.textureCoordinate);

    if (src.a != 0.0)   src.rgb /= src.a;
    if (dst.a != 0.0)   dst.rgb /= dst.a;

    float3 rgb = (1.0 - dst.a) * src.rgb + dst.a * blend(src.rgb, dst.rgb);
    outFragColor = lerp(float4(dst.rgb * dst.a, dst.a), float4(rgb, 1.0), src.a);
    return outFragColor;
}
