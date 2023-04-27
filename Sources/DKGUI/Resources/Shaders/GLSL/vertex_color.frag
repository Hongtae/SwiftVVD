#version 450

layout (binding=0) uniform sampler2D maskImage;

layout (location=0) in vec2 maskUV;
layout (location=1) in vec2 texUV;
layout (location=2) in vec4 color;

layout (location=0) out vec4 outFragColor;

void main(void) {
    if (texture(maskImage, maskUV).r <= 0)
        discard;
    outFragColor = color;
}
