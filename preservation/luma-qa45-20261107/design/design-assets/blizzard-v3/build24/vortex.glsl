precision highp float;
/** @resolution */
uniform vec2 u_resolution;
/** @time */
uniform float u_time;
/** @label Motion:0 for Reduce Motion @default 1 @range 0,1 */
uniform float u_motion;
/** @label Phase in seconds @default 0 */
uniform float u_phase;
/** @label Logical width @default 353 */
uniform float u_width;
/** @label Logical height @default 260 */
uniform float u_height;
/** @label Vertical paint bleed @default 12 */
uniform float u_pad;
const float PI=3.141592653589793;
const float TAU=6.283185307179586;
vec2 surface(float v,float a,float phase){
 float r=28.0+135.0*v+11.0*v*sin(3.0*a-4.0*v+phase)+8.0*v*sin(2.0*a+5.0*v-phase);
 return vec2(cos(a)*r,.69*sin(a)*r+14.0*v*sin(2.0*a-3.0*v+phase));
}
void main(){
 vec2 pt=vec2(gl_FragCoord.x/u_resolution.x*u_width,(1.0-gl_FragCoord.y/u_resolution.y)*(u_height+2.0*u_pad)-u_pad);
 vec2 q=(pt-vec2(u_width*.5,u_height*137.0/260.0))/vec2(u_width/353.0,u_height/260.0);
 float phase=(u_time*u_motion+u_phase)*TAU/12.0;
 float shear=.7*sin(phase);
 float a=atan(q.y/.69,q.x);
 float v=(length(q/vec2(1.0,.69))-28.0)/135.0;
 for(int i=0;i<4;i++){
  float t1=3.0*a-4.0*v+phase,t2=2.0*a+5.0*v-phase,t3=2.0*a-3.0*v+phase;
  float r=28.0+135.0*v+11.0*v*sin(t1)+8.0*v*sin(t2);
  float rv=135.0+11.0*sin(t1)-44.0*v*cos(t1)+8.0*sin(t2)+40.0*v*cos(t2);
  float ra=33.0*v*cos(t1)+16.0*v*cos(t2);
  vec2 f=vec2(cos(a)*r,.69*sin(a)*r+14.0*v*sin(t3))-q;
  vec2 dv=vec2(cos(a)*rv,.69*sin(a)*rv+14.0*sin(t3)-42.0*v*cos(t3));
  vec2 da=vec2(-sin(a)*r+cos(a)*ra,.69*(cos(a)*r+sin(a)*ra)+28.0*v*cos(t3));
  float det=dv.x*da.y-da.x*dv.y;
  if(abs(det)>.01){v-=clamp((f.x*da.y-da.x*f.y)/det,-.15,.15);a-=clamp((dv.x*f.y-f.x*dv.y)/det,-.3,.3);}
 }
 float alpha=0.0;
 float pixel=353.0/u_resolution.x;
 float row=floor(v*44.0+.5);
 for(int ri=-1;ri<=1;ri++){
  float vr=(row+float(ri))/44.0;
  if(vr>0.0&&vr<1.0){
   float column=floor((a-phase-vr*shear)*192.0/TAU+.5);
   for(int ci=-1;ci<=1;ci++){
    float ac=(column+float(ci))*TAU/192.0+phase+vr*shear;
    float dist=length((q-surface(vr,ac,phase))*vec2(u_width/353.0,u_height/260.0));
    float radius=(.65+vr*.3)*min(u_width/353.0,u_height/260.0)*.5;
    float coverage=1.0-smoothstep(max(0.0,radius-pixel*.6),radius+pixel*.6,dist);
    alpha=max(alpha,coverage*pow(sin(vr*PI),.7));
   }
  }
 }
 float light=clamp(distance(pt,vec2(u_width*.29,u_height*.28))/(u_width*.8),0.0,1.0);
 vec3 color=light<.45?mix(vec3(.839,.949,1.0),vec3(.447,.82,1.0),light/.45):mix(vec3(.447,.82,1.0),vec3(.157,.663,.855),(light-.45)/.55);
 float opacity=light<.45?mix(.72,.42,light/.45):mix(.42,.12,(light-.45)/.55);
 alpha*=opacity;
 gl_FragColor=vec4(color*alpha,alpha);
}
