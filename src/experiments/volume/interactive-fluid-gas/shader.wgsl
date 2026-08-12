struct VertexOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
};

@vertex
fn vsMain(@builtin(vertex_index) vertexIndex: u32) -> VertexOut {
  var positions = array<vec2f, 3>(
    vec2f(-1.0, -3.0),
    vec2f(-1.0, 1.0),
    vec2f(3.0, 1.0),
  );
  let p = positions[vertexIndex];
  var out: VertexOut;
  out.position = vec4f(p, 0.0, 1.0);
  out.uv = p * 0.5 + 0.5;
  return out;
}

fn fluidIndex(x: i32, y: i32) -> u32 {
  let hi = i32(FLUID_SIZE) - 1;
  let cx = clamp(x, 0, hi);
  let cy = clamp(y, 0, hi);
  return u32(cy) * FLUID_SIZE + u32(cx);
}

fn fluidCell(x: i32, y: i32) -> vec4f {
  return fluidIn.cells[fluidIndex(x, y)];
}

fn sampleFluid(uvInput: vec2f) -> vec4f {
  let uv = clamp(uvInput, vec2f(0.0), vec2f(1.0));
  let p = uv * f32(FLUID_SIZE - 1u);
  let i = vec2i(floor(p));
  let f = fract(p);
  let a = mix(fluidCell(i.x, i.y), fluidCell(i.x + 1, i.y), f.x);
  let b = mix(fluidCell(i.x, i.y + 1), fluidCell(i.x + 1, i.y + 1), f.x);
  return mix(a, b, f.y);
}

