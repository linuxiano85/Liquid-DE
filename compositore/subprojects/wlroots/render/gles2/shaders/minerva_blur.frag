precision highp float;
varying vec2 v_texcoord;
uniform sampler2D tex;
uniform sampler2D mask;
uniform vec2 step_uv;
uniform vec4 capture;
uniform float composite;
uniform float has_mask;
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
 if (composite>0.5) {
  vec2 uv=(gl_FragCoord.xy-capture.xy)/capture.zw;
  float a=minerva_coverage();
  if(has_mask>0.5) a*=texture2D(mask,v_minerva).a;
  gl_FragColor=texture2D(tex,uv)*a;
 } else {
  vec4 c=vec4(0.0); float total=0.0;
  for(int i=-4;i<=4;i++) { float w=exp(-float(i*i)/8.0); c+=texture2D(tex,v_minerva+float(i)*step_uv)*w; total+=w; }
  gl_FragColor=c/total;
 }
}
