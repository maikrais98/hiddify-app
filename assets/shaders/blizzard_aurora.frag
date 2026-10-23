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
  vec3 sky = vec3(0.02745, 0.08235, 0.11373);
  vec3 light = vec3(0.0);
  for (int i = 0; i < 20; i++) {
    float z = float(i) / 20.0;
    float x = uv.x + z * 0.075;
    float fold = noise(x * 5.0 + t) * 0.065 + noise(x * 13.0 - t * 0.3) * 0.018;
    float arc = 0.34 + 0.08 * sin(x * 3.8 - 1.2) + 0.09 * x + fold + z * 0.040;
    float d = uv.y - arc;
    float silk = 0.62 + 0.38 * pow(noise(uv.x * 90.0 + t * 0.6 + z * 0.65), 2.0);
    float curtain = exp(-max(-d, 0.0) * (14.0 + 22.0 * noise(x * 12.0))) * exp(-max(d, 0.0) * 90.0);
    float hem = exp(-abs(d) * 150.0) * 0.15;
    float hue = smoothstep(0.5, 0.95, noise(x * 3.0 + t * 0.2 + z));
    vec3 jade = mix(vec3(0.22, 0.80, 0.58), vec3(0.22, 0.64, 0.75), z);
    vec3 tint = mix(jade, vec3(0.48, 0.37, 0.78), hue * 0.55);
    light += tint * (curtain * silk + hem) * 0.067;
  }
  float second = uv.y - (0.76 + 0.035 * sin(uv.x * 4.0 + t));
  light += vec3(0.07, 0.24, 0.22) * exp(-abs(second) * 31.0) * 0.15;
  float reading = 1.0 - 0.68 * exp(-pow((uv.y - 0.235) / 0.09, 2.0));
  float vignette = 0.65 + 0.35 * sin(uv.x * 3.14159);
  vec3 col = sky + light * u_intensity * reading * vignette;
  for (int j = 0; j < 16; j++) {
    float k = float(j) + 1.0;
    vec2 star = vec2(hash(k * 7.2), hash(k * 12.8));
    vec2 dist = (uv - star) * u_resolution;
    float point = exp(-dot(dist, dist) / 0.52) * (0.13 + hash(k) * 0.23);
    col += vec3(0.70, 0.83, 0.85) * point;
  }
  fragColor = vec4(col, 1.0);
}
