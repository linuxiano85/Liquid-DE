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
float minerva_coverage() {
 vec2 p=v_minerva*minerva_size;
 float a=1.0;
 if(any(greaterThan(minerva_radii,vec4(0.0)))) a=minerva_round(p,minerva_size,minerva_radii);
 if(minerva_hole.z>0.0 && minerva_hole.w>0.0) a*=1.0-minerva_round(p-minerva_hole.xy,minerva_hole.zw,minerva_hole_radii);
 return a;
}

void main() {
	gl_FragColor = color;
	gl_FragColor *= minerva_coverage();
}
