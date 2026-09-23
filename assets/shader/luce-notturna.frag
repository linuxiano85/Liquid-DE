// luce-notturna.frag — Il filtro luce blu di Minerva.
//
// Lo applica il COMPOSITORE a tutto lo schermo (`decoration:screen_shader` di
// Hyprland), quindi vale per ogni finestra, per i giochi e per i filmati senza
// che nessuno debba saperlo.
//
// ── Perché non wlsunset o gammastep ────────────────────────────────────────
//
// Perché sono due pacchetti in più che su questa macchina non ci sono, e
// perché fanno una cosa che sappiamo già fare: Minerva disegna l'aurora della
// schermata di accesso con uno shader suo. Uno in più non aggiunge niente da
// installare, niente da far partire all'avvio, niente che possa mancare.
//
// ── Come si scalda un'immagine ─────────────────────────────────────────────
//
// Non «aggiungendo arancione»: quello sbianca i neri e fa sembrare lo schermo
// sporco. Si SPENGONO il blu e un po' di verde, che è quello che fa il sole
// quando scende — la luce non diventa arancione, diventa meno blu.
//
// I tre numeri sono i moltiplicatori di rosso, verde e blu, e arrivano da
// fuori come temperature di colore già convertite: 6500 K è la luce del
// giorno (1, 1, 1), 3400 K è la sera, 2000 K è quasi candela.
//
// Si lavora in spazio lineare e non sui valori come stanno: moltiplicare per
// 0.8 un valore già compresso in sRGB scurisce più del dovuto e il grigio
// vira. La radice e il quadrato qui sotto sono l'approssimazione veloce di
// quella conversione, ed è abbastanza per un filtro che deve essere gentile.
#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

// I moltiplicatori, scritti dalla shell a ogni cambio di intensità.
const vec3 tinta = vec3(1.0, 0.86, 0.71);

void main() {
    vec4 c = texture(tex, v_texcoord);
    vec3 lineare = c.rgb * c.rgb;      // ≈ sRGB → lineare
    lineare *= tinta;
    fragColor = vec4(sqrt(lineare), c.a);
}
