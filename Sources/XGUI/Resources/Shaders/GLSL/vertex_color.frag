#version 450

layout (location=0) in vec2 texUV;
layout (location=1) in vec4 color;

layout (location=0) out vec4 outFragColor;

void main(void) {
    outFragColor = color;
}
