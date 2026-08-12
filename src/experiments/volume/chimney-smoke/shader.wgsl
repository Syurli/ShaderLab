// ShaderLab injects `frame: ShaderLabFrame` and `params: ShaderLabParams`.
// Each @shaderlab parameter occupies one vec4f slot in `params`.

struct VertexOutput {
  @builtin(position) position: vec4f,
};

@vertex
fn vsMain(@builtin(vertex_index) vertexIndex: u32) -> VertexOutput {
  var positions = array<vec2f, 3>(
    vec2f(-1.0, -1.0),
    vec2f(3.0, -1.0),
    vec2f(-1.0, 3.0),
  );
  var output: VertexOutput;
  output.position = vec4f(positions[vertexIndex], 0.0, 1.0);
  return output;
}

fn hash31(pInput: vec3f) -> f32 {
  var p = fract(pInput * vec3f(0.1031, 0.1030, 0.0973));
  p = p + dot(p, p.yzx + vec3f(33.33));
  return fract((p.x + p.y) * p.z);
}

fn valueNoise(p: vec3f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (vec3f(3.0) - 2.0 * f);

  let n000 = hash31(i + vec3f(0.0, 0.0, 0.0));
  let n100 = hash31(i + vec3f(1.0, 0.0, 0.0));
  let n010 = hash31(i + vec3f(0.0, 1.0, 0.0));
  let n110 = hash31(i + vec3f(1.0, 1.0, 0.0));
  let n001 = hash31(i + vec3f(0.0, 0.0, 1.0));
  let n101 = hash31(i + vec3f(1.0, 0.0, 1.0));
  let n011 = hash31(i + vec3f(0.0, 1.0, 1.0));
  let n111 = hash31(i + vec3f(1.0, 1.0, 1.0));

  let x00 = mix(n000, n100, u.x);
  let x10 = mix(n010, n110, u.x);
  let x01 = mix(n001, n101, u.x);
  let x11 = mix(n011, n111, u.x);
  let y0 = mix(x00, x10, u.y);
  let y1 = mix(x01, x11, u.y);
  return mix(y0, y1, u.z);
}

fn fbmMain(pInput: vec3f) -> f32 {
  var p = pInput;
  var amplitude = 0.5;
  var total = 0.0;
  var normalization = 0.0;

  for (var octave = 0; octave < 4; octave = octave + 1) {
    total = total + valueNoise(p) * amplitude;
    normalization = normalization + amplitude;
    p = p * 2.03 + vec3f(17.13, 9.71, 13.57);
    amplitude = amplitude * 0.5;
  }

  return total / normalization;
}

fn fbmShadow(pInput: vec3f) -> f32 {
  var p = pInput;
  var amplitude = 0.64;
  var total = 0.0;
  var normalization = 0.0;

  for (var octave = 0; octave < 2; octave = octave + 1) {
    total = total + valueNoise(p) * amplitude;
    normalization = normalization + amplitude;
    p = p * 2.01 + vec3f(11.7, 5.3, 7.9);
    amplitude = amplitude * 0.45;
  }

  return total / normalization;
}

fn plumeEnvelope(p: vec3f, time: f32) -> vec4f {
  let y01 = clamp((p.y + 0.72) / 2.82, 0.0, 1.0);
  let turbulence = params.uTurbulence.x;
  let drift = vec2f(
    sin(p.y * 2.1 + time * 0.57),
    cos(p.y * 1.63 - time * 0.43),
  ) * turbulence * (0.06 + 0.21 * y01);

  let centered = vec3f(p.x - drift.x, p.y, p.z - drift.y);
  let radius = mix(params.uBaseRadius.x, params.uTopRadius.x, y01);
  let radial = length(centered.xz);
  let plume = 1.0 - smoothstep(radius * 0.5, radius, radial);
  let bottomFade = smoothstep(-0.76, -0.52, p.y);
  let topFade = 1.0 - smoothstep(1.62, 2.10, p.y);
  let envelope = plume * bottomFade * topFade;

  return vec4f(centered, envelope);
}

