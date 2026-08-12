uniform float uTime;
uniform vec2 uResolution;
uniform vec2 uPointer;
uniform float uRadius;
uniform float uMaxDistance;
uniform int uSteps;
uniform float uEpsilon;
uniform vec3 uBaseColor;

varying vec2 vUv;

float mapScene(vec3 p) {
  vec3 center = vec3(sin(uTime * 0.45) * 0.18, cos(uTime * 0.35) * 0.12, 0.0);
  return length(p - center) - uRadius;
}

vec3 getNormal(vec3 p) {
  vec2 e = vec2(uEpsilon, 0.0);
  return normalize(vec3(
    mapScene(p + e.xyy) - mapScene(p - e.xyy),
    mapScene(p + e.yxy) - mapScene(p - e.yxy),
    mapScene(p + e.yyx) - mapScene(p - e.yyx)
  ));
}

void main() {
  vec2 uv = (gl_FragCoord.xy * 2.0 - uResolution.xy) / max(uResolution.y, 1.0);
  vec3 ro = vec3(0.0, 0.0, 3.2);
  vec3 rd = normalize(vec3(uv, -1.8));

  float total = 0.0;
  float hit = 0.0;
  vec3 p = ro;

  for (int i = 0; i < 256; i++) {
    if (i >= uSteps) break;
    p = ro + rd * total;
    float d = mapScene(p);
    if (d < uEpsilon) {
      hit = 1.0;
      break;
    }
    total += d;
    if (total > uMaxDistance) break;
  }

  vec3 bg = vec3(0.025, 0.03, 0.045) + 0.08 * vec3(vUv.y);
  vec3 color = bg;

  if (hit > 0.5) {
    vec3 n = getNormal(p);
    vec3 lightDir = normalize(vec3(-0.6, 0.8, 0.7));
    float diffuse = max(dot(n, lightDir), 0.0);
    float rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
    float checker = 0.5 + 0.5 * sin(8.0 * p.x) * sin(8.0 * p.y) * sin(8.0 * p.z);
    color = uBaseColor * (0.18 + diffuse * 0.82);
    color += rim * vec3(0.35, 0.55, 1.0);
    color *= mix(0.82, 1.08, checker);
  }

  gl_FragColor = vec4(pow(color, vec3(0.4545)), 1.0);
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uRadius": {
      "type": "float",
      "default": 0.82,
      "min": 0.2,
      "max": 1.4,
      "step": 0.01,
      "label": { "zh": "球体半径", "en": "Sphere Radius" },
      "description": { "zh": "SDF 球体的半径。", "en": "Radius used by the sphere signed distance field." },
      "group": { "zh": "几何", "en": "Geometry" }
    },
    "uSteps": {
      "type": "int",
      "default": 96,
      "min": 8,
      "max": 256,
      "step": 1,
      "label": { "zh": "最大步数", "en": "Max Steps" },
      "description": { "zh": "Sphere tracing 的最大迭代次数。", "en": "Maximum number of sphere-tracing iterations." },
      "group": { "zh": "Ray Marching", "en": "Ray Marching" }
    },
    "uEpsilon": {
      "type": "float",
      "default": 0.0015,
      "min": 0.0002,
      "max": 0.02,
      "step": 0.0001,
      "label": { "zh": "命中阈值", "en": "Hit Epsilon" },
      "description": { "zh": "距离场小于该值时视为命中表面。", "en": "Treats the ray as a surface hit below this distance." },
      "group": { "zh": "Ray Marching", "en": "Ray Marching" }
    },
    "uMaxDistance": {
      "type": "float",
      "default": 8.0,
      "min": 2.0,
      "max": 20.0,
      "step": 0.1,
      "label": { "zh": "最大距离", "en": "Max Distance" },
      "description": { "zh": "光线超过该距离后提前终止。", "en": "Terminates the ray after it travels beyond this distance." },
      "group": { "zh": "Ray Marching", "en": "Ray Marching" }
    },
    "uBaseColor": {
      "type": "color",
      "default": "#6fa8ff",
      "label": { "zh": "基础颜色", "en": "Base Color" },
      "description": { "zh": "SDF 表面的基础漫反射颜色。", "en": "Base diffuse color of the SDF surface." },
      "group": { "zh": "外观", "en": "Appearance" }
    }
  }
}
@endshaderlab */
