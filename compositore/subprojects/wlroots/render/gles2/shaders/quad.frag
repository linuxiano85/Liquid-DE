#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec4 v_color;
varying vec2 v_texcoord;
uniform vec4 color;


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

void main() {
	gl_FragColor = color;
	gl_FragColor *= minerva_coverage();
}
