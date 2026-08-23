//
//  File: filter_colorMatrix.frag.hlsl
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "image.hlsli"

struct Constants
{
    float colorMatrixR[5];
    float colorMatrixG[5];
    float colorMatrixB[5];
    float colorMatrixA[5];
};

[[vk::push_constant]] ConstantBuffer<Constants> constants;

float4 filter_colorMatrix(FragmentInput input) : SV_Target0
{
    float4 source = sampleImage(input.textureCoordinate) * input.color;
    if (source.a != 0.0)
        source.rgb /= source.a;

    float4 matrixR = float4(
        constants.colorMatrixR[0], constants.colorMatrixR[1],
        constants.colorMatrixR[2], constants.colorMatrixR[3]
    );
    float4 matrixG = float4(
        constants.colorMatrixG[0], constants.colorMatrixG[1],
        constants.colorMatrixG[2], constants.colorMatrixG[3]
    );
    float4 matrixB = float4(
        constants.colorMatrixB[0], constants.colorMatrixB[1],
        constants.colorMatrixB[2], constants.colorMatrixB[3]
    );
    float4 matrixA = float4(
        constants.colorMatrixA[0], constants.colorMatrixA[1],
        constants.colorMatrixA[2], constants.colorMatrixA[3]
    );
    float4 result = saturate(float4(
        dot(source, matrixR) + constants.colorMatrixR[4],
        dot(source, matrixG) + constants.colorMatrixG[4],
        dot(source, matrixB) + constants.colorMatrixB[4],
        dot(source, matrixA) + constants.colorMatrixA[4]
    ));
    result.rgb *= result.a;
    return result;
}
