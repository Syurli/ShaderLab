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
  var burstField = advected.w * exp(-params.uBurstFieldDissipation.x * dt);

  let left = sampleFluid(uv - vec2f(texel, 0.0)).xy;
  let right = sampleFluid(uv + vec2f(texel, 0.0)).xy;
  let down = sampleFluid(uv - vec2f(0.0, texel)).xy;
  let up = sampleFluid(uv + vec2f(0.0, texel)).xy;
  let neighborAverage = (left + right + down + up) * 0.25;
  velocity = mix(
    velocity,
    neighborAverage,
    clamp(params.uViscosity.x * dt * 9.0, 0.0, 0.34),
  );

  // Cheap vorticity retention. The 2D grid carries velocity.xy, smoke.z and burst memory.w.
  let curl = (right.y - left.y) - (up.x - down.x);
  velocity += vec2f(-velocity.y, velocity.x)
    * curl
    * params.uVorticity.x
    * dt
    * 3.6;

  let centerDelta = uv - vec2f(0.5);
  let centerRadius = max(length(centerDelta), 0.001);
  let radial = centerDelta / centerRadius;
  let tangent = vec2f(-radial.y, radial.x);
  let centerFalloff = exp(-centerRadius * 6.0);
  let audio = frame.pointer.w;

  // Idle state: weak circulation and restoring motion keep the core alive without inflating it.
  let idlePulse = 0.5 + 0.5 * sin(frame.timeResolution.x * 1.37 + centerRadius * 13.0);
  velocity += tangent
    * centerFalloff
    * (0.025 + audio * 0.032)
    * params.uTurbulence.x
    * dt;
  velocity -= centerDelta
    * centerFalloff
    * (0.020 + idlePulse * 0.010)
    * dt;
  velocity += radial
    * centerFalloff
    * params.uExpansion.x
    * sin(frame.timeResolution.x * 1.11 + centerRadius * 15.0)
    * dt
    * 0.008;
  dye += centerFalloff * (0.010 + audio * 0.008) * dt;

  // Event-driven explosion. pointer.z is a short CPU-side impulse envelope.
  let burstAmplitude = frame.pointer.z;
  if (burstAmplitude > 0.0005) {
    let seed = frame.pointerDelta.w * 6.28318530718;
    let angle = atan2(centerDelta.y, centerDelta.x);
    let branches = clamp(params.uFractalBranches.x, 3.0, 10.0);
    let sharpness = clamp(params.uBranchSharpness.x, 1.0, 7.0);

    let phaseA = angle * branches
      + sin(angle * 2.73 - seed * 1.37) * 1.18
      + seed;
    let phaseB = angle * (branches * 0.63 + 2.0)
      - sin(angle * 4.11 + seed * 0.71) * 0.92
      - seed * 1.71;
    let phaseC = angle * (branches * 1.37 + 1.0)
      + sin(angle * 1.91 - seed * 2.13) * 0.73
      + seed * 0.43;

    let ridgeA = pow(0.5 + 0.5 * cos(phaseA), sharpness);
    let ridgeB = pow(0.5 + 0.5 * cos(phaseB), sharpness * 0.82);
    let ridgeC = pow(0.5 + 0.5 * cos(phaseC), sharpness * 0.68);
    let fractalRidge = max(ridgeA, max(ridgeB * 0.78, ridgeC * 0.55));

    let targetVector = frame.pointerDelta.xy - vec2f(0.5);
    let targetDirection = targetVector / max(length(targetVector), 0.001);
    let directionBias = 0.58
      + 0.42 * smoothstep(-0.65, 0.80, dot(radial, targetDirection));

    let radialEnvelope = exp(-centerRadius * 2.35);
    let branchSource = burstAmplitude
      * radialEnvelope
      * directionBias
      * (0.20 + fractalRidge * 1.45);

    velocity += radial
      * branchSource
      * params.uBurstForce.x
      * dt
      * 12.5;
    velocity += tangent
      * sin(phaseB + centerRadius * 17.0)
      * branchSource
      * params.uBurstForce.x
      * dt
      * 3.6;

    let coreBlast = exp(
      -dot(centerDelta, centerDelta) / 0.022
    );
    velocity += radial
      * coreBlast
      * burstAmplitude
      * params.uBurstForce.x
      * dt
      * 5.0;

    dye += branchSource * params.uBurstDensity.x * dt * 2.8;
    burstField += branchSource * dt * 7.5;
  }

  let speed = length(velocity);
  if (speed > 2.75) {
    velocity *= 2.75 / speed;
  }

  let index = gid.y * FLUID_SIZE + gid.x;
  fluidOut.cells[index] = vec4f(
    velocity,
    clamp(dye, 0.0, 2.0),
    clamp(burstField, 0.0, 2.5),
  );
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
    p = p * 2.13 + vec3f(7.1, 13.7, 5.3);
    amplitude *= 0.46;
  }
  return sum;
}

fn densityField(pInput: vec3f, cameraRight: vec3f, cameraUp: vec3f) -> f32 {
  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;
  let cameraForward = normalize(cross(cameraRight, cameraUp));

  var p = pInput;
  let initialPlane = vec2f(dot(p, cameraRight), dot(p, cameraUp));
  let initialUv = clamp(initialPlane * 0.48 + vec2f(0.5), vec2f(0.0), vec2f(1.0));
  let fluid = sampleFluid(initialUv);
  let burstLocal = clamp(
    fluid.w * params.uBurstVisualStrength.x + frame.pointer.z * 0.32,
    0.0,
    1.65,
  );

  // The 2D solver bends the 3D density. Burst areas receive much stronger displacement.
  let fluidWarpScale = params.uFluidInfluence.x * (0.075 + burstLocal * 0.145);
  let fluidWarp = fluid.xy * fluidWarpScale;
  p += cameraRight * fluidWarp.x + cameraUp * fluidWarp.y;

  let radius = max(length(p), 0.001);
  let direction = p / radius;
  let detailNoise = fbm(
    p * params.uNoiseScale.x
      + vec3f(time * 0.095, -time * 0.071, time * 0.052)
  );
  let fineNoise = noise3(
    p * params.uNoiseScale.x * 3.05
      + vec3f(-time * 0.14, time * 0.11, time * 0.08)
  );
  let coarseNoise = noise3(
    direction * 2.0 + vec3f(time * 0.031, -time * 0.026, time * 0.022)
  );

  // Idle state: a complete, finely rolling volumetric sphere.
  let coreRadius = params.uCoreRadius.x
    + (coarseNoise - 0.5) * params.uCoreWobble.x
    + (audio - 0.5) * params.uAudioInfluence.x * 0.010;
  let surfaceWarp = (detailNoise - 0.48) * 0.040
    + (fineNoise - 0.5) * 0.014;
  let coreEnvelope = 1.0 - smoothstep(
    coreRadius - 0.085,
    coreRadius + 0.105,
    radius - surfaceWarp,
  );
  let corePorosity = 0.54 + 0.46 * smoothstep(
    params.uDetailCutoff.x - 0.14,
    params.uDetailCutoff.x + 0.30,
    detailNoise + fineNoise * 0.12,
  );

  let plane = vec2f(dot(p, cameraRight), dot(p, cameraUp));
  let planeRadius = max(length(plane), 0.001);
  let angle = atan2(plane.y, plane.x);
  let seed = frame.pointerDelta.w * 6.28318530718;
  let branchCount = clamp(params.uFractalBranches.x, 3.0, 10.0);
  let sharpness = clamp(params.uBranchSharpness.x, 1.0, 7.0);

  // Curled ridged multifractal coordinates. Radius-dependent phase prevents straight spikes.
  let curlAngle = angle
    + planeRadius * (4.0 + burstLocal * 1.2)
    + sin(planeRadius * 11.0 - time * 2.2 + seed) * 0.38
    + fluid.x * params.uFluidInfluence.x * 0.60;
  let branchA = pow(
    0.5 + 0.5 * cos(
      curlAngle * branchCount
        + sin(curlAngle * 2.37 + seed * 1.31) * 1.15
        + seed
    ),
    sharpness,
  );
  let branchB = pow(
    0.5 + 0.5 * cos(
      curlAngle * (branchCount * 0.61 + 2.0)
        - planeRadius * 7.4
        + sin(curlAngle * 3.11 - seed) * 0.82
        - seed * 1.73
    ),
    sharpness * 0.82,
  );
  let branchC = pow(
    0.5 + 0.5 * cos(
      curlAngle * (branchCount * 1.29 + 1.0)
        + planeRadius * 4.1
        + seed * 0.47
    ),
    sharpness * 0.68,
  );
  let fractureRidge = max(branchA, max(branchB * 0.78, branchC * 0.55));

  // During a burst the same branching field tears holes through the otherwise complete core.
  let fractureCut = clamp(
    burstLocal
      * fractureRidge
      * params.uCoreBreakup.x,
    0.0,
    0.92,
  );
  let globalOpening = clamp(frame.pointer.z * params.uCoreBreakup.x * 0.18, 0.0, 0.30);
  let coreDensity = coreEnvelope
    * corePorosity
    * (1.0 - fractureCut * 0.82)
    * (1.0 - globalOpening);

  // Short-lived exploded structures: broad folded sheets plus branching smoke filaments.
  let depth = dot(p, cameraForward);
  let foldA = sin(
    curlAngle * 1.73
      + planeRadius * 8.4
      - time * 2.4
      + seed
  ) * 0.115
    + (detailNoise - 0.5) * 0.065
    + fluid.y * params.uFluidInfluence.x * 0.040;
  let foldB = cos(
    curlAngle * 2.21
      - planeRadius * 6.7
      + time * 1.7
      - seed * 1.4
  ) * 0.135
    + (fineNoise - 0.5) * 0.045;

  let sheetA = 1.0 - smoothstep(0.075, 0.255, abs(depth - foldA));
  let sheetB = 1.0 - smoothstep(0.080, 0.285, abs(depth - foldB));
  let radialStart = smoothstep(
    params.uCoreRadius.x * 0.72,
    params.uCoreRadius.x * 0.98,
    planeRadius,
  );
  let radialEnd = 1.0 - smoothstep(0.73, 1.01, planeRadius);
  let radialWindow = radialStart * radialEnd;
  let lacyDetail = 0.40 + 0.60 * smoothstep(
    params.uDetailCutoff.x - 0.12,
    params.uDetailCutoff.x + 0.28,
    detailNoise
      + fineNoise * 0.15
      + fluid.z * 0.08
      + fractureRidge * 0.12,
  );

  let foldedFractal = max(
    branchA * sheetA,
    max(branchB * sheetB * 0.82, branchC * max(sheetA, sheetB) * 0.52),
  );
  let explodedDensity = burstLocal
    * radialWindow
    * foldedFractal
    * lacyDetail
    * 1.18;

  // Advected smoke fills some gaps so the explosion reads as volume rather than geometry.
  let smokeTrail = clamp(fluid.z, 0.0, 1.5)
    * burstLocal
    * radialWindow
    * (1.0 - smoothstep(0.18, 0.48, abs(depth)))
    * (0.10 + detailNoise * 0.12);

  let density = coreDensity * 0.90
    + explodedDensity
    + smokeTrail;
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
  let screen = vec2f(
    (in.uv.x * 2.0 - 1.0) * aspect,
    in.uv.y * 2.0 - 1.0,
  );
  let time = frame.timeResolution.x;

  let degreesToRadians = 0.017453292519943295;
  let yaw = (
    params.uCameraYaw.x + time * params.uCameraOrbitSpeed.x
  ) * degreesToRadians;
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
  let rd = normalize(
    forward * focalLength
      + cameraRight * screen.x
      + cameraUp * screen.y
  );

  // A compact bound still leaves room for the transient exploded structures.
  let hit = intersectSphere(ro, rd, 1.08);
  var background = mix(
    vec3f(0.008, 0.012, 0.020),
    vec3f(0.035, 0.055, 0.080),
    in.uv.y,
  );
  let vignette = 1.0 - 0.24 * dot(screen * 0.48, screen * 0.48);
  background *= max(vignette, 0.55);

  var color = background;
  if (hit.y > max(hit.x, 0.0)) {
    let steps = clamp(i32(params.uSteps.x), 28, 136);
    let startT = max(hit.x, 0.0);
    let travelDistance = hit.y - startT;
    let stepLength = travelDistance / f32(steps);
    let jitter = (
      hash31(vec3f(in.position.xy, fract(time))) - 0.5
    ) * stepLength * params.uJitter.x;

    var t = startT + jitter;
    var transmittance = 1.0;
    var scattering = vec3f(0.0);
    let lightDir = normalize(vec3f(-0.48, 0.76, 0.43));
    let gasColor = params.uGasColor.xyz;

    for (var i = 0; i < 136; i += 1) {
      if (i >= steps) {
        break;
      }

      let p = ro + rd * t;
      let density = densityField(p, cameraRight, cameraUp);
      if (density > 0.0035) {
        let outward = normalize(p + vec3f(0.0001));
        let directional = clamp(
          dot(outward, lightDir) * 0.5 + 0.5,
          0.0,
          1.0,
        );
        let localShadow = exp(-density * params.uShadow.x * 0.40);
        let light = 0.24 + 0.76 * directional * localShadow;
        let rim = pow(1.0 - abs(dot(outward, -rd)), 2.0);
        let burstGlow = clamp(frame.pointer.z + frame.pointer.w * 0.16, 0.0, 1.2);
        let sampleColor = gasColor * (
          light
            + rim * (0.22 + burstGlow * 0.10)
            + burstGlow * 0.035
        );

        let alpha = 1.0 - exp(
          -density * params.uAbsorption.x * stepLength
        );
        scattering += transmittance * alpha * sampleColor;
        transmittance *= 1.0 - alpha;

        if (transmittance < 0.025) {
          break;
        }
      }

      t += stepLength;
    }

    color = scattering + background * transmittance;
  }

  let waveX = in.uv.x * 2.0 - 1.0;
  let wave = -0.79
    + waveform(waveX, time)
      * (0.022 + frame.pointer.w * 0.017)
      * params.uAudioInfluence.x;
  let lineDistance = abs(screen.y - wave);
  let line = exp(-lineDistance * max(resolution.y, 1.0) * 0.42);
  let baseline = exp(
    -abs(screen.y + 0.79) * max(resolution.y, 1.0) * 0.16
  ) * 0.14;
  color += params.uWaveColor.xyz * (line * 0.72 + baseline);

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
      "description": { "zh": "围绕核心水平旋转相机。", "en": "Horizontal orbit around the core." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraPitch": {
      "type": "float", "default": 0.0, "min": -80.0, "max": 80.0, "step": 1.0,
      "label": { "zh": "相机俯仰角", "en": "Camera Pitch" },
      "description": { "zh": "控制上下观察角度。", "en": "Vertical orbit angle." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraDistance": {
      "type": "float", "default": 3.15, "min": 1.5, "max": 6.0, "step": 0.02,
      "label": { "zh": "相机距离", "en": "Camera Distance" },
      "description": { "zh": "相机到体积核心的距离。", "en": "Distance from camera to volume core." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraFov": {
      "type": "float", "default": 47.0, "min": 20.0, "max": 100.0, "step": 1.0,
      "label": { "zh": "相机视野", "en": "Camera FOV" },
      "description": { "zh": "垂直视野角。", "en": "Vertical field of view." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraOrbitSpeed": {
      "type": "float", "default": 0.0, "min": -30.0, "max": 30.0, "step": 0.1,
      "label": { "zh": "自动环绕速度", "en": "Auto Orbit Speed" },
      "description": { "zh": "设为 0 关闭自动环绕。", "en": "Set to 0 to disable automatic orbit." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uDensity": {
      "type": "float", "default": 0.76, "min": 0.1, "max": 3.0, "step": 0.01,
      "label": { "zh": "气体密度", "en": "Gas Density" },
      "description": { "zh": "整体体积密度，默认保留较多透光层次。", "en": "Overall volume density; the default preserves translucency." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uAbsorption": {
      "type": "float", "default": 1.92, "min": 0.2, "max": 8.0, "step": 0.01,
      "label": { "zh": "吸收", "en": "Absorption" },
      "description": { "zh": "Beer-Lambert 吸收强度。", "en": "Beer-Lambert absorption strength." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uSteps": {
      "type": "int", "default": 68, "min": 28, "max": 136, "step": 1,
      "label": { "zh": "光线步数", "en": "Ray Steps" },
      "description": { "zh": "体积 raymarch 采样数量。", "en": "Volume ray-marching sample count." },
      "group": { "zh": "采样", "en": "Sampling" }
    },
    "uJitter": {
      "type": "float", "default": 0.78, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "采样抖动", "en": "Jitter" },
      "description": { "zh": "减弱低步数带状伪影。", "en": "Reduces banding at lower sample counts." },
      "group": { "zh": "采样", "en": "Sampling" }
    },
    "uCoreRadius": {
      "type": "float", "default": 0.43, "min": 0.28, "max": 0.62, "step": 0.005,
      "label": { "zh": "核心半径", "en": "Core Radius" },
      "description": { "zh": "平静状态下完整蠕动球体的平均半径。", "en": "Average radius of the intact idle core." },
      "group": { "zh": "核心烟雾", "en": "Core Smoke" }
    },
    "uCoreWobble": {
      "type": "float", "default": 0.055, "min": 0.0, "max": 0.18, "step": 0.002,
      "label": { "zh": "核心蠕动", "en": "Core Wobble" },
      "description": { "zh": "控制球体表面的低频细腻蠕动，不生成长尖刺。", "en": "Low-frequency surface motion without long spikes." },
      "group": { "zh": "核心烟雾", "en": "Core Smoke" }
    },
    "uNoiseScale": {
      "type": "float", "default": 3.15, "min": 1.0, "max": 7.0, "step": 0.01,
      "label": { "zh": "细节尺度", "en": "Detail Scale" },
      "description": { "zh": "控制核心内部与爆裂结构的细节频率。", "en": "Detail frequency inside the core and burst structures." },
      "group": { "zh": "核心烟雾", "en": "Core Smoke" }
    },
    "uDetailCutoff": {
      "type": "float", "default": 0.42, "min": 0.20, "max": 0.72, "step": 0.01,
      "label": { "zh": "内部疏松度", "en": "Internal Porosity" },
      "description": { "zh": "提高后核心和爆裂结构更稀疏。", "en": "Higher values make the volume more porous." },
      "group": { "zh": "核心烟雾", "en": "Core Smoke" }
    },
    "uTurbulence": {
      "type": "float", "default": 0.72, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "平静翻涌", "en": "Idle Turbulence" },
      "description": { "zh": "平静状态下二维流场的轻微旋转活性。", "en": "Subtle 2D circulation while idle." },
      "group": { "zh": "核心烟雾", "en": "Core Smoke" }
    },
    "uExpansion": {
      "type": "float", "default": 0.16, "min": 0.0, "max": 1.5, "step": 0.01,
      "label": { "zh": "呼吸漂移", "en": "Breathing Drift" },
      "description": { "zh": "核心很弱的呼吸式径向漂移，不持续膨胀。", "en": "Very weak breathing-like radial drift without continuous inflation." },
      "group": { "zh": "核心烟雾", "en": "Core Smoke" }
    },
    "uClickBurstStrength": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "点击爆裂强度", "en": "Click Burst Strength" },
      "description": { "zh": "鼠标按下沿触发一次爆裂的总强度。", "en": "Overall strength of a single burst triggered on pointer-down." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstDuration": {
      "type": "float", "default": 0.78, "min": 0.15, "max": 2.0, "step": 0.01,
      "label": { "zh": "爆裂注入时长", "en": "Burst Injection Duration" },
      "description": { "zh": "一次爆裂向二维解算持续注入力的时间。", "en": "Duration of force injection for one burst event." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstForce": {
      "type": "float", "default": 1.55, "min": 0.0, "max": 3.5, "step": 0.01,
      "label": { "zh": "爆炸推力", "en": "Burst Force" },
      "description": { "zh": "分叉速度脉冲把核心瞬间撕开的力度。", "en": "Strength of the branching velocity impulse that tears the core open." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstDensity": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "爆裂烟量", "en": "Burst Smoke" },
      "description": { "zh": "爆裂分支注入到二维烟雾场的量。", "en": "Smoke injected into the 2D field along burst branches." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uFractalBranches": {
      "type": "float", "default": 6.0, "min": 3.0, "max": 10.0, "step": 0.1,
      "label": { "zh": "分形主分支", "en": "Fractal Branches" },
      "description": { "zh": "控制爆裂时主要分叉数量；多尺度相位会继续产生次级枝杈。", "en": "Primary branch count; multi-scale phases add secondary branches." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBranchSharpness": {
      "type": "float", "default": 3.0, "min": 1.0, "max": 7.0, "step": 0.05,
      "label": { "zh": "分支锐度", "en": "Branch Sharpness" },
      "description": { "zh": "控制分叉结构宽度；过高会重新变成尖刺。", "en": "Controls branch width; very high values can become spike-like." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uCoreBreakup": {
      "type": "float", "default": 1.22, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "核心撕裂", "en": "Core Breakup" },
      "description": { "zh": "爆裂分形场穿透并撕开核心密度的程度。", "en": "How strongly the burst fractal tears holes through the core." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstVisualStrength": {
      "type": "float", "default": 1.35, "min": 0.0, "max": 2.8, "step": 0.01,
      "label": { "zh": "爆裂结构强度", "en": "Burst Structure Strength" },
      "description": { "zh": "二维爆裂激励场对三维卷曲薄片和烟丝的影响。", "en": "Influence of the 2D burst field on 3D folded sheets and filaments." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uFluidInfluence": {
      "type": "float", "default": 1.45, "min": 0.0, "max": 3.5, "step": 0.01,
      "label": { "zh": "流场形变", "en": "Fluid Deformation" },
      "description": { "zh": "二维速度场弯折三维密度的强度；爆裂区域自动增强。", "en": "2D velocity deformation of the 3D density, automatically stronger during bursts." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uAdvection": {
      "type": "float", "default": 1.15, "min": 0.1, "max": 2.0, "step": 0.01,
      "label": { "zh": "平流速度", "en": "Advection" },
      "description": { "zh": "半拉格朗日回溯距离。", "en": "Semi-Lagrangian backtrace distance." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uViscosity": {
      "type": "float", "default": 0.08, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "粘性", "en": "Viscosity" },
      "description": { "zh": "速度邻域扩散；默认较低以保留爆裂细节。", "en": "Velocity diffusion; kept low to preserve burst detail." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uVorticity": {
      "type": "float", "default": 1.40, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "涡量保持", "en": "Vorticity" },
      "description": { "zh": "保持爆裂后的卷曲和回流结构。", "en": "Preserves curling and recirculation after a burst." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uVelocityDissipation": {
      "type": "float", "default": 0.34, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "速度耗散", "en": "Velocity Dissipation" },
      "description": { "zh": "控制爆裂后流场回落速度。", "en": "Controls how quickly velocity settles after a burst." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uDyeDissipation": {
      "type": "float", "default": 0.62, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "烟雾耗散", "en": "Smoke Dissipation" },
      "description": { "zh": "二维辅助烟雾场消散速度。", "en": "Dissipation rate of the auxiliary smoke field." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uBurstFieldDissipation": {
      "type": "float", "default": 1.05, "min": 0.1, "max": 4.0, "step": 0.01,
      "label": { "zh": "爆裂记忆耗散", "en": "Burst Memory Dissipation" },
      "description": { "zh": "分形爆裂结构在流场中保留的时间；越高恢复越快。", "en": "How quickly the advected burst structure fades and the core recovers." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uSolverSubsteps": {
      "type": "int", "default": 2, "min": 1, "max": 4, "step": 1,
      "label": { "zh": "解算子步", "en": "Solver Substeps" },
      "description": { "zh": "每帧二维 ping-pong 解算次数。", "en": "2D ping-pong solver iterations per rendered frame." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uAudioBurstEnabled": {
      "type": "boolean", "default": true,
      "label": { "zh": "音频触发爆裂", "en": "Audio Burst Trigger" },
      "description": { "zh": "当前示例使用合成音频包络，越过节拍阈值时随机触发爆裂。", "en": "The demo uses a synthetic audio envelope and triggers randomized bursts on threshold crossings." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uAudioBurstStrength": {
      "type": "float", "default": 0.72, "min": 0.0, "max": 2.0, "step": 0.01,
      "label": { "zh": "音频爆裂强度", "en": "Audio Burst Strength" },
      "description": { "zh": "节拍自动触发的爆裂力度。", "en": "Strength of beat-triggered bursts." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uBeatThreshold": {
      "type": "float", "default": 0.69, "min": 0.45, "max": 0.90, "step": 0.01,
      "label": { "zh": "节拍阈值", "en": "Beat Threshold" },
      "description": { "zh": "合成音频包络向上越过该值时触发。", "en": "A rising crossing of this envelope value triggers a burst." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uBeatCooldown": {
      "type": "float", "default": 0.72, "min": 0.2, "max": 2.5, "step": 0.01,
      "label": { "zh": "节拍冷却", "en": "Beat Cooldown" },
      "description": { "zh": "自动爆裂之间的最短间隔。", "en": "Minimum interval between automatic bursts." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uAudioInfluence": {
      "type": "float", "default": 0.55, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "音频呼吸联动", "en": "Audio Breathing" },
      "description": { "zh": "非爆裂时音频对核心呼吸和底部波形的影响。", "en": "Audio influence on idle breathing and the waveform." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uShadow": {
      "type": "float", "default": 1.05, "min": 0.0, "max": 4.0, "step": 0.01,
      "label": { "zh": "局部阴影", "en": "Local Shadow" },
      "description": { "zh": "低成本局部密度阴影。", "en": "Low-cost local-density shadowing." },
      "group": { "zh": "光照", "en": "Lighting" }
    },
    "uGasColor": {
      "type": "color", "default": "#637fd2",
      "label": { "zh": "气体颜色", "en": "Gas Color" },
      "description": { "zh": "体积散射颜色。", "en": "Volumetric scattering color." },
      "group": { "zh": "外观", "en": "Appearance" }
    },
    "uWaveColor": {
      "type": "color", "default": "#55d8ff",
      "label": { "zh": "波形颜色", "en": "Wave Color" },
      "description": { "zh": "底部音频曲线颜色。", "en": "Color of the audio waveform." },
      "group": { "zh": "外观", "en": "Appearance" }
    },
    "uUncappedBenchmark": {
      "type": "boolean", "default": false,
      "label": { "zh": "取消帧率限制", "en": "Uncapped Benchmark" },
      "description": { "zh": "关闭显示同步，用于测试 GPU 极限吞吐；会增加功耗。", "en": "Bypasses display synchronization for GPU-throughput benchmarking; increases power use." },
      "group": { "zh": "性能", "en": "Performance" }
    }
  }
}
@endshaderlab */
