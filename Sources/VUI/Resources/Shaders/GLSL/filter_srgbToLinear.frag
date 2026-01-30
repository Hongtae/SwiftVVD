#version 450

layout (push_constant) uniform Constants {
    mat3 matrix;
} pc;

layout (binding=0) uniform sampler2D image;

layout (location=0) in vec2 texUV;
layout (location=1) in vec4 color;

layout (location=0) out vec4 outFragColor;

float if_then_else(bool c, float t, float e) {
    return c ? t : e;
}

vec3 if_then_else(bvec3 c, vec3 t, vec3 e) {
    return vec3(if_then_else(c.x, t.x, e.x),
                if_then_else(c.y, t.y, e.y),
                if_then_else(c.z, t.z, e.z));
}

vec3 srgbToLinear(vec3 color) {
    vec3 c1 = color / 12.92;
    vec3 c2 = pow(color / 1.055 + vec3(0.055 / 1.055), vec3(2.4));
    return if_then_else(lessThanEqual(color, vec3(0.04045)), c1, c2);
}

vec3 linearToSrgb(vec3 color) {
    vec3 c1 = color * 12.92;
    vec3 c2 = vec3(1.055) * pow(color, vec3(1.0 / 2.4)) - vec3(0.055);
    return if_then_else(lessThanEqual(color, vec3(0.0031308)), c1, c2);
}

void main() {
    vec4 src = texture(image, texUV) * color;
    if (src.a != 0.0) src.rgb /= src.a;
    vec3 rgb = srgbToLinear(src.rgb) * src.a;
    outFragColor = vec4(rgb, src.a);
}
