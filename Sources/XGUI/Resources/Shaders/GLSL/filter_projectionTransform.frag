#version 450

layout (push_constant) uniform Constants {
    mat3 matrix;
} pc;

layout (binding=0) uniform sampler2D image;

layout (location=0) in vec2 texUV;
layout (location=1) in vec4 color;

layout (location=0) out vec4 outFragColor;

void main() {
    vec3 uv = vec3(texUV.xy, 1) * pc.matrix;
    outFragColor = texture(image, uv.xy / uv.z) * color;
}
