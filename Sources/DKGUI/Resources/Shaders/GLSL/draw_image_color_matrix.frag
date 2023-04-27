#version 450

layout (push_constant) uniform Constants {
    float colorMatrixR[5];
    float colorMatrixG[5];
    float colorMatrixB[5];
    float colorMatrixA[5];
} pc;

layout (binding=0) uniform sampler2D maskImage;
layout (binding=1) uniform sampler2D image;

layout (location=0) in vec2 maskUV;
layout (location=1) in vec2 texUV;
layout (location=2) in vec4 color;

layout (location=0) out vec4 outFragColor;

void main() {
    if (texture(maskImage, maskUV).r <= 0)
        discard;
    vec4 fragColor = texture(image, texUV) * color;
    vec4 cmR = vec4(pc.colorMatrixR[0], pc.colorMatrixR[1], pc.colorMatrixR[2], pc.colorMatrixR[3]);
    vec4 cmG = vec4(pc.colorMatrixG[0], pc.colorMatrixG[1], pc.colorMatrixG[2], pc.colorMatrixG[3]);
    vec4 cmB = vec4(pc.colorMatrixB[0], pc.colorMatrixB[1], pc.colorMatrixB[2], pc.colorMatrixB[3]);
    vec4 cmA = vec4(pc.colorMatrixA[0], pc.colorMatrixA[1], pc.colorMatrixA[2], pc.colorMatrixA[3]);
    float r = dot(fragColor, cmR) + pc.colorMatrixR[4];
    float g = dot(fragColor, cmG) + pc.colorMatrixG[4];
    float b = dot(fragColor, cmB) + pc.colorMatrixB[4];
    float a = dot(fragColor, cmA) + pc.colorMatrixA[4];
    outFragColor = vec4(r, g, b, a);
}
