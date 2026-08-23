//
//  File: draw_r8_opacity_image.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "image.hlsli"

float4 draw_r8_opacity_image(FragmentInput input) : SV_Target0
{
    return float4(
        input.color.rgb,
        sampleImage(input.textureCoordinate).r * input.color.a
    );
}
