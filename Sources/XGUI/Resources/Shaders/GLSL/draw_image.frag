#version 450

layout (binding=0) uniform sampler2D image;

layout (location=0) in vec2 texUV;
layout (location=1) in vec4 color;

layout (location=0) out vec4 outFragColor;

void main() {
    outFragColor = texture(image, texUV) * color;
}
