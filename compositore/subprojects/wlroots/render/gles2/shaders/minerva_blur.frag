precision highp float;
varying vec2 v_texcoord;
uniform sampler2D tex;
uniform sampler2D mask;
uniform vec4 capture;
uniform float has_mask;
/* L'acquerello, vedi minerva_acquerello_pezzo in pass.c. `fase` 2 riduce
 * a 1/4, 3 da 1/4 a 1/32, 4 stende; 0 e 1 sono il blur. Tutte le coordinate
 * sono pixel del framebuffer e ogni lettura cade nel CENTRO di un texel:
 * così lo stesso pixel esce identico a pezzi e per intero. */
uniform float fase;
uniform vec2 a_base;
uniform vec4 a_valido;
uniform vec4 a_cattura;
uniform vec4 a_celle;
uniform vec4 a_piccola;
varying vec2 v_minerva;
uniform vec2 minerva_size;
uniform vec4 minerva_radii;
uniform vec4 minerva_hole;
uniform vec4 minerva_hole_radii;
float minerva_round(vec2 p, vec2 size, vec4 r) {
 float radius = p.x < size.x * 0.5 ? (p.y < size.y*0.5 ? r.x:r.w) : (p.y<size.y*0.5?r.y:r.z);
 radius=clamp(radius,0.0,min(size.x,size.y)*0.5);
 vec2 q=abs(p-size*0.5)-(size*0.5-vec2(radius));
 float d=length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-radius;
 return 1.0-smoothstep(-0.5,0.5,d);
}
uniform float mer_n;
uniform vec4 mer_f[8];
uniform vec2 mer_kr;
float mer_d(vec2 p, vec4 f) {
 vec2 h=f.zw*0.5;
 float r=clamp(mer_kr.y,0.0,min(h.x,h.y));
 vec2 q=abs(p-(f.xy+h))-(h-vec2(r));
 return length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-r;
}
float mer_smin(float a, float b) {
 float k=mer_kr.x;
 float h=max(k-abs(a-b),0.0)/k;
 return min(a,b)-h*h*k*0.25;
}
/* Mercurio: dentro l'unione morbida e fuori dalle forme. Sotto il bordo di
 * una finestra il materiale entra di un pixel e mezzo, o fra il bordo
 * ammorbidito della finestra e quello del ponte passerebbe un filo di fondo. */
float minerva_mercurio(vec2 p) {
 float d[8];
 float mn=1e5;
 for (int i=0;i<8;i++) {
  if (float(i)>=mer_n) break;
  d[i]=mer_d(p,mer_f[i]);
  mn=min(mn,d[i]);
 }
 float u=mn;
 for (int i=0;i<8;i++) {
  if (float(i)>=mer_n) break;
  for (int j=0;j<8;j++) {
   if (j<=i) continue;
   if (float(j)>=mer_n) break;
   u=min(u,mer_smin(d[i],d[j]));
  }
 }
 return (1.0-smoothstep(-0.5,0.5,u))*smoothstep(-2.0,-1.0,mn);
}
float minerva_coverage() {
 vec2 p=v_minerva*minerva_size;
 float a=1.0;
 if(any(greaterThan(minerva_radii,vec4(0.0)))) a=minerva_round(p,minerva_size,minerva_radii);
 if(minerva_hole.z>0.0 && minerva_hole.w>0.0) a*=1.0-minerva_round(p-minerva_hole.xy,minerva_hole.zw,minerva_hole_radii);
 if(mer_n>0.5) a*=minerva_mercurio(p);
 return a;
}


/* La maschera dice DOVE la superficie c'è, non quanto è opaca. Usata come
 * peso, dietro una dock al 68 % il filtro arrivava al 68 % del 32 % che
 * passa, e il resto era lo sfondo nitido: blur e acquerello uscivano quasi
 * uguali, e quasi uguali a niente (27 settembre 2026). Dove l'alfa passa un
 * quarto il filtro sostituisce lo sfondo per intero; sotto, una rampa per i
 * bordi sfumati e le ombre. */
float minerva_dove() {
 return clamp(texture2D(mask,v_texcoord).a*4.0,0.0,1.0);
}

/* Il colore di una cella, per indice di cella (tenuto dentro l'area). */
vec4 acquerello_cella(vec2 c) {
 c=clamp(c,a_celle.xy,a_celle.zw);
 return texture2D(tex,(c-a_piccola.xy+0.5)/a_piccola.zw);
}

/* Due pesi per asse sulle tre celle b, b+1, b+2: `u` sono i quattro campioni
 * a mezza cella del primo acquerello (sommati), `w` quello al centro. */
float acquerello_peso(vec3 v, int i) {
 return i==0 ? v.x : (i==1 ? v.y : v.z);
}

/* ── L'Acrylic di Windows 11 ─────────────────────────────────────────────
 *
 * La ricetta di WinUI (AcrylicBrush.cpp, MIT): sullo sfondo sfocato
 *   1. fusione LUMINOSITÀ col colore `ac_luminosita` (alfa = opacità di
 *      luminosità): tinta e saturazione dello sfondo, chiarezza sua. È ciò
 *      che rende le schede di Windows «leggermente in blur» e sempre
 *      leggibili: i colori dello sfondo passano, i contrasti no;
 *   2. fusione COLORE con `ac_tinta` (alfa = opacità della tinta);
 *   3. rumore, 2 %.
 * Le fusioni sono quelle del W3C (Compositing and Blending, «non-separable
 * blend modes»), le stesse di Direct2D. */
