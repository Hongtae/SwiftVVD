//
//  File: projective.vert.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct VertexInput
{
    [[vk::location(0)]] float4 position : POSITION0;
    [[vk::location(1)]] float2 textureCoordinate : TEXCOORD0;
    [[vk::location(2)]] float4 color : COLOR0;
};

struct VertexOutput
{
    float4 position : SV_Position;
    [[vk::location(0)]] float2 textureCoordinate : TEXCOORD0;
    [[vk::location(1)]] float4 color : COLOR0;
};

VertexOutput projective(VertexInput input)
{
    VertexOutput output;
    output.position = input.position;
    output.textureCoordinate = input.textureCoordinate;
    output.color = input.color;
    return output;
}
