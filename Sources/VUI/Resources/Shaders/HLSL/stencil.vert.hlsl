//
//  File: stencil.vert.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

float4 stencil([[vk::location(0)]] float2 position : POSITION0) : SV_Position
{
    return float4(position, 0.0, 1.0);
}