@compute @workgroup_size(8, 8)
fn csFluid(@builtin(global_invocation_id) gid: vec3u) {
  if (gid.x >= FLUID_SIZE || gid.y >= FLUID_SIZE) {
    return;
  }

  let uv = (vec2f(gid.xy) + 0.5) / f32(FLUID_SIZE);
  let substeps = max(params.uSolverSubsteps.x, 1.0);
  let dt = frame.pointerDelta.z / substeps;
  let texel = 1.0 / f32(FLUID_SIZE);
  let current = fluidCell(i32(gid.x), i32(gid.y));
  let previousUv = uv - current.xy * dt * params.uAdvection.x;
  let advected = sampleFluid(previousUv);

  var velocity = advected.xy * exp(-params.uVelocityDissipation.x * dt);
  var dye = advected.z * exp(-params.uDyeDissipation.x * dt);

  let left = sampleFluid(uv - vec2f(texel, 0.0)).xy;
  let right = sampleFluid(uv + vec2f(texel, 0.0)).xy;
  let down = sampleFluid(uv - vec2f(0.0, texel)).xy;
  let up = sampleFluid(uv + vec2f(0.0, texel)).xy;
  let neighborAverage = (left + right + down + up) * 0.25;
  velocity = mix(velocity, neighborAverage, clamp(params.uViscosity.x * dt * 10.0, 0.0, 0.38));

  let curl = (right.y - left.y) - (up.x - down.x);
  velocity += vec2f(-velocity.y, velocity.x) * curl * params.uVorticity.x * dt * 4.0;

  // Keep the idle gas alive, but avoid the old strong radial expansion that produced spikes.
  let centerDelta = uv - vec2f(0.5);
  let centerRadius = max(length(centerDelta), 0.001);
  let tangent = vec2f(-centerDelta.y, centerDelta.x) / centerRadius;
  let centerFalloff = exp(-centerRadius * 5.0);
  let audioPulse = frame.pointer.w;
  velocity += tangent * centerFalloff * (0.055 + audioPulse * 0.075) * params.uTurbulence.x * dt;
  velocity += normalize(centerDelta + vec2f(0.0001)) * centerFalloff * params.uExpansion.x * 0.010 * dt;
  dye += centerFalloff * (0.016 + audioPulse * 0.018) * dt;

  if (frame.pointer.z > 0.5) {
    let obstacleDelta = uv - frame.pointer.xy;
    let obstacleDistance = length(obstacleDelta);
    let radius = max(params.uMouseRadius.x, 0.008);
    let normal = obstacleDelta / max(obstacleDistance, 0.0001);
    let core = 1.0 - smoothstep(radius * 0.62, radius, obstacleDistance);
    let shell = 1.0 - smoothstep(radius * 0.95, radius * 3.30, obstacleDistance);
    let coupling = clamp(params.uObstacleCoupling.x, 0.0, 1.0);

    let rawObstacleVelocity = frame.pointerDelta.xy / max(frame.pointerDelta.z, 0.001);
    let rawSpeed = length(rawObstacleVelocity);
    let speedScale = min(1.0, 3.2 / max(rawSpeed, 0.001));
    let obstacleVelocity = rawObstacleVelocity * speedScale * params.uMouseForce.x * 0.34;
    let obstacleSpeed = length(obstacleVelocity);

    // No penetration: fluid inside the obstacle follows it, nearby fluid is pushed aside.
    let relativeVelocity = velocity - obstacleVelocity;
    let inward = min(dot(relativeVelocity, normal), 0.0);
    velocity -= normal * inward * shell * coupling;
    velocity = mix(velocity, obstacleVelocity, clamp(core * coupling, 0.0, 1.0));

    // Directional displacement rather than a radial pulse. This is the main solid-pushing term.
    let pushEnvelope = exp(-dot(obstacleDelta, obstacleDelta) / max(radius * radius * 4.8, 0.0001));
    velocity += obstacleVelocity
      * pushEnvelope
      * coupling
      * params.uPushStrength.x
      * dt
      * 7.0;

    if (obstacleSpeed > 0.015) {
      let axis = obstacleVelocity / obstacleSpeed;
      let side = vec2f(-axis.y, axis.x);
      let along = dot(obstacleDelta, axis);
      let across = dot(obstacleDelta, side);

      let bow = smoothstep(-radius * 0.20, radius * 0.75, along)
        * (1.0 - smoothstep(radius * 0.75, radius * 3.30, along))
        * exp(-(across * across) / max(radius * radius * 2.6, 0.0001));
      velocity += axis
        * bow
        * obstacleSpeed
        * params.uObstacleDeflection.x
        * coupling
        * dt
        * 1.8;

      let sideSign = select(-1.0, 1.0, across >= 0.0);
      let shoulder = exp(-abs(along) / max(radius * 1.8, 0.001))
        * exp(-abs(abs(across) - radius * 1.10) / max(radius * 0.75, 0.001));
      velocity += side
        * sideSign
        * shoulder
        * obstacleSpeed
        * params.uObstacleDeflection.x
        * coupling
        * dt
        * 1.35;

      let behind = -along;
      let wakeLong = smoothstep(radius * 0.20, radius * 0.95, behind)
        * (1.0 - smoothstep(radius * 1.0, radius * 6.0, behind));
      let wakeSide = exp(-(across * across) / max(radius * radius * 3.0, 0.0001));
      let shed = sin(
        behind / max(radius, 0.01) * 4.8
        + frame.timeResolution.x * 7.2
        + across / max(radius, 0.01) * 1.8
      );
      velocity += side
        * shed
        * wakeLong
        * wakeSide
        * min(obstacleSpeed, 3.0)
        * params.uWakeStrength.x
        * dt
        * 2.8;
    }

    dye *= 1.0 - core * 0.82;
  }

  let speed = length(velocity);
  if (speed > 2.2) {
    velocity *= 2.2 / speed;
  }

  let index = gid.y * FLUID_SIZE + gid.x;
  fluidOut.cells[index] = vec4f(velocity, clamp(dye, 0.0, 2.0), 0.0);
}

fn hash31(p: vec3f) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + vec3f(33.33));
  return fract((q.x + q.y) * q.z);
}

