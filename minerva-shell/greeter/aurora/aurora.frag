#version 440

layout(location = 0) in vec2 coord;
layout(location = 0) out vec4 fragColor;

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

// Una macchia morbida: nessun bordo, nessun cerchio riconoscibile.
// `smoothstep` da 1 a 0 su un raggio ampio è ciò che la fa somigliare a luce
// e non a una forma disegnata.
float macchia(vec2 p, vec2 centro, float raggio) {
    float d = length((p - centro) / vec2(1.0, misura.y / max(misura.x, 1.0)));
    return smoothstep(raggio, 0.0, d);
}

void main() {
    vec2 p = coord;
    float t = tempo;

    // Tre correnti lente, ognuna con un suo passo. I periodi sono numeri
    // primi fra loro apposta: se battessero insieme si vedrebbe il ciclo, e
    // uno sfondo che si ripete a occhio smette di essere vivo.
    vec2 c1 = vec2(0.28 + 0.17 * sin(t * 0.081), 0.32 + 0.13 * cos(t * 0.063));
    vec2 c2 = vec2(0.74 + 0.15 * cos(t * 0.047), 0.30 + 0.16 * sin(t * 0.055));
    vec2 c3 = vec2(0.50 + 0.24 * sin(t * 0.037), 0.78 + 0.11 * cos(t * 0.071));

    float m1 = macchia(p, c1, 0.62);
    float m2 = macchia(p, c2, 0.55);
    float m3 = macchia(p, c3, 0.70);

    vec3 colore = fondo.rgb;
    colore += tinta1.rgb * m1 * forza;
    colore += tinta2.rgb * m2 * forza;
    colore += tinta3.rgb * m3 * forza * 0.8;

    // La vignettatura scurisce i bordi: tiene l'occhio al centro, dove sta
    // quello che c'è da leggere.
    float v = 1.0 - 0.45 * length(p - vec2(0.5)) ;
    colore *= clamp(v, 0.0, 1.0);

    fragColor = vec4(colore, 1.0) * qt_Opacity;
}
