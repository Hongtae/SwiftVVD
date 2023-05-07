#version 450

layout (binding=0) uniform sampler2D image1;
layout (binding=1) uniform sampler2D image2;

layout (location=0) in vec2 texUV;
layout (location=1) in vec4 color;

layout (location=0) out vec4 outFragColor;

float lum(vec3 c) {
    return 0.3 * c.r + 0.59 * c.g + 0.11 * c.b;
}

vec3 clip(vec3 c) {
    float l = lum(c);
    float n = min(c.r, min(c.g, c.b));
    float x = max(c.r, max(c.g, c.b));
    if (n < 0.0)
        c = l + (((c - l) * l) / (l - n));
    if (x > 1.0)
        c = l + (((c - l) * (1.0 - l)) / (x - l));
    return c;
}

vec3 set_lum(vec3 c, float l) {
    float d = l - lum(c);
    return clip(c + d);
}

vec3 blend(vec3 src, vec3 dst) {
    return set_lum(src, lum(dst));
}

void main() {
    vec4 src = texture(image1, texUV) * color;
    vec4 dst = texture(image2, texUV);

    if (src.a != 0.0)   src.rgb /= src.a;
    if (dst.a != 0.0)   dst.rgb /= dst.a;

    vec3 rgb = (1.0 - dst.a) * src.rgb + dst.a * blend(src.rgb, dst.rgb);
    outFragColor = mix(vec4(dst.rgb * dst.a, dst.a), vec4(rgb, 1.0), src.a);
}
