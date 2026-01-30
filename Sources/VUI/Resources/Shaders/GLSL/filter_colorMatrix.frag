#version 450

layout (push_constant) uniform Constants {
    float colorMatrixR[5];
    float colorMatrixG[5];
    float colorMatrixB[5];
    float colorMatrixA[5];
} pc;

layout (binding=0) uniform sampler2D image;

layout (location=0) in vec2 texUV;
layout (location=1) in vec4 color;

layout (location=0) out vec4 outFragColor;

void main() {
    vec4 src = texture(image, texUV) * color;
    if (src.a != 0.0)   src.rgb /= src.a;

    vec4 cmR = vec4(pc.colorMatrixR[0], pc.colorMatrixR[1], pc.colorMatrixR[2], pc.colorMatrixR[3]);
    vec4 cmG = vec4(pc.colorMatrixG[0], pc.colorMatrixG[1], pc.colorMatrixG[2], pc.colorMatrixG[3]);
    vec4 cmB = vec4(pc.colorMatrixB[0], pc.colorMatrixB[1], pc.colorMatrixB[2], pc.colorMatrixB[3]);
    vec4 cmA = vec4(pc.colorMatrixA[0], pc.colorMatrixA[1], pc.colorMatrixA[2], pc.colorMatrixA[3]);
    float r = dot(src, cmR) + pc.colorMatrixR[4];
    float g = dot(src, cmG) + pc.colorMatrixG[4];
    float b = dot(src, cmB) + pc.colorMatrixB[4];
    float a = dot(src, cmA) + pc.colorMatrixA[4];

    vec4 result = clamp(vec4(r, g, b, a), vec4(0), vec4(1));
    result.rgb *= result.a;
    outFragColor = result;
}
