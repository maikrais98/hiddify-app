#include <flutter/runtime_effect.glsl>

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_intensity;
uniform float u_motion;
uniform float u_phase;

out vec4 fragColor;

float hash(float p) {
  return fract(sin(p * 127.1) * 43758.5453);
}

float noise(float p) {
  float i = floor(p);
  float f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(hash(i), hash(i + 1.0), f);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / u_resolution;
  uv.y = 1.0 - uv.y;
  float t = u_phase + u_time * u_motion * 0.035;
  vec3 light = vec3(0.0);
  for (int i = 0; i < 20; i++) {
    float z = float(i) / 20.0;
    float x = uv.x + z * 0.075;
    float fold = noise(x * 5.0 + t) * 0.065 + noise(x * 13.0 - t * 0.3) * 0.018;
    float arc = 0.70 - 0.075 * sin(x * 3.8 - 1.2) - 0.080 * x + fold + z * 0.040;
    float d = uv.y - arc;
    float silk = 0.68 + 0.32 * pow(noise(uv.x * 90.0 + t * 0.6 + z * 0.65), 2.0);
    float curtain = exp(-max(-d, 0.0) * (18.0 + 26.0 * noise(x * 12.0))) * exp(-max(d, 0.0) * 90.0);
    float hem = exp(-abs(d) * 150.0) * 0.18;
    float hue = smoothstep(0.55, 0.78, noise(x * 3.0 + t * 0.2 + z));
    vec3 jade = mix(vec3(0.10, 0.98, 0.60), vec3(0.08, 0.78, 0.96), z);
    float violetAccent = smoothstep(0.60, 0.76, z) * (0.55 + 0.45 * hue);
    vec3 tint = mix(jade, vec3(0.82, 0.18, 1.00), violetAccent);
    light += tint * (curtain * silk + hem) * 0.230;
  }
  float second = uv.y - (0.44 + 0.040 * sin(uv.x * 4.0 + t));
  light += vec3(0.52, 0.18, 0.86) * exp(-abs(second) * 31.0) * 0.55;
  float reading = 1.0 - 0.68 * exp(-pow((uv.y - 0.235) / 0.09, 2.0));
  reading *= 1.0 - 0.42 * exp(-pow((uv.y - 0.52) / 0.10, 2.0));
  float vignette = 0.65 + 0.35 * sin(uv.x * 3.14159);
  vec3 col = light * u_intensity * reading * vignette;
  float edge = smoothstep(0.0, 0.04, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
  col = clamp(col * edge, 0.0, 1.0);
  fragColor = vec4(col, max(col.r, max(col.g, col.b)));
}
