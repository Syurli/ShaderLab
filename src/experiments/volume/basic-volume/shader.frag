uniform float uTime;
uniform vec2 uResolution;
uniform vec2 uPointer;
uniform float uDensity;
uniform float uAbsorption;
uniform int uSteps;
uniform float uNoiseScale;
uniform float uJitter;
uniform vec3 uVolumeColor;

varying vec2 vUv;

float hash13(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);

  float n000 = hash13(i + vec3(0, 0, 0));
  float n100 = hash13(i + vec3(1, 0, 0));
  float n010 = hash13(i + vec3(0, 1, 0));
  float n110 = hash13(i + vec3(1, 1, 0));
  float n001 = hash13(i + vec3(0, 0, 1));
  float n101 = hash13(i + vec3(1, 0, 1));
  float n011 = hash13(i + vec3(0, 1, 1));
  float n111 = hash13(i + vec3(1, 1, 1));

  float nx00 = mix(n000, n100, f.x);
  float nx10 = mix(n010, n110, f.x);
  float nx01 = mix(n001, n101, f.x);
  float nx11 = mix(n011, n111, f.x);
  float nxy0 = mix(nx00, nx10, f.y);
  float nxy1 = mix(nx01, nx11, f.y);
  return mix(nxy0, nxy1, f.z);
}

float densityField(vec3 p) {
  float sphere = 1.0 - smoothstep(0.55, 1.0, length(p));
  float detail = noise3(p * uNoiseScale + vec3(0.0, uTime * 0.12, uTime * 0.05));
  detail += 0.5 * noise3(p * uNoiseScale * 2.1 - vec3(uTime * 0.07, 0.0, 0.0));
  detail /= 1.5;
  return sphere * smoothstep(0.22, 0.82, detail) * uDensity;
}

bool intersectBox(vec3 ro, vec3 rd, out float tNear, out float tFar) {
  vec3 inv = 1.0 / rd;
  vec3 t0 = (-vec3(1.0) - ro) * inv;
  vec3 t1 = ( vec3(1.0) - ro) * inv;
  vec3 tMin = min(t0, t1);
  vec3 tMax = max(t0, t1);
  tNear = max(max(tMin.x, tMin.y), tMin.z);
  tFar = min(min(tMax.x, tMax.y), tMax.z);
  return tFar > max(tNear, 0.0);
}

void main() {
  vec2 uv = (gl_FragCoord.xy * 2.0 - uResolution.xy) / max(uResolution.y, 1.0);
  vec3 ro = vec3(0.0, 0.0, 3.0);
  vec3 rd = normalize(vec3(uv, -1.65));

  float tNear;
  float tFar;
  vec3 background = mix(vec3(0.015, 0.02, 0.032), vec3(0.05, 0.07, 0.11), vUv.y);

  if (!intersectBox(ro, rd, tNear, tFar)) {
    gl_FragColor = vec4(background, 1.0);
    return;
  }

  tNear = max(tNear, 0.0);
  float travel = tFar - tNear;
  float stepSize = travel / float(uSteps);
  float jitter = (hash13(vec3(gl_FragCoord.xy, fract(uTime))) - 0.5) * stepSize * uJitter;
  float t = tNear + jitter;

  vec3 accumulated = vec3(0.0);
  float transmittance = 1.0;

  for (int i = 0; i < 384; i++) {
    if (i >= uSteps) break;
    vec3 p = ro + rd * t;
    float density = densityField(p);
    float alpha = 1.0 - exp(-density * uAbsorption * stepSize);

    vec3 lightDir = normalize(vec3(-0.5, 0.8, 0.6));
    float lightProbe = densityField(p + lightDir * 0.12);
    float lighting = exp(-lightProbe * 1.4) * 0.75 + 0.25;

    accumulated += transmittance * alpha * uVolumeColor * lighting;
    transmittance *= 1.0 - alpha;

    if (transmittance < 0.015) break;
    t += stepSize;
  }

  vec3 color = accumulated + background * transmittance;
  color = pow(color, vec3(0.4545));
  gl_FragColor = vec4(color, 1.0);
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uDensity": {
      "type": "float",
      "default": 1.35,
      "min": 0.0,
      "max": 4.0,
      "step": 0.01,
      "label": { "zh": "密度", "en": "Density" },
      "description": { "zh": "对体积密度场进行整体缩放。", "en": "Scales the overall volume density field." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uAbsorption": {
      "type": "float",
      "default": 2.2,
      "min": 0.0,
      "max": 8.0,
      "step": 0.01,
      "label": { "zh": "吸收系数", "en": "Absorption" },
      "description": { "zh": "控制 Beer-Lambert 吸收强度。", "en": "Controls Beer-Lambert absorption strength." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uSteps": {
      "type": "int",
      "default": 128,
      "min": 16,
      "max": 384,
      "step": 1,
      "label": { "zh": "采样步数", "en": "Ray Steps" },
      "description": { "zh": "体积积分的最大采样次数；越高越平滑但成本更高。", "en": "Maximum volume integration samples; higher values are smoother but more expensive." },
      "group": { "zh": "采样", "en": "Sampling" }
    },
    "uNoiseScale": {
      "type": "float",
      "default": 2.8,
      "min": 0.5,
      "max": 8.0,
      "step": 0.01,
      "label": { "zh": "噪声尺度", "en": "Noise Scale" },
      "description": { "zh": "控制程序化密度细节的空间频率。", "en": "Controls the spatial frequency of procedural density detail." },
      "group": { "zh": "形态", "en": "Shape" }
    },
    "uJitter": {
      "type": "float",
      "default": 0.85,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "label": { "zh": "抖动", "en": "Jitter" },
      "description": { "zh": "在首个采样位置加入随机偏移，减弱固定步长带状伪影。", "en": "Offsets the first sample to reduce fixed-step banding artifacts." },
      "group": { "zh": "采样", "en": "Sampling" }
    },
    "uVolumeColor": {
      "type": "color",
      "default": "#88b8ff",
      "label": { "zh": "体积颜色", "en": "Volume Color" },
      "description": { "zh": "参与体积积分的散射颜色。", "en": "Scattering color accumulated during volume integration." },
      "group": { "zh": "外观", "en": "Appearance" }
    }
  }
}
@endshaderlab */