fn densityField(p: vec3f, time: f32) -> f32 {
  let shaped = plumeEnvelope(p, time);
  if (shaped.w <= 0.001) {
    return 0.0;
  }

  let centered = shaped.xyz;
  let scale = params.uNoiseScale.x;
  let rise = params.uRiseSpeed.x;
  let turbulence = params.uTurbulence.x;
  let advected = vec3f(
    centered.x * scale,
    centered.y * scale - time * rise,
    centered.z * scale,
  );
  let curlOffset = vec2f(
    sin(advected.y * 1.35 + time * 0.31),
    cos(advected.y * 1.11 - time * 0.27),
  ) * turbulence * 0.38;

  let sampleP = vec3f(
    advected.x + curlOffset.x,
    advected.y,
    advected.z + curlOffset.y,
  );

  let coarse = fbmMain(sampleP);
  let detail = valueNoise(sampleP * 2.35 + vec3f(4.7, 1.9, 8.1));
  let mixedNoise = coarse * 0.84 + detail * 0.16;
  let threshold = clamp(params.uThreshold.x, 0.0, 0.95);
  let billow = smoothstep(threshold, 1.0, mixedNoise);

  return max(0.0, shaped.w * billow * params.uDensity.x);
}

fn densityFieldShadow(p: vec3f, time: f32) -> f32 {
  let shaped = plumeEnvelope(p, time);
  if (shaped.w <= 0.001) {
    return 0.0;
  }

  let scale = params.uNoiseScale.x * 0.82;
  let rise = params.uRiseSpeed.x;
  let sampleP = vec3f(
    shaped.x * scale,
    shaped.y * scale - time * rise,
    shaped.z * scale,
  );
  let coarse = fbmShadow(sampleP);
  let threshold = clamp(params.uThreshold.x * 0.92, 0.0, 0.9);
  let billow = smoothstep(threshold, 1.0, coarse);
  return shaped.w * billow * params.uDensity.x;
}

fn intersectBox(ro: vec3f, rd: vec3f, bmin: vec3f, bmax: vec3f) -> vec2f {
  let invDir = 1.0 / rd;
  let t0 = (bmin - ro) * invDir;
  let t1 = (bmax - ro) * invDir;
  let lo = min(t0, t1);
  let hi = max(t0, t1);
  let tNear = max(max(lo.x, lo.y), lo.z);
  let tFar = min(min(hi.x, hi.y), hi.z);
  return vec2f(tNear, tFar);
}

fn phaseHG(cosTheta: f32, gInput: f32) -> f32 {
  let g = clamp(gInput, -0.88, 0.88);
  let g2 = g * g;
  let denominator = pow(max(0.001, 1.0 + g2 - 2.0 * g * cosTheta), 1.5);
  return (1.0 - g2) / denominator;
}

fn smokeLight(p: vec3f, time: f32, viewDir: vec3f) -> vec3f {
  let lightDir = normalize(vec3f(-0.52, 0.78, 0.34));
  var opticalDepth = 0.0;
  var sampleP = p;

  for (var i = 0; i < 3; i = i + 1) {
    sampleP = sampleP + lightDir * 0.27;
    opticalDepth = opticalDepth + densityFieldShadow(sampleP, time) * 0.27;
  }

  let shadow = exp(-opticalDepth * params.uShadowStrength.x);
  let phase = phaseHG(dot(lightDir, -viewDir), params.uAnisotropy.x);
  let base = params.uSmokeColor.xyz;
  let ambient = base * 0.22;
  let direct = base * shadow * (0.30 + 0.70 * phase);
  return ambient + direct;
}

fn backgroundColor(ro: vec3f, rd: vec3f) -> vec3f {
  let skyT = clamp(rd.y * 0.5 + 0.5, 0.0, 1.0);
  var color = mix(vec3f(0.055, 0.062, 0.073), vec3f(0.16, 0.19, 0.23), vec3f(skyT));

  if (rd.y < -0.001) {
    let groundT = (-1.32 - ro.y) / rd.y;
    if (groundT > 0.0) {
      let groundP = ro + rd * groundT;
      let distanceFade = exp(-0.06 * dot(groundP.xz, groundP.xz));
      color = mix(vec3f(0.055, 0.058, 0.064), vec3f(0.075, 0.079, 0.086), vec3f(distanceFade));
    }
  }

  let stackHit = intersectBox(
    ro,
    rd,
    vec3f(-0.23, -1.32, -0.23),
    vec3f(0.23, -0.70, 0.23),
  );
  if (stackHit.y > max(stackHit.x, 0.0)) {
    let hitT = max(stackHit.x, 0.0);
    let hitP = ro + rd * hitT;
    let brick = step(0.5, fract((hitP.y + 1.32) * 7.0));
    color = mix(vec3f(0.09, 0.07, 0.06), vec3f(0.13, 0.09, 0.07), vec3f(brick * 0.35));
  }

  return color;
}

@fragment
fn fsMain(@builtin(position) fragCoord: vec4f) -> @location(0) vec4f {
  let resolution = max(frame.timeResolution.yz, vec2f(1.0));
  let aspect = frame.timeResolution.w;
  let pointer = frame.pointerPixelRatio.xy;
  let time = frame.timeResolution.x;

  let yaw = (pointer.x - 0.5) * 0.78;
  let pitch = (pointer.y - 0.5) * 0.34;
  let cameraTarget = vec3f(0.0, 0.35, 0.0);
  let ro = vec3f(sin(yaw) * 3.25, 0.30 + pitch * 1.8, cos(yaw) * 3.25);
  let forward = normalize(cameraTarget - ro);
  let right = normalize(cross(forward, vec3f(0.0, 1.0, 0.0)));
  let up = normalize(cross(right, forward));

  var screen = fragCoord.xy / resolution * 2.0 - vec2f(1.0);
  screen.y = -screen.y;
  screen.x = screen.x * aspect;
  let rd = normalize(forward + right * screen.x * 0.62 + up * screen.y * 0.62);

  let hit = intersectBox(
    ro,
    rd,
    vec3f(-1.12, -0.78, -1.12),
    vec3f(1.12, 2.12, 1.12),
  );

  let background = backgroundColor(ro, rd);
  if (hit.y <= max(hit.x, 0.0)) {
    return vec4f(background, 1.0);
  }

  let steps = clamp(i32(round(params.uSteps.x)), 16, 128);
  let startT = max(hit.x, 0.0);
  let endT = hit.y;
  let stepSize = (endT - startT) / f32(steps);
  let jitterEnabled = step(0.5, params.uJitter.x);
  let pixelHash = hash31(vec3f(floor(fragCoord.xy), floor(time * 20.0)));
  var t = startT + stepSize * mix(0.5, pixelHash, jitterEnabled);

  var transmittance = 1.0;
  var scattering = vec3f(0.0);

  for (var i = 0; i < 128; i = i + 1) {
    if (i >= steps || t >= endT || transmittance < 0.02) {
      break;
    }

    let p = ro + rd * t;
    let density = densityField(p, time);
    if (density > 0.003) {
      let extinction = density * params.uAbsorption.x;
      let alpha = 1.0 - exp(-extinction * stepSize);
      let lighting = smokeLight(p, time, rd);
      scattering = scattering + transmittance * alpha * lighting;
      transmittance = transmittance * (1.0 - alpha);
    }

    t = t + stepSize;
  }

  let color = scattering + transmittance * background;
  let mapped = color / (color + vec3f(1.0));
  let gamma = pow(mapped, vec3f(1.0 / 2.2));
  return vec4f(gamma, 1.0);
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uDensity": {
      "type": "float",
      "default": 1.15,
      "min": 0.15,
      "max": 3.0,
      "step": 0.01,
      "label": { "zh": "烟雾密度", "en": "Smoke Density" },
      "description": { "zh": "整体缩放程序化烟雾的体积密度。", "en": "Scales the overall procedural smoke density." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uAbsorption": {
      "type": "float",
      "default": 1.45,
      "min": 0.2,
      "max": 4.0,
      "step": 0.01,
      "label": { "zh": "吸收系数", "en": "Absorption" },
      "description": { "zh": "Beer-Lambert 消光强度；数值越高烟雾越厚重。", "en": "Beer-Lambert extinction strength; higher values make the smoke more opaque." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uSteps": {
      "type": "int",
      "default": 64,
      "min": 24,
      "max": 128,
      "step": 1,
      "label": { "zh": "采样步数", "en": "Ray Steps" },
      "description": { "zh": "主视线体积积分的最大采样数。默认值针对实时预览优化。", "en": "Maximum sample count for primary volume integration. The default is tuned for realtime preview." },
      "group": { "zh": "质量", "en": "Quality" }
    },
    "uJitter": {
      "type": "boolean",
      "default": true,
      "label": { "zh": "抖动采样", "en": "Jitter Sampling" },
      "description": { "zh": "对每个像素的起始采样位置做随机偏移，减少层状条纹。", "en": "Offsets the first sample per pixel to reduce ray-marching banding." },
      "group": { "zh": "质量", "en": "Quality" }
    },
    "uBaseRadius": {
      "type": "float",
      "default": 0.34,
      "min": 0.12,
      "max": 0.75,
      "step": 0.01,
      "label": { "zh": "底部半径", "en": "Base Radius" },
      "description": { "zh": "烟囱出口附近烟柱的基础宽度。", "en": "Base plume radius close to the chimney outlet." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uTopRadius": {
      "type": "float",
      "default": 0.82,
      "min": 0.3,
      "max": 1.15,
      "step": 0.01,
      "label": { "zh": "顶部扩散", "en": "Top Spread" },
      "description": { "zh": "控制烟雾上升后的横向扩散程度。", "en": "Controls lateral plume expansion as smoke rises." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uNoiseScale": {
      "type": "float",
      "default": 1.55,
      "min": 0.5,
      "max": 4.0,
      "step": 0.01,
      "label": { "zh": "噪声尺度", "en": "Noise Scale" },
      "description": { "zh": "FBM 密度场的空间频率。", "en": "Spatial frequency of the FBM density field." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uThreshold": {
      "type": "float",
      "default": 0.42,
      "min": 0.1,
      "max": 0.8,
      "step": 0.01,
      "label": { "zh": "密度阈值", "en": "Density Threshold" },
      "description": { "zh": "切割低密度噪声，塑造更明显的烟团边界。", "en": "Cuts low-density noise to form more distinct billows." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uTurbulence": {
      "type": "float",
      "default": 0.72,
      "min": 0.0,
      "max": 1.8,
      "step": 0.01,
      "label": { "zh": "湍流", "en": "Turbulence" },
      "description": { "zh": "控制烟柱弯曲、摆动与卷动幅度。", "en": "Controls plume bending, sway, and curl amplitude." },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uRiseSpeed": {
      "type": "float",
      "default": 0.48,
      "min": 0.0,
      "max": 1.5,
      "step": 0.01,
      "label": { "zh": "上升速度", "en": "Rise Speed" },
      "description": { "zh": "沿竖直方向平流噪声场的速度。", "en": "Vertical advection speed of the procedural noise field." },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uSmokeColor": {
      "type": "color",
      "default": "#b7c0ca",
      "label": { "zh": "烟雾颜色", "en": "Smoke Color" },
      "description": { "zh": "参与单次散射近似的基础烟雾颜色。", "en": "Base smoke color used by the single-scattering approximation." },
      "group": { "zh": "光照", "en": "Lighting" }
    },
    "uShadowStrength": {
      "type": "float",
      "default": 2.0,
      "min": 0.0,
      "max": 6.0,
      "step": 0.01,
      "label": { "zh": "自阴影强度", "en": "Self Shadow" },
      "description": { "zh": "沿主光方向使用低成本密度采样得到的体积自阴影强度。", "en": "Strength of low-cost density sampling along the main light direction." },
      "group": { "zh": "光照", "en": "Lighting" }
    },
    "uAnisotropy": {
      "type": "float",
      "default": 0.22,
      "min": -0.75,
      "max": 0.75,
      "step": 0.01,
      "label": { "zh": "散射各向异性", "en": "Anisotropy" },
      "description": { "zh": "Henyey-Greenstein 相函数 g；正值偏前向散射。", "en": "Henyey-Greenstein phase parameter g; positive values favor forward scattering." },
      "group": { "zh": "光照", "en": "Lighting" }
    }
  }
}
@endshaderlab */
