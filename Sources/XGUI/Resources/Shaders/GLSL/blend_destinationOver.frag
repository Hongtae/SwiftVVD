#version 450

layout (binding=0) uniform sampler2D image1;
layout (binding=1) uniform sampler2D image2;

layout (location=0) in vec2 texUV;
layout (location=1) in vec4 color;

layout (location=0) out vec4 outFragColor;

vec4 blend(vec4 src, vec4 dst) {
    return src * (1 - dst.a) + dst;
}

void main() {
    vec4 src = texture(image1, texUV) * color;
    vec4 dst = texture(image2, texUV);

    if (src.a != 0.0)   src.rgb /= src.a;
    if (dst.a != 0.0)   dst.rgb /= dst.a;

    vec4 rgba = blend(src, dst);
    outFragColor = mix(vec4(dst.rgb * dst.a, dst.a), rgba, src.a);
}