uniform float ac_attivo;
uniform vec4 ac_tinta;
uniform vec4 ac_luminosita;
uniform float ac_rumore;

float ac_lum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }
vec3 ac_clip(vec3 c) {
 float l = ac_lum(c);
 float n = min(min(c.r, c.g), c.b);
 float x = max(max(c.r, c.g), c.b);
 if (n < 0.0) c = l + (c - l) * l / max(l - n, 1e-5);
 if (x > 1.0) c = l + (c - l) * (1.0 - l) / max(x - l, 1e-5);
 return c;
}
vec3 ac_setlum(vec3 c, float l) { return ac_clip(c + (l - ac_lum(c))); }

vec4 acrylic(vec4 sfocato) {
 if (ac_attivo < 0.5) return sfocato;
 /* L'Acrylic è sempre pieno: dove dietro non c'è niente (sotto la barra lo
  * sfondo può mancare) vale il colore della ricetta, come il ripiego di
  * Windows. Lo sfondo sfocato, premoltiplicato, si compone sopra di lui. */
 vec3 c = sfocato.rgb + (1.0 - sfocato.a) * ac_luminosita.rgb;
 /* 1. luminosità: tinta e saturazione di `c`, luminosità del colore */
 c = mix(c, ac_setlum(c, ac_lum(ac_luminosita.rgb)), ac_luminosita.a);
 /* 2. colore: tinta e saturazione del colore, luminosità di `c` */
 c = mix(c, ac_setlum(ac_tinta.rgb, ac_lum(c)), ac_tinta.a);
 /* 3. rumore: un valore fisso per pixel dello schermo, quindi non scintilla
  * quando il fotogramma si rifà.
  *
  * Niente `fract(sin(…))`: con l'argomento oltre 65 536 il `sin` di questa
  * scheda (radeonsi) non dà più un numero, e una diagonale di pixel neri
  * tagliava la barra (11 ottobre 2026). Questo è il rumore a gradiente
  * intrecciato di Jimenez: solo moltiplicazioni e `fract`, valido ovunque. */
 float r = fract(52.9829189 * fract(dot(floor(gl_FragCoord.xy), vec2(0.06711056, 0.00583715))));
 c += (r - 0.5) * ac_rumore;
 return vec4(clamp(c, 0.0, 1.0), 1.0);
}

vec4 acquerello() {
 vec2 i=floor(gl_FragCoord.xy);
 vec4 s=vec4(0.0);
 if (fase<2.5) {
  /* 4×4 pixel del framebuffer (catturati) → un texel. */
  for (int a=0;a<4;a++) for (int b=0;b<4;b++) {
   vec2 q=clamp(a_base+i*4.0+vec2(float(a),float(b)),a_valido.xy,a_valido.zw);
   s+=texture2D(tex,(q-a_cattura.xy+0.5)/a_cattura.zw);
  }
  return s/16.0;
 }
 if (fase<3.5) {
  /* 8×8 texel da 1/4 → la cella da 32×32. */
  for (int a=0;a<8;a++) for (int b=0;b<8;b++)
   s+=texture2D(tex,(i*8.0+vec2(float(a),float(b))+0.5)/a_cattura.zw);
  return s/64.0;
 }
 /* La stesura: il vecchio «bilineare più quattro campioni a mezza cella»,
  * coi pesi scritti qui invece che lasciati al campionatore — che li
  * arrotonderebbe in modo diverso secondo la misura della cattura. */
 vec2 t=(gl_FragCoord.xy-a_base)/32.0-0.5;
 vec2 b=floor(t-0.5), g=t-0.5-b;
 vec3 ux=vec3(1.0-g.x,1.0,g.x), uy=vec3(1.0-g.y,1.0,g.y);
 vec3 wx=g.x<0.5 ? vec3(0.5-g.x,0.5+g.x,0.0) : vec3(0.0,1.5-g.x,g.x-0.5);
 vec3 wy=g.y<0.5 ? vec3(0.5-g.y,0.5+g.y,0.0) : vec3(0.0,1.5-g.y,g.y-0.5);
 for (int y=0;y<3;y++) for (int x=0;x<3;x++) {
  float p=2.0*acquerello_peso(wx,x)*acquerello_peso(wy,y)
   +acquerello_peso(ux,x)*acquerello_peso(uy,y);
  s+=p*acquerello_cella(b+vec2(float(x),float(y)));
 }
 float a=minerva_coverage();
 if(has_mask>0.5) a*=minerva_dove();
 return acrylic(s/6.0)*a;
}

/* Due mestieri: l'acquerello (fase 2, 3, 4) e la copia di un pezzo di
 * fotogramma messo da parte (le fasce, `minerva_ripristina` in pass.c). Il
 * blur gaussiano che stava qui è stato tolto il 28 settembre 2026. */
void main() {
 if (fase>1.5) { gl_FragColor=acquerello(); return; }
 vec2 uv=(gl_FragCoord.xy-capture.xy)/capture.zw;
 float a=minerva_coverage();
 if(has_mask>0.5) a*=minerva_dove();
 gl_FragColor=texture2D(tex,uv)*a;
}
