precision highp float;
/** @resolution */
uniform vec2 u_resolution;
/** @time */
uniform float u_time;
/** @label Motion: zero for a still reduced-motion preview @default 1 @range 0,1 */
uniform float u_motion;
/** @label Preview time offset in seconds @default 0 */
uniform float u_phase;
/** @label Logical width @default 393 */
uniform float u_width;
/** @label Logical height @default 852 */
uniform float u_height;
/** @label Snow intensity @default 1 @range 0,1 */
uniform float u_intensity;

vec2 hash2(vec2 p) {
  return fract(sin(vec2(dot(p, vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);
}

float segmentDistance(vec2 p,vec2 b) {
  float h=clamp(dot(p,b)/dot(b,b),0.0,1.0);
  return length(p-b*h);
}

float snowLayer(vec2 p,vec2 grid,float speed,float radius,float strength,float t,float salt) {
  vec2 cellSize=vec2(u_width,u_height)/grid;
  float wind=sin(t*.43+salt)*5.0+sin(t*.19+salt*.7)*3.0;
  vec2 flow=vec2(t*speed*.17+wind,t*speed);
  vec2 world=(p-flow)/cellSize;
  vec2 cell=floor(world);
  vec2 seed=hash2(mod(cell+grid,grid)+salt);
  vec2 local=(fract(world)-(.2+.6*seed))*cellSize;
  float aa=max(.25,u_width/u_resolution.x*.7);
  float r=radius*(.75+.5*seed.y);
  float core=1.0-smoothstep(max(0.0,r-aa),r+aa,length(local));
  float alpha=core*strength;
  if(radius>1.0) {
    float halo=(1.0-smoothstep(r,r+4.0,length(local)))*.055;
    vec2 trail=vec2(-3.5-seed.x*2.0,-6.0-seed.y*3.0);
    float streak=(1.0-smoothstep(.25,1.05,segmentDistance(local,trail)))*.13;
    alpha=max(alpha,max(halo,streak));
  }
  return alpha;
}

void main() {
  vec2 p=vec2(gl_FragCoord.x/u_resolution.x*u_width,(1.0-gl_FragCoord.y/u_resolution.y)*u_height);
  float t=u_time*u_motion+u_phase;
  float a=snowLayer(p,vec2(13.0,26.0),14.0,.55,.22,t,3.1);
  float b=snowLayer(p,vec2(8.0,18.0),34.0,.95,.38,t,17.7);
  float c=snowLayer(p,vec2(5.0,10.0),70.0,1.65,.66,t,41.3);
  float alpha=(1.0-(1.0-a)*(1.0-b)*(1.0-c))*u_intensity;
  gl_FragColor=vec4(vec3(.82,.94,1.0)*alpha,alpha);
}
