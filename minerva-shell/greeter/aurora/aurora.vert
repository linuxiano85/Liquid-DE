#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 coord;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    vec4 tinta1;
    vec4 tinta2;
    vec4 tinta3;
    vec4 fondo;
    vec2 misura;
    float qt_Opacity;
    float tempo;
    float forza;
};

void main() {
    coord = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
