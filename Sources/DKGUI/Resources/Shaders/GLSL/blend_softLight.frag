#version 450

layout (binding=0) uniform sampler2D image1;
layout (binding=1) uniform sampler2D image2;

layout (location=0) in vec2 texUV;
layout (location=1) in vec4 color;

layout (location=0) out vec4 outFragColor;

float softLight(float src, float dst) {
    if (src <= 0.5)
        return dst - (1 - 2 * src) * dst * (1 - dst);
    else {
        float d = (dst <= 0.25) ? ((16 * dst - 12) * dst + 4) * dst : sqrt(dst);
        return dst + (2 * src - 1) * (d - dst);
    }
}

vec3 blend(vec3 src, vec3 dst) {
    return vec3(softLight(src.r, dst.r), softLight(src.g, dst.g), softLight(src.b, dst.b));
}

void main() {
    vec4 src = texture(image1, texUV) * color;
    vec4 dst = texture(image2, texUV);

    if (src.a != 0.0)   src.rgb /= src.a;
    if (dst.a != 0.0)   dst.rgb /= dst.a;

    vec3 rgb = (1.0 - dst.a) * src.rgb + dst.a * blend(src.rgb, dst.rgb);
    outFragColor = mix(vec4(dst.rgb * dst.a, dst.a), vec4(rgb, 1.0), src.a);
}