fn noise3(p: vec3f) -> f32 {
  let i = floor(p);
  var f = fract(p);
  f = f * f * (3.0 - 2.0 * f);

  let n000 = hash31(i + vec3f(0.0, 0.0, 0.0));
  let n100 = hash31(i + vec3f(1.0, 0.0, 0.0));
  let n010 = hash31(i + vec3f(0.0, 1.0, 0.0));
  let n110 = hash31(i + vec3f(1.0, 1.0, 0.0));
  let n001 = hash31(i + vec3f(0.0, 0.0, 1.0));
  let n101 = hash31(i + vec3f(1.0, 0.0, 1.0));
  let n011 = hash31(i + vec3f(0.0, 1.0, 1.0));
  let n111 = hash31(i + vec3f(1.0, 1.0, 1.0));

  let nx00 = mix(n000, n100, f.x);
  let nx10 = mix(n010, n110, f.x);
  let nx01 = mix(n001, n101, f.x);
  let nx11 = mix(n011, n111, f.x);
  return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

fn fbm(pInput: vec3f) -> f32 {
  var p = pInput;
  var sum = 0.0;
  var amplitude = 0.62;
  for (var octave = 0; octave < 2; octave += 1) {
    sum += noise3(p) * amplitude;
    p = p * 2.11 + vec3f(7.1, 13.7, 5.3);
    amplitude *= 0.46;
  }
  return sum;
}

fn densityField(pInput: vec3f, cameraRight: vec3f, cameraUp: vec3f) -> f32 {
  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;

  var p = pInput;
  let initialPlane = vec2f(dot(p, cameraRight), dot(p, cameraUp));
  let initialUv = clamp(initialPlane * 0.42 + vec2f(0.5), vec2f(0.0), vec2f(1.0));
  let fluid = sampleFluid(initialUv);

  // Fluid displacement now bends the body substantially instead of only perturbing fine noise.
  let fluidWarp = fluid.xy * params.uFluidInfluence.x * 0.23;
  p += cameraRight * fluidWarp.x + cameraUp * fluidWarp.y;

  // Immediate solid displacement gives the pointer a tangible push even before the wake develops.
  var obstacleMask = 1.0;
  if (frame.pointer.z > 0.5) {
    let obstacleDelta = initialUv - frame.pointer.xy;
    let obstacleDistance = length(obstacleDelta);
    let obstacleRadius = max(params.uMouseRadius.x, 0.008);
    let obstacleNormal = obstacleDelta / max(obstacleDistance, 0.0001);
    let push = (1.0 - smoothstep(obstacleRadius * 0.70, obstacleRadius * 3.2, obstacleDistance))
      * params.uPushStrength.x
      * params.uObstacleCoupling.x
      * 0.075;
    p += cameraRight * obstacleNormal.x * push + cameraUp * obstacleNormal.y * push;
    obstacleMask = smoothstep(obstacleRadius * 0.58, obstacleRadius * 1.03, obstacleDistance);
  }

  let radius = max(length(p), 0.001);
  let direction = p / radius;
  let detailNoise = fbm(
    p * params.uNoiseScale.x
    + vec3f(time * 0.10, -time * 0.075, time * 0.055)
  );
  let coarseNoise = noise3(direction * 2.1 + vec3f(time * 0.035, -time * 0.028, time * 0.024));

  // Compact cloudy core. Noise only softens it; it no longer creates long radial spikes.
  let coreRadius = 0.39
    + (coarseNoise - 0.5) * 0.085 * params.uIrregularity.x
    + (audio - 0.5) * params.uAudioInfluence.x * 0.018;
  let coreEnvelope = 1.0 - smoothstep(coreRadius - 0.11, coreRadius + 0.13, radius);
  let corePorosity = 0.48 + smoothstep(
    params.uDetailCutoff.x - 0.08,
    params.uDetailCutoff.x + 0.28,
    detailNoise,
  ) * 0.52;
  let coreDensity = coreEnvelope * corePorosity;

  // A small number of broad, curved arms replaces the old high-frequency radial silhouette.
  let planarRadius = length(p.xz);
  let azimuth = atan2(p.z, p.x);
  let armCount = clamp(params.uArmCount.x, 4.0, 8.0);
  let curl = params.uArmCurl.x;
  let drift = time * (0.12 + params.uExpansion.x * 0.12);
  let armPhase = azimuth * armCount
    + planarRadius * (1.7 + curl * 1.15)
    + sin(planarRadius * 5.2 - drift + p.y * 2.2) * curl * 0.52
    + fluid.x * params.uFluidInfluence.x * 1.25;
  let armWave = 0.5 + 0.5 * cos(armPhase);
  let armThreshold = mix(0.48, 0.79, smoothstep(0.28, 0.84, planarRadius));
  let angularArm = smoothstep(armThreshold, 0.985, armWave);

  let armCenterY = sin(
    azimuth * 2.15
    + planarRadius * (4.4 + curl * 0.9)
    - drift * 2.1
  ) * 0.10 * curl
    + fluid.y * params.uFluidInfluence.x * 0.055;
  let verticalArm = 1.0 - smoothstep(0.13, 0.27, abs(p.y - armCenterY));

  let lengthVariation = 0.035 * sin(azimuth * 3.0 + 0.8)
    + 0.025 * sin(azimuth * 5.0 - 1.6);
  let armEnd = clamp(params.uArmLength.x + lengthVariation, 0.42, 0.90);
  let radialStart = smoothstep(0.26, 0.38, planarRadius);
  let radialEnd = 1.0 - smoothstep(armEnd - 0.13, armEnd + 0.09, planarRadius);
  let armBody = angularArm * verticalArm * radialStart * radialEnd;

  // Arms stay thick and smoky instead of tapering to needle tips.
  let armTexture = 0.56 + 0.44 * smoothstep(
    params.uDetailCutoff.x - 0.12,
    params.uDetailCutoff.x + 0.30,
    detailNoise + fluid.z * 0.08,
  );
  let tentacleDensity = armBody * armTexture * 0.82;

  let fluidCompression = 1.0 + clamp(fluid.z, 0.0, 1.5) * 0.10;
  let density = (coreDensity * 0.78 + tentacleDensity)
    * fluidCompression
    * obstacleMask;

  return max(0.0, density * params.uDensity.x);
}

fn intersectSphere(ro: vec3f, rd: vec3f, radius: f32) -> vec2f {
  let b = dot(ro, rd);
  let c = dot(ro, ro) - radius * radius;
  let h = b * b - c;
  if (h < 0.0) {
    return vec2f(1e6, -1e6);
  }
  let root = sqrt(h);
  return vec2f(-b - root, -b + root);
}

fn waveform(x: f32, time: f32) -> f32 {
  return sin(x * 31.0 + time * 5.2) * 0.46
    + sin(x * 57.0 - time * 8.1 + 1.7) * 0.25
    + sin(x * 13.0 + time * 2.4) * 0.18;
}

@fragment
fn fsMain(in: VertexOut) -> @location(0) vec4f {
  let resolution = frame.timeResolution.yz;
  let aspect = frame.timeResolution.w;
  let screen = vec2f((in.uv.x * 2.0 - 1.0) * aspect, in.uv.y * 2.0 - 1.0);
  let time = frame.timeResolution.x;

  let degreesToRadians = 0.017453292519943295;
  let yaw = (params.uCameraYaw.x + time * params.uCameraOrbitSpeed.x) * degreesToRadians;
  let pitch = clamp(params.uCameraPitch.x, -85.0, 85.0) * degreesToRadians;
  let cameraDistance = max(params.uCameraDistance.x, 1.35);
  let cosPitch = cos(pitch);
  let ro = vec3f(
    sin(yaw) * cosPitch,
    sin(pitch),
    cos(yaw) * cosPitch,
  ) * cameraDistance;
  let forward = normalize(-ro);
  let cameraRight = normalize(cross(forward, vec3f(0.0, 1.0, 0.0)));
  let cameraUp = normalize(cross(cameraRight, forward));
  let fovRadians = clamp(params.uCameraFov.x, 20.0, 100.0) * degreesToRadians;
  let focalLength = 1.0 / tan(fovRadians * 0.5);
  let rd = normalize(forward * focalLength + cameraRight * screen.x + cameraUp * screen.y);

  // Tighter bounds keep the visual compact and reduce empty raymarch work.
  let hit = intersectSphere(ro, rd, 1.02);
  var background = mix(vec3f(0.008, 0.012, 0.020), vec3f(0.035, 0.055, 0.080), in.uv.y);
  let vignette = 1.0 - 0.24 * dot(screen * 0.48, screen * 0.48);
  background *= max(vignette, 0.55);

  var color = background;
  if (hit.y > max(hit.x, 0.0)) {
    let steps = clamp(i32(params.uSteps.x), 28, 144);
    let startT = max(hit.x, 0.0);
    let travelDistance = hit.y - startT;
    let stepLength = travelDistance / f32(steps);
    let jitter = (hash31(vec3f(in.position.xy, fract(time))) - 0.5) * stepLength * params.uJitter.x;
    var t = startT + jitter;
    var transmittance = 1.0;
    var scattering = vec3f(0.0);
    let lightDir = normalize(vec3f(-0.55, 0.72, 0.42));
    let gasColor = params.uGasColor.xyz;

    for (var i = 0; i < 144; i += 1) {
      if (i >= steps) { break; }
      let p = ro + rd * t;
      let density = densityField(p, cameraRight, cameraUp);
      if (density > 0.004) {
        let outward = normalize(p + vec3f(0.0001));
        let directional = clamp(dot(outward, lightDir) * 0.5 + 0.5, 0.0, 1.0);
        let localShadow = exp(-density * params.uShadow.x * 0.42);
        let light = 0.29 + 0.71 * directional * localShadow;
        let rim = pow(1.0 - abs(dot(outward, -rd)), 2.1);
        let sampleColor = gasColor * (
          light
          + rim * 0.22
          + frame.pointer.w * params.uAudioInfluence.x * 0.035
        );
        let alpha = 1.0 - exp(-density * params.uAbsorption.x * stepLength);
        scattering += transmittance * alpha * sampleColor;
        transmittance *= 1.0 - alpha;
        if (transmittance < 0.025) { break; }
      }
      t += stepLength;
    }
    color = scattering + background * transmittance;
  }

  let waveX = in.uv.x * 2.0 - 1.0;
  let wave = -0.79 + waveform(waveX, time) * (0.025 + frame.pointer.w * 0.018) * params.uAudioInfluence.x;
  let lineDistance = abs(screen.y - wave);
  let line = exp(-lineDistance * max(resolution.y, 1.0) * 0.42);
  let baseline = exp(-abs(screen.y + 0.79) * max(resolution.y, 1.0) * 0.16) * 0.16;
  color += params.uWaveColor.xyz * (line * 0.78 + baseline);

  color = color / (color + vec3f(1.0));
  color = pow(max(color, vec3f(0.0)), vec3f(1.0 / 2.2));
  return vec4f(color, 1.0);
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uCameraYaw": {
      "type": "float", "default": 0.0, "min": -180.0, "max": 180.0, "step": 1.0,
      "label": { "zh": "相机水平角", "en": "Camera Yaw" },
      "description": { "zh": "围绕气体中心进行水平轨道旋转。", "en": "Horizontal orbit angle around the gas center." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraPitch": {
      "type": "float", "default": 0.0, "min": -80.0, "max": 80.0, "step": 1.0,
      "label": { "zh": "相机俯仰角", "en": "Camera Pitch" },
      "description": { "zh": "控制相机上下观察角度。", "en": "Controls the vertical camera orbit angle." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraDistance": {
      "type": "float", "default": 3.1, "min": 1.5, "max": 6.0, "step": 0.02,
      "label": { "zh": "相机距离", "en": "Camera Distance" },
      "description": { "zh": "控制相机到气体中心的距离。", "en": "Distance from the camera to the gas center." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraFov": {
      "type": "float", "default": 48.0, "min": 20.0, "max": 100.0, "step": 1.0,
      "label": { "zh": "相机视野", "en": "Camera FOV" },
      "description": { "zh": "垂直视野角度。", "en": "Vertical field of view in degrees." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraOrbitSpeed": {
      "type": "float", "default": 0.0, "min": -30.0, "max": 30.0, "step": 0.1,
      "label": { "zh": "自动环绕速度", "en": "Auto Orbit Speed" },
      "description": { "zh": "每秒自动增加的水平角度；设为 0 关闭自动环绕。", "en": "Yaw degrees added per second; set to 0 to disable auto orbit." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uDensity": {
      "type": "float", "default": 0.78, "min": 0.1, "max": 3.0, "step": 0.01,
      "label": { "zh": "气体密度", "en": "Gas Density" },
      "description": { "zh": "整体缩放体积密度；默认更轻，保留内部层次。", "en": "Scales volume density; the lighter default preserves internal depth." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uAbsorption": {
      "type": "float", "default": 1.85, "min": 0.2, "max": 8.0, "step": 0.01,
      "label": { "zh": "吸收", "en": "Absorption" },
      "description": { "zh": "Beer-Lambert 吸收强度。", "en": "Beer-Lambert absorption strength." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uSteps": {
      "type": "int", "default": 72, "min": 28, "max": 144, "step": 1,
      "label": { "zh": "光线步数", "en": "Ray Steps" },
      "description": { "zh": "体积 raymarch 采样步数。", "en": "Volume ray-marching sample count." },
      "group": { "zh": "采样", "en": "Sampling" }
    },
    "uJitter": {
      "type": "float", "default": 0.82, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "采样抖动", "en": "Jitter" },
      "description": { "zh": "减弱低步数下的固定采样带状伪影。", "en": "Reduces fixed-step banding at lower sample counts." },
      "group": { "zh": "采样", "en": "Sampling" }
    },
    "uNoiseScale": {
      "type": "float", "default": 2.45, "min": 0.8, "max": 6.0, "step": 0.01,
      "label": { "zh": "烟雾细节尺度", "en": "Smoke Detail Scale" },
      "description": { "zh": "控制内部翻滚纹理，不直接拉长外轮廓。", "en": "Controls internal rolling texture without stretching the silhouette." },
      "group": { "zh": "形态", "en": "Shape" }
    },
    "uTurbulence": {
      "type": "float", "default": 1.10, "min": 0.0, "max": 2.8, "step": 0.01,
      "label": { "zh": "翻涌扰动", "en": "Turbulence" },
      "description": { "zh": "控制中心流动与涡旋活跃度。", "en": "Controls central flow and vortical activity." },
      "group": { "zh": "形态", "en": "Shape" }
    },
    "uIrregularity": {
      "type": "float", "default": 0.65, "min": 0.0, "max": 2.0, "step": 0.01,
      "label": { "zh": "核心不规则度", "en": "Core Irregularity" },
      "description": { "zh": "只扰动核心柔和轮廓，不再生成放射尖刺。", "en": "Perturbs the soft core only and no longer creates radial spikes." },
      "group": { "zh": "形态", "en": "Shape" }
    },
    "uExpansion": {
      "type": "float", "default": 0.22, "min": 0.0, "max": 2.0, "step": 0.01,
      "label": { "zh": "整体漂移", "en": "Overall Drift" },
      "description": { "zh": "控制轻微的向外漂移和触手相位运动；默认不再持续膨胀。", "en": "Controls subtle outward drift and arm phase motion; the default no longer continuously inflates." },
      "group": { "zh": "形态", "en": "Shape" }
    },
    "uDetailCutoff": {
      "type": "float", "default": 0.48, "min": 0.20, "max": 0.78, "step": 0.01,
      "label": { "zh": "内部疏松度", "en": "Internal Porosity" },
      "description": { "zh": "提高后内部更稀疏，但不会把触手侵蚀成尖线。", "en": "Higher values make the interior sparser without eroding arms into needles." },
      "group": { "zh": "形态", "en": "Shape" }
    },
    "uArmCount": {
      "type": "int", "default": 6, "min": 4, "max": 8, "step": 1,
      "label": { "zh": "触手数量", "en": "Arm Count" },
      "description": { "zh": "控制围绕核心形成的粗大卷臂数量。", "en": "Number of broad curling arms around the core." },
      "group": { "zh": "触手形态", "en": "Tentacle Shape" }
    },
    "uArmLength": {
      "type": "float", "default": 0.64, "min": 0.40, "max": 0.90, "step": 0.01,
      "label": { "zh": "触手长度", "en": "Arm Length" },
      "description": { "zh": "控制触手平均伸展范围；默认保持整体紧凑。", "en": "Average arm reach; the default keeps the body compact." },
      "group": { "zh": "触手形态", "en": "Tentacle Shape" }
    },
    "uArmCurl": {
      "type": "float", "default": 1.15, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "触手卷曲", "en": "Arm Curl" },
      "description": { "zh": "控制触手弯曲和摆动程度。", "en": "Controls arm curvature and undulation." },
      "group": { "zh": "触手形态", "en": "Tentacle Shape" }
    },
    "uFluidInfluence": {
      "type": "float", "default": 1.90, "min": 0.0, "max": 3.5, "step": 0.01,
      "label": { "zh": "流体弯折", "en": "Fluid Bending" },
      "description": { "zh": "二维速度场对三维核心和触手形变的影响；默认明显增强。", "en": "How strongly the 2D velocity field bends the 3D core and arms; raised by default." },
      "group": { "zh": "流体解算", "en": "Fluid Solver" }
    },
    "uAdvection": {
      "type": "float", "default": 1.10, "min": 0.1, "max": 2.0, "step": 0.01,
      "label": { "zh": "平流速度", "en": "Advection" },
      "description": { "zh": "半拉格朗日平流回溯距离。", "en": "Backtrace distance for semi-Lagrangian advection." },
      "group": { "zh": "流体解算", "en": "Fluid Solver" }
    },
    "uViscosity": {
      "type": "float", "default": 0.12, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "粘性", "en": "Viscosity" },
      "description": { "zh": "控制速度场邻域扩散；默认降低以保留局部推动痕迹。", "en": "Controls velocity diffusion; lowered by default to retain local pushes." },
      "group": { "zh": "流体解算", "en": "Fluid Solver" }
    },
    "uVorticity": {
      "type": "float", "default": 1.35, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "涡量保持", "en": "Vorticity" },
      "description": { "zh": "增强固体后方和触手之间的旋涡结构。", "en": "Preserves vortices behind the solid and between arms." },
      "group": { "zh": "流体解算", "en": "Fluid Solver" }
    },
    "uVelocityDissipation": {
      "type": "float", "default": 0.22, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "速度耗散", "en": "Velocity Dissipation" },
      "description": { "zh": "速度随时间衰减速度；默认降低以产生更明显的尾随与回弹。", "en": "Velocity decay rate; lowered so pushes leave a clearer trailing response." },
      "group": { "zh": "流体解算", "en": "Fluid Solver" }
    },
    "uDyeDissipation": {
      "type": "float", "default": 0.25, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "密度耗散", "en": "Density Dissipation" },
      "description": { "zh": "二维辅助密度场随时间消散速度。", "en": "Rate at which the auxiliary 2D density field fades." },
      "group": { "zh": "流体解算", "en": "Fluid Solver" }
    },
    "uSolverSubsteps": {
      "type": "int", "default": 2, "min": 1, "max": 4, "step": 1,
      "label": { "zh": "解算子步", "en": "Solver Substeps" },
      "description": { "zh": "每帧流体子步数；默认 2 以增强移动固体与尾涡的稳定性。", "en": "Fluid substeps per frame; defaults to 2 for more stable obstacle wakes." },
      "group": { "zh": "流体解算", "en": "Fluid Solver" }
    },
    "uMouseRadius": {
      "type": "float", "default": 0.095, "min": 0.02, "max": 0.22, "step": 0.001,
      "label": { "zh": "固体半径", "en": "Obstacle Radius" },
      "description": { "zh": "按住鼠标时固体障碍物半径。", "en": "Radius of the solid obstacle while the pointer is held." },
      "group": { "zh": "固体交互", "en": "Solid Interaction" }
    },
    "uMouseForce": {
      "type": "float", "default": 5.0, "min": 0.0, "max": 12.0, "step": 0.1,
      "label": { "zh": "固体移动速度", "en": "Obstacle Motion" },
      "description": { "zh": "鼠标拖动速度传递给流体的倍率。", "en": "Multiplier for pointer motion transferred to the fluid." },
      "group": { "zh": "固体交互", "en": "Solid Interaction" }
    },
    "uObstacleCoupling": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "固体耦合", "en": "Obstacle Coupling" },
      "description": { "zh": "控制无穿透边界和固体速度约束。", "en": "Strength of no-penetration and obstacle velocity coupling." },
      "group": { "zh": "固体交互", "en": "Solid Interaction" }
    },
    "uPushStrength": {
      "type": "float", "default": 1.65, "min": 0.0, "max": 3.5, "step": 0.01,
      "label": { "zh": "直接推动", "en": "Direct Push" },
      "description": { "zh": "控制固体对附近触手的即时位移与定向推动，是交互手感的主要参数。", "en": "Immediate directional displacement applied to nearby arms; the main interaction feel control." },
      "group": { "zh": "固体交互", "en": "Solid Interaction" }
    },
    "uObstacleDeflection": {
      "type": "float", "default": 2.05, "min": 0.0, "max": 3.5, "step": 0.01,
      "label": { "zh": "绕流偏转", "en": "Flow Deflection" },
      "description": { "zh": "增强流体沿移动固体两侧绕开的趋势。", "en": "Strengthens flow diversion around the moving solid." },
      "group": { "zh": "固体交互", "en": "Solid Interaction" }
    },
    "uWakeStrength": {
      "type": "float", "default": 1.55, "min": 0.0, "max": 3.5, "step": 0.01,
      "label": { "zh": "尾涡强度", "en": "Wake Strength" },
      "description": { "zh": "控制移动固体后方交替脱落的尾涡。", "en": "Controls alternating wake shedding behind the moving solid." },
      "group": { "zh": "固体交互", "en": "Solid Interaction" }
    },
    "uAudioInfluence": {
      "type": "float", "default": 0.75, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "音频联动", "en": "Audio Influence" },
      "description": { "zh": "合成音频包络对核心呼吸、流动和波形的影响。", "en": "Influence of the synthetic audio envelope on core breathing, flow, and waveform." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uShadow": {
      "type": "float", "default": 1.05, "min": 0.0, "max": 4.0, "step": 0.01,
      "label": { "zh": "局部阴影", "en": "Local Shadow" },
      "description": { "zh": "控制低成本局部密度阴影。", "en": "Controls low-cost local-density shadowing." },
      "group": { "zh": "光照", "en": "Lighting" }
    },
    "uGasColor": {
      "type": "color", "default": "#78a6c7",
      "label": { "zh": "气体颜色", "en": "Gas Color" },
      "description": { "zh": "体积散射颜色。", "en": "Volumetric scattering color." },
      "group": { "zh": "外观", "en": "Appearance" }
    },
    "uWaveColor": {
      "type": "color", "default": "#55d8ff",
      "label": { "zh": "波形颜色", "en": "Wave Color" },
      "description": { "zh": "底部音频波动曲线颜色。", "en": "Color of the audio waveform drawn at the bottom." },
      "group": { "zh": "外观", "en": "Appearance" }
    },
    "uUncappedBenchmark": {
      "type": "boolean", "default": false,
      "label": { "zh": "取消帧率限制", "en": "Uncapped Benchmark" },
      "description": { "zh": "关闭显示刷新率同步，用于测试 GPU 极限吞吐；开启时可能显著增加功耗。", "en": "Bypasses display synchronization to benchmark GPU throughput; this can substantially increase power use." },
      "group": { "zh": "性能", "en": "Performance" }
    }
  }
}
@endshaderlab */