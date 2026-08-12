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

fn radians(degrees: f32) -> f32 {
  return degrees * 0.017453292519943295;
}

fn rotateY(p: vec3f, angle: f32) -> vec3f {
  let c = cos(angle);
  let s = sin(angle);
  return vec3f(c * p.x - s * p.z, p.y, s * p.x + c * p.z);
}

fn worldToModel(p: vec3f) -> vec3f {
  return rotateY(p, -radians(params.uModelYaw.x));
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

fn plumeEnvelope(worldP: vec3f, time: f32) -> vec4f {
  let p = worldToModel(worldP);
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
  let safeDir = select(rd, vec3f(0.00001), abs(rd) < vec3f(0.00001));
  let invDir = 1.0 / safeDir;
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

fn lightPosition() -> vec3f {
  let azimuth = radians(params.uLightAzimuth.x);
  let elevation = radians(params.uLightElevation.x);
  let distance = params.uLightDistance.x;
  let horizontal = cos(elevation) * distance;
  return vec3f(
    sin(azimuth) * horizontal,
    0.25 + sin(elevation) * distance,
    cos(azimuth) * horizontal,
  );
}

fn volumeShadowToLight(p: vec3f, time: f32) -> f32 {
  let lightPos = lightPosition();
  let toLight = lightPos - p;
  let lightDistance = max(length(toLight), 0.001);
  let lightDir = toLight / lightDistance;
  let stepLength = lightDistance / 6.0;
  var opticalDepth = 0.0;
  var sampleP = p + lightDir * stepLength * 0.5;

  for (var i = 0; i < 6; i = i + 1) {
    opticalDepth = opticalDepth + densityFieldShadow(sampleP, time) * stepLength;
    sampleP = sampleP + lightDir * stepLength;
  }

  return exp(-opticalDepth * params.uShadowStrength.x);
}

fn smokeLight(p: vec3f, time: f32, viewDir: vec3f) -> vec3f {
  let lightPos = lightPosition();
  let toLight = lightPos - p;
  let lightDistance = max(length(toLight), 0.001);
  let lightDir = toLight / lightDistance;
  let attenuation = 1.0 / (1.0 + 0.09 * lightDistance * lightDistance);
  let shadow = volumeShadowToLight(p, time);
  let phase = phaseHG(dot(lightDir, -viewDir), params.uAnisotropy.x);
  let smoke = params.uSmokeColor.xyz;
  let lightColor = params.uLightColor.xyz;
  let ambient = smoke * 0.16;
  let direct = smoke * lightColor * params.uLightIntensity.x * attenuation * shadow * (0.25 + 0.75 * phase);
  return ambient + direct;
}

fn groundLighting(groundP: vec3f, time: f32) -> vec3f {
  let lightPos = lightPosition();
  let toLight = lightPos - groundP;
  let distance = max(length(toLight), 0.001);
  let lightDir = toLight / distance;
  let nDotL = max(lightDir.y, 0.0);
  let attenuation = 1.0 / (1.0 + 0.065 * distance * distance);
  let shadow = volumeShadowToLight(groundP + vec3f(0.0, 0.02, 0.0), time);
  return params.uLightColor.xyz * params.uLightIntensity.x * nDotL * attenuation * shadow;
}

fn backgroundColor(ro: vec3f, rd: vec3f, time: f32) -> vec3f {
  let skyT = clamp(rd.y * 0.5 + 0.5, 0.0, 1.0);
  var color = mix(vec3f(0.055, 0.062, 0.073), vec3f(0.16, 0.19, 0.23), vec3f(skyT));

  if (rd.y < -0.001) {
    let groundT = (-1.32 - ro.y) / rd.y;
    if (groundT > 0.0) {
      let groundP = ro + rd * groundT;
      let distanceFade = exp(-0.06 * dot(groundP.xz, groundP.xz));
      let groundBase = mix(vec3f(0.045, 0.048, 0.052), vec3f(0.075, 0.079, 0.086), vec3f(distanceFade));
      color = groundBase + groundLighting(groundP, time) * 0.14;
    }
  }

  let modelAngle = -radians(params.uModelYaw.x);
  let localRo = rotateY(ro, modelAngle);
  let localRd = rotateY(rd, modelAngle);
  let stackHit = intersectBox(
    localRo,
    localRd,
    vec3f(-0.28, -1.32, -0.20),
    vec3f(0.28, -0.70, 0.20),
  );
  if (stackHit.y > max(stackHit.x, 0.0)) {
    let hitT = max(stackHit.x, 0.0);
    let hitP = localRo + localRd * hitT;
    let brick = step(0.5, fract((hitP.y + 1.32) * 7.0));
    let brickColor = mix(vec3f(0.08, 0.055, 0.045), vec3f(0.15, 0.095, 0.065), vec3f(brick * 0.4));
    let worldHit = ro + rd * hitT;
    color = brickColor + groundLighting(worldHit, time) * 0.18;
  }

  return color;
}

fn displayTransform(color: vec3f) -> vec3f {
  let mapped = color / (color + vec3f(1.0));
  return pow(max(mapped, vec3f(0.0)), vec3f(1.0 / 2.2));
}

@fragment
fn fsMain(@builtin(position) fragCoord: vec4f) -> @location(0) vec4f {
  let resolution = max(frame.timeResolution.yz, vec2f(1.0));
  let aspect = frame.timeResolution.w;
  let pointer = frame.pointerPixelRatio.xy;
  let time = frame.timeResolution.x;

  let pointerOrbit = step(0.5, params.uPointerOrbit.x);
  let yaw = radians(params.uCameraYaw.x + (pointer.x - 0.5) * 360.0 * pointerOrbit);
  let pitchDegrees = clamp(params.uCameraPitch.x + (pointer.y - 0.5) * 40.0 * pointerOrbit, -85.0, 85.0);
  let pitch = radians(pitchDegrees);
  let cameraTarget = vec3f(0.0, params.uTargetHeight.x, 0.0);
  let distance = params.uCameraDistance.x;
  let horizontalDistance = cos(pitch) * distance;
  let ro = cameraTarget + vec3f(
    sin(yaw) * horizontalDistance,
    sin(pitch) * distance,
    cos(yaw) * horizontalDistance,
  );
  let forward = normalize(cameraTarget - ro);
  let right = normalize(cross(forward, vec3f(0.0, 1.0, 0.0)));
  let up = normalize(cross(right, forward));

  var screen = fragCoord.xy / resolution * 2.0 - vec2f(1.0);
  screen.y = -screen.y;
  screen.x = screen.x * aspect;
  let fovScale = tan(radians(params.uCameraFov.x) * 0.5);
  let rd = normalize(forward + right * screen.x * fovScale + up * screen.y * fovScale);

  let hit = intersectBox(
    ro,
    rd,
    vec3f(-1.18, -0.82, -1.18),
    vec3f(1.18, 2.16, 1.18),
  );

  let background = backgroundColor(ro, rd, time);
  if (hit.y <= max(hit.x, 0.0)) {
    return vec4f(displayTransform(background), 1.0);
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
  return vec4f(displayTransform(color), 1.0);
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uDensity": {
      "type": "float", "default": 1.15, "min": 0.15, "max": 3.0, "step": 0.01,
      "label": { "zh": "烟雾密度", "en": "Smoke Density" },
      "description": { "zh": "整体缩放程序化烟雾的体积密度。", "en": "Scales the overall procedural smoke density." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uAbsorption": {
      "type": "float", "default": 1.45, "min": 0.2, "max": 4.0, "step": 0.01,
      "label": { "zh": "吸收系数", "en": "Absorption" },
      "description": { "zh": "Beer-Lambert 消光强度；数值越高烟雾越厚重。", "en": "Beer-Lambert extinction strength; higher values make the smoke more opaque." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uSteps": {
      "type": "int", "default": 64, "min": 24, "max": 128, "step": 1,
      "label": { "zh": "采样步数", "en": "Ray Steps" },
      "description": { "zh": "主视线体积积分的最大采样数。", "en": "Maximum sample count for primary volume integration." },
      "group": { "zh": "质量", "en": "Quality" }
    },
    "uJitter": {
      "type": "boolean", "default": true,
      "label": { "zh": "抖动采样", "en": "Jitter Sampling" },
      "description": { "zh": "随机偏移起始采样位置，减少层状条纹。", "en": "Offsets the first sample per pixel to reduce banding." },
      "group": { "zh": "质量", "en": "Quality" }
    },
    "uBaseRadius": {
      "type": "float", "default": 0.34, "min": 0.12, "max": 0.75, "step": 0.01,
      "label": { "zh": "底部半径", "en": "Base Radius" },
      "description": { "zh": "烟囱出口附近烟柱的基础宽度。", "en": "Base plume radius close to the chimney outlet." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uTopRadius": {
      "type": "float", "default": 0.82, "min": 0.3, "max": 1.15, "step": 0.01,
      "label": { "zh": "顶部扩散", "en": "Top Spread" },
      "description": { "zh": "控制烟雾上升后的横向扩散程度。", "en": "Controls lateral plume expansion as smoke rises." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uNoiseScale": {
      "type": "float", "default": 1.55, "min": 0.5, "max": 4.0, "step": 0.01,
      "label": { "zh": "噪声尺度", "en": "Noise Scale" },
      "description": { "zh": "FBM 密度场的空间频率。", "en": "Spatial frequency of the FBM density field." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uThreshold": {
      "type": "float", "default": 0.42, "min": 0.1, "max": 0.8, "step": 0.01,
      "label": { "zh": "密度阈值", "en": "Density Threshold" },
      "description": { "zh": "切割低密度噪声，塑造更明显的烟团边界。", "en": "Cuts low-density noise to form more distinct billows." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uTurbulence": {
      "type": "float", "default": 0.72, "min": 0.0, "max": 1.8, "step": 0.01,
      "label": { "zh": "湍流", "en": "Turbulence" },
      "description": { "zh": "控制烟柱弯曲、摆动与卷动幅度。", "en": "Controls plume bending, sway, and curl amplitude." },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uRiseSpeed": {
      "type": "float", "default": 0.48, "min": 0.0, "max": 1.5, "step": 0.01,
      "label": { "zh": "上升速度", "en": "Rise Speed" },
      "description": { "zh": "沿竖直方向平流噪声场的速度。", "en": "Vertical advection speed of the procedural noise field." },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uSmokeColor": {
      "type": "color", "default": "#b7c0ca",
      "label": { "zh": "烟雾颜色", "en": "Smoke Color" },
      "description": { "zh": "单次散射近似使用的基础烟雾颜色。", "en": "Base smoke color used by the single-scattering approximation." },
      "group": { "zh": "光照", "en": "Lighting" }
    },
    "uShadowStrength": {
      "type": "float", "default": 2.2, "min": 0.0, "max": 8.0, "step": 0.01,
      "label": { "zh": "投影/自阴影强度", "en": "Shadow Strength" },
      "description": { "zh": "控制烟雾对自身以及地面的体积投影强度。", "en": "Controls volumetric self-shadowing and projected smoke shadow on the ground." },
      "group": { "zh": "光照", "en": "Lighting" }
    },
    "uAnisotropy": {
      "type": "float", "default": 0.22, "min": -0.75, "max": 0.75, "step": 0.01,
      "label": { "zh": "散射各向异性", "en": "Anisotropy" },
      "description": { "zh": "Henyey-Greenstein 相函数 g；正值偏前向散射。", "en": "Henyey-Greenstein phase parameter g; positive values favor forward scattering." },
      "group": { "zh": "光照", "en": "Lighting" }
    },
    "uLightAzimuth": {
      "type": "float", "default": 315.0, "min": 0.0, "max": 360.0, "step": 1.0,
      "label": { "zh": "光源方位角", "en": "Light Azimuth" },
      "description": { "zh": "绕场景 Y 轴旋转点光源。", "en": "Rotates the point light around the scene Y axis." },
      "group": { "zh": "光源", "en": "Light" }
    },
    "uLightElevation": {
      "type": "float", "default": 48.0, "min": 5.0, "max": 85.0, "step": 1.0,
      "label": { "zh": "光源仰角", "en": "Light Elevation" },
      "description": { "zh": "控制光源在场景上方的高度角。", "en": "Controls the light elevation above the scene." },
      "group": { "zh": "光源", "en": "Light" }
    },
    "uLightDistance": {
      "type": "float", "default": 4.0, "min": 1.5, "max": 8.0, "step": 0.05,
      "label": { "zh": "光源距离", "en": "Light Distance" },
      "description": { "zh": "光源与烟雾中心的距离。", "en": "Distance from the light to the smoke volume." },
      "group": { "zh": "光源", "en": "Light" }
    },
    "uLightIntensity": {
      "type": "float", "default": 4.5, "min": 0.0, "max": 12.0, "step": 0.05,
      "label": { "zh": "光源强度", "en": "Light Intensity" },
      "description": { "zh": "同时影响烟雾散射与地面受光。", "en": "Affects both volume scattering and ground illumination." },
      "group": { "zh": "光源", "en": "Light" }
    },
    "uLightColor": {
      "type": "color", "default": "#ffe0b3",
      "label": { "zh": "光源颜色", "en": "Light Color" },
      "description": { "zh": "点光源颜色。", "en": "Point light color." },
      "group": { "zh": "光源", "en": "Light" }
    },
    "uCameraYaw": {
      "type": "float", "default": 0.0, "min": 0.0, "max": 360.0, "step": 1.0,
      "label": { "zh": "相机水平旋转", "en": "Camera Yaw" },
      "description": { "zh": "相机绕目标 360° 水平旋转。鼠标位置可在此基础上追加一整圈偏移。", "en": "Rotates the camera 360 degrees around the target; pointer orbit can add another full turn." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraPitch": {
      "type": "float", "default": 8.0, "min": -80.0, "max": 80.0, "step": 1.0,
      "label": { "zh": "相机俯仰", "en": "Camera Pitch" },
      "description": { "zh": "控制相机仰视/俯视角。", "en": "Controls camera elevation around the target." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraDistance": {
      "type": "float", "default": 3.4, "min": 1.4, "max": 8.0, "step": 0.05,
      "label": { "zh": "相机距离", "en": "Camera Distance" },
      "description": { "zh": "拉近或远离烟雾与烟囱。", "en": "Dollies the camera toward or away from the smoke and chimney." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraFov": {
      "type": "float", "default": 52.0, "min": 25.0, "max": 85.0, "step": 1.0,
      "label": { "zh": "相机视场角", "en": "Camera FOV" },
      "description": { "zh": "控制透视视场角。", "en": "Controls the perspective field of view." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uTargetHeight": {
      "type": "float", "default": 0.35, "min": -0.4, "max": 1.5, "step": 0.01,
      "label": { "zh": "观察目标高度", "en": "Target Height" },
      "description": { "zh": "上下移动相机围绕旋转的观察目标。", "en": "Moves the camera orbit target vertically." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uPointerOrbit": {
      "type": "boolean", "default": true,
      "label": { "zh": "鼠标辅助环绕", "en": "Pointer Orbit" },
      "description": { "zh": "开启后，鼠标从画布左到右对应额外 360° 环绕，上下对应额外俯仰。", "en": "When enabled, horizontal pointer position adds a full 360-degree orbit and vertical position adjusts pitch." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uModelYaw": {
      "type": "float", "default": 0.0, "min": 0.0, "max": 360.0, "step": 1.0,
      "label": { "zh": "模型水平旋转", "en": "Model Yaw" },
      "description": { "zh": "旋转烟囱和程序化烟雾局部坐标。", "en": "Rotates the chimney and procedural smoke local coordinate system." },
      "group": { "zh": "模型", "en": "Model" }
    }
  }
}
@endshaderlab */