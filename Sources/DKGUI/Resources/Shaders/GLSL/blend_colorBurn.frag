#version 450

layout (binding=0) uniform sampler2D image1;
layout (binding=1) uniform sampler2D image2;

layout (location=0) in vec2 texUV;
layout (location=1) in vec4 color;

layout (location=0) out vec4 outFragColor;

float blend(float src, float dst) {
    return (dst == 1) ? 1 : ((src == 0) ? 0 : (1 - min(1, (1 - dst) / src)));
}

vec3 blend(vec3 src, vec3 dst) {
    return src;
}

void main() {
    vec4 src = texture(image1, texUV);
    vec4 dst = texture(image2, texUV);

    vec3 rgb = (1 - dst.a) * src.rgb + dst.a * blend(src.rgb, dst.rgb);
    outFragColor = mix(vec4(dst.rgb * dst.a, dst.a), vec4(rgb, 1), src.a * color.a);
}
