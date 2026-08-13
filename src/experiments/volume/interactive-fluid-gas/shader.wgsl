struct VertexOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
};

struct Flow3D {
  velocity: vec3f,
  displacement: vec3f,
};

struct VolumeSample {
  density: f32,
  detail: f32,
  activity: f32,
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

fn rotate2(v: vec2f, a: f32) -> vec2f {
  let c = cos(a);
  let s = sin(a);
  return vec2f(c * v.x + s * v.y, -s * v.x + c * v.y);
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

fn hash31(p: vec3f) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + vec3f(33.33));
  return fract((q.x + q.y) * q.z);
}

fn branchBand2(p: vec2f, dir: vec2f, phase: f32, width: f32) -> f32 {
  let sideAxis = vec2f(-dir.y, dir.x);
  let along = dot(p, dir);
  let side = dot(p, sideAxis)
    + sin(along * 13.0 + phase) * 0.030
    + sin(along * 29.0 - phase * 1.23) * 0.012
    + sin(along * 53.0 + phase * 0.47) * 0.005;
  let ridge = exp(-abs(side) / max(width, 0.004));
  let window = smoothstep(-0.035, 0.035, along)
    * (1.0 - smoothstep(0.30, 0.60, along));
  return ridge * window;
}

fn impulsePattern2(p: vec2f, seed: f32, complexity: f32, sharpness: f32) -> f32 {
  let a = seed * 6.28318530718;
  let d0 = vec2f(cos(a), sin(a));
  let d1 = vec2f(cos(a + 1.83), sin(a + 1.83));
  let d2 = vec2f(cos(a - 2.31), sin(a - 2.31));
  let d3 = vec2f(cos(a + 3.77), sin(a + 3.77));
  let width = mix(0.052, 0.017, clamp(sharpness / 7.0, 0.0, 1.0));
  let trunks = max(
    branchBand2(p, d0, seed * 7.9, width),
    max(
      branchBand2(p, d1, seed * 11.3 + 1.2, width * 0.84) * 0.92,
      max(
        branchBand2(p, d2, seed * 16.7 - 2.1, width * 0.72) * 0.82,
        branchBand2(p, d3, seed * 20.1 + 0.6, width * 0.62) * 0.70,
      ),
    ),
  );

  var q = p * (8.5 + complexity * 0.72);
  var ridge = 0.0;
  var amplitude = 0.55;
  var frequency = 1.0;
  for (var i = 0; i < 3; i += 1) {
    let wave = abs(
      sin(q.y * frequency + seed * 4.7)
        + cos(q.x * frequency - seed * 3.2)
    ) * 0.5;
    ridge += pow(max(0.0, 1.0 - wave), 1.35 + sharpness * 0.18) * amplitude;
    q = rotate2(q, 0.61 + seed * 0.13 + f32(i) * 0.19);
    frequency *= 1.79;
    amplitude *= 0.48;
  }
  return clamp(max(trunks, ridge * 0.48), 0.0, 1.25);
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
  let advection = params.uAdvection.x;

  let current = fluidCell(i32(gid.x), i32(gid.y));
  let midpointUv = uv - current.xy * dt * advection * 0.5;
  let midpoint = sampleFluid(midpointUv);
  let previousUv = uv - midpoint.xy * dt * advection;
  let advected = sampleFluid(previousUv);

  var velocity = advected.xy;
  var displacement = advected.zw;

  let leftState = sampleFluid(uv - vec2f(texel, 0.0));
  let rightState = sampleFluid(uv + vec2f(texel, 0.0));
  let downState = sampleFluid(uv - vec2f(0.0, texel));
  let upState = sampleFluid(uv + vec2f(0.0, texel));

  velocity = mix(
    velocity,
    (leftState.xy + rightState.xy + downState.xy + upState.xy) * 0.25,
    clamp(params.uViscosity.x * dt * 5.5, 0.0, 0.20),
  );

  let curl = (rightState.y - leftState.y) - (upState.x - downState.x);
  velocity += vec2f(-velocity.y, velocity.x)
    * curl
    * params.uVorticity.x
    * dt
    * 2.7;

  let displacementLaplacian = leftState.zw
    + rightState.zw
    + downState.zw
    + upState.zw
    - displacement * 4.0;
  displacement -= displacementLaplacian
    * clamp(params.uFlowSharpen.x * dt, 0.0, 0.055);

  let centerDelta = uv - vec2f(0.5);
  let centerRadius = max(length(centerDelta), 0.001);
  let radial = centerDelta / centerRadius;
  let centerFalloff = exp(-centerRadius * 6.0);
  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;

  let idleCurl = vec2f(
    sin(uv.y * 12.7 + time * 0.83) + sin((uv.x + uv.y) * 18.3 - time * 0.47) * 0.37,
    cos(uv.x * 11.9 - time * 0.71) - cos((uv.x - uv.y) * 17.1 + time * 0.52) * 0.34,
  );
  velocity += idleCurl
    * centerFalloff
    * params.uCoreWobble.x
    * dt
    * (0.055 + audio * params.uAudioInfluence.x * 0.008);

  let injection = frame.pointer.z;
  if (injection > 0.0005) {
    let seed = frame.pointerDelta.w;
    let pattern = impulsePattern2(
      centerDelta,
      seed,
      clamp(params.uFractalBranches.x, 3.0, 10.0),
      clamp(params.uBranchSharpness.x, 1.0, 7.0),
    );
    let targetVector = frame.pointerDelta.xy - vec2f(0.5);
    let targetDirection = targetVector / max(length(targetVector), 0.001);
    let directionBias = 0.32
      + 0.68 * smoothstep(-0.78, 0.92, dot(radial, targetDirection));
    let reach = max(params.uBurstReach.x, 0.25);
    let radialEnvelope = exp(-pow(centerRadius / reach, 2.0) * 3.2);
    let source = injection * radialEnvelope * directionBias * pattern;

    let shear = vec2f(-targetDirection.y, targetDirection.x)
      * sin(dot(centerDelta, vec2f(-targetDirection.y, targetDirection.x)) * 37.0 + seed * 19.0);
    let pushDirection = normalize(
      radial * 0.56
        + targetDirection * 0.34
        + shear * 0.24
        + vec2f(0.0001),
    );
    let impulse = pushDirection
      * source
      * params.uBurstForce.x
      * dt
      * 16.0;
    velocity += impulse;
    displacement += impulse * dt * params.uMaterialResponse.x * 0.55;
  }

  let burstPhase = frame.burstState.x;
  let burstStrength = clamp(frame.burstState.w, 0.0, 2.0);
  let springRamp = mix(
    1.0,
    mix(0.34, 1.08, smoothstep(0.16, 0.78, burstPhase)),
    clamp(burstStrength, 0.0, 1.0),
  );
  velocity -= displacement
    * params.uElasticity.x
    * springRamp
    * dt
    * 8.2;
  velocity *= exp(-params.uElasticDamping.x * dt);
  velocity *= exp(-params.uVelocityDissipation.x * dt);

  displacement += velocity * dt * params.uMaterialResponse.x;

  let speed = length(velocity);
  if (speed > 3.4) {
    velocity *= 3.4 / speed;
  }
  let maxDisplacement = max(params.uMaxDisplacement.x, 0.05);
  let displacementLength = length(displacement);
  if (displacementLength > maxDisplacement) {
    displacement *= maxDisplacement / displacementLength;
  }

  let index = gid.y * FLUID_SIZE + gid.x;
  fluidOut.cells[index] = vec4f(velocity, displacement);
}

fn rotateVolume(pInput: vec3f, time: f32) -> vec3f {
  var p = pInput;
  let xz = rotate2(vec2f(p.x, p.z), time * 0.12 + 0.19);
  p = vec3f(xz.x, p.y, xz.y);
  let yz = rotate2(vec2f(p.y, p.z), -time * 0.08 + 0.37);
  return vec3f(p.x, yz.x, yz.y);
}

fn crawlWarp(p: vec3f, time: f32, amount: f32) -> vec3f {
  let w = vec3f(
    sin(p.y * 4.1 + p.z * 2.2 + time * 0.77),
    sin(p.z * 3.5 - p.x * 2.7 - time * 0.69 + 1.7),
    sin(p.x * 3.7 + p.y * 2.9 + time * 0.62 + 3.1),
  );
  let w2 = vec3f(
    sin(p.z * 8.3 - time * 1.03),
    cos(p.x * 7.7 + time * 0.91),
    sin(p.y * 9.1 + time * 0.79),
  );
  return p + (w * 0.72 + w2 * 0.28) * amount;
}

fn spiralRidged3(pInput: vec3f, phase: f32) -> f32 {
  var p = pInput;
  var sum = 0.0;
  var amplitude = 0.53;
  var frequency = 1.0;
  for (var i = 0; i < 4; i += 1) {
    let wave = abs(
      sin(p.y * frequency + phase * 0.73)
        + cos(p.x * frequency - phase * 0.51)
    ) * 0.5;
    sum += max(0.0, 1.0 - wave) * amplitude;
    let xy = rotate2(vec2f(p.x, p.y), 0.64 + f32(i) * 0.07);
    p = vec3f(xy.x, xy.y, p.z);
    let xz = rotate2(vec2f(p.x, p.z), -0.51 + f32(i) * 0.05);
    p = vec3f(xz.x, p.y, xz.y);
    frequency *= 1.73;
    amplitude *= 0.49;
  }
  return clamp(sum / 0.99, 0.0, 1.0);
}

fn spiralFlow3(pInput: vec3f, phase: f32) -> f32 {
  var p = pInput;
  var sum = 0.0;
  var amplitude = 0.59;
  var frequency = 1.0;
  for (var i = 0; i < 3; i += 1) {
    let wave = (
      sin(p.y * frequency + phase * 0.63)
        + cos(p.x * frequency - phase * 0.47)
    ) * 0.5;
    sum += wave * amplitude;
    let xz = rotate2(vec2f(p.x, p.z), 0.57 + f32(i) * 0.11);
    p = vec3f(xz.x, p.y, xz.y);
    let yz = rotate2(vec2f(p.y, p.z), -0.43 + f32(i) * 0.08);
    p = vec3f(p.x, yz.x, yz.y);
    frequency *= 1.56;
    amplitude *= 0.48;
  }
  return 0.5 + 0.5 * clamp(sum / 1.02, -1.0, 1.0);
}

fn fineMaterialNoise(p: vec3f, time: f32) -> f32 {
  return clamp(
    0.5
      + (
        sin(p.x * 19.1 + p.y * 4.3 + time * 0.31)
          + sin(p.y * 25.7 - p.z * 3.9 - time * 0.27)
          + sin(p.z * 31.3 + p.x * 5.1 + time * 0.23)
      ) / 6.0,
    0.0,
    1.0,
  );
}

fn sampleFlowWorld(p: vec3f) -> Flow3D {
  let weightsRaw = abs(p) + vec3f(0.24);
  let weights = weightsRaw / max(dot(weightsRaw, vec3f(1.0)), 0.001);
  let xy = sampleFluid(p.xy * 0.44 + vec2f(0.5));
  let yz = sampleFluid(p.yz * 0.44 + vec2f(0.5));
  let zx = sampleFluid(vec2f(p.z, p.x) * 0.44 + vec2f(0.5));

  var result: Flow3D;
  result.velocity = vec3f(xy.x, xy.y, 0.0) * weights.z
    + vec3f(0.0, yz.x, yz.y) * weights.x
    + vec3f(zx.y, 0.0, zx.x) * weights.y;
  result.displacement = vec3f(xy.z, xy.w, 0.0) * weights.z
    + vec3f(0.0, yz.z, yz.w) * weights.x
    + vec3f(zx.w, 0.0, zx.z) * weights.y;
  return result;
}

fn densityField(pWorld: vec3f) -> VolumeSample {
  var out: VolumeSample;
  out.density = 0.0;
  out.detail = 0.0;
  out.activity = 0.0;

  if (length(pWorld) > 1.28) {
    return out;
  }

  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;
  let flow = sampleFlowWorld(pWorld);
  let deformation = params.uFluidInfluence.x;
  let materialPosition = pWorld - flow.displacement * deformation;
  let displacementAmount = length(flow.displacement) * deformation;

  let crawled = crawlWarp(
    materialPosition,
    time,
    params.uCoreWobble.x * 0.34,
  );
  let radius = max(length(crawled), 0.001);
  let direction = crawled / radius;
  let q = rotateVolume(crawled, time * (0.15 + params.uTurbulence.x * 0.035));
  let coarse = spiralFlow3(
    q * 1.75 + vec3f(0.37, -0.21, 0.13),
    time * (0.18 + params.uTurbulence.x * 0.055),
  );
  let detail = spiralRidged3(
    q * params.uNoiseScale.x,
    time * (0.28 + params.uTurbulence.x * 0.075),
  );
  let fine = fineMaterialNoise(q * (1.0 + params.uNoiseScale.x * 0.17), time);

  let directionalLobe = (
    sin(direction.x * 3.7 + time * 0.23)
      + sin(direction.y * 4.5 - time * 0.19)
      + sin(direction.z * 5.3 + time * 0.17 + 1.4)
  ) / 3.0;
  let breathing = sin(time * 1.37) * params.uExpansion.x * 0.009
    + (audio - 0.5) * params.uAudioInfluence.x * 0.009;
  let coreRadius = params.uCoreRadius.x
    + breathing
    + (coarse - 0.5) * params.uCoreWobble.x * 1.42
    + directionalLobe * params.uCoreWobble.x * 0.48;
  let surfaceWarp = (detail - 0.5) * params.uCoreDetailStrength.x * 0.105
    + (fine - 0.5) * params.uCoreDetailStrength.x * 0.040;
  let coreEnvelope = 1.0 - smoothstep(
    coreRadius - 0.055,
    coreRadius + 0.062,
    radius - surfaceWarp,
  );

  let porous = smoothstep(
    params.uDetailCutoff.x - 0.20,
    params.uDetailCutoff.x + 0.16,
    detail * 0.72 + fine * 0.28,
  );

  let strain = smoothstep(
    params.uTearThreshold.x,
    params.uTearThreshold.x + 0.18,
    displacementAmount,
  );
  let fractureNoise = smoothstep(
    0.38,
    0.73,
    fine * 0.58 + detail * 0.42,
  );
  let tearing = strain
    * (1.0 - fractureNoise)
    * params.uStrainTearing.x;
  let centerEvacuation = strain
    * (1.0 - smoothstep(0.16, 0.52, radius))
    * params.uStrainTearing.x
    * 0.68;

  let stretchedRidges = pow(
    max(0.0, 1.0 - abs(sin(
      q.x * 29.0
        + q.y * 17.0
        - q.z * 13.0
        + dot(flow.displacement, vec3f(11.0, -7.0, 9.0))
    ))),
    2.6,
  );
  let microStructure = mix(
    1.0,
    0.50 + stretchedRidges * 0.78,
    strain * params.uFineStretchDetail.x,
  );

  let baseDensity = coreEnvelope
    * (0.08 + porous * 0.92)
    * microStructure;
  let densityAfterTear = baseDensity
    * max(0.0, 1.0 - tearing - centerEvacuation);

  out.density = max(0.0, densityAfterTear * params.uDensity.x);
  out.detail = clamp(
    detail * 0.52
      + fine * 0.23
      + stretchedRidges * strain * 0.35,
    0.0,
    1.0,
  );
  out.activity = clamp(strain + length(flow.velocity) * 0.16, 0.0, 1.0);
  return out;
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
  let yaw = (params.uCameraYaw.x + time * params.uCameraOrbitSpeed.x) * degreesToRadians;
  let pitch = clamp(params.uCameraPitch.x, -82.0, 82.0) * degreesToRadians;
  let cameraDistance = clamp(params.uCameraDistance.x, 1.45, 6.0);
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

  let hit = intersectSphere(ro, rd, 1.30);
  var background = mix(
    vec3f(0.007, 0.010, 0.017),
    vec3f(0.030, 0.047, 0.070),
    in.uv.y,
  );
  let vignette = 1.0 - 0.22 * dot(screen * 0.48, screen * 0.48);
  background *= max(vignette, 0.58);

  var color = background;
  if (hit.y > max(hit.x, 0.0)) {
    let steps = clamp(i32(params.uSteps.x), 40, 160);
    let startT = max(hit.x, 0.0);
    let travelDistance = hit.y - startT;
    let stepLength = travelDistance / f32(steps);
    let jitter = (hash31(vec3f(in.position.xy, fract(time))) - 0.5)
      * stepLength
      * params.uJitter.x;

    var t = startT + jitter;
    var transmittance = 1.0;
    var scattering = vec3f(0.0);
    let lightDir = normalize(vec3f(-0.52, 0.71, 0.47));
    let gasColor = params.uGasColor.xyz;

    for (var i = 0; i < 160; i += 1) {
      if (i >= steps) {
        break;
      }
      let p = ro + rd * t;
      if (length(p) < 1.28) {
        let volumeSample = densityField(p);
        if (volumeSample.density > 0.0015) {
          let q = crawlWarp(
            rotateVolume(p, time * 0.11),
            time,
            params.uCoreWobble.x * 0.10,
          );
          let normalPerturbation = vec3f(
            sin(q.y * 9.3 + time * 0.43),
            sin(q.z * 10.1 - time * 0.39),
            sin(q.x * 9.7 + time * 0.35 + 1.2),
          ) * params.uCoreDetailStrength.x * 0.075;
          let outward = normalize(p + normalPerturbation + vec3f(0.0001));
          let directional = clamp(dot(outward, lightDir) * 0.5 + 0.5, 0.0, 1.0);
          let localShadow = exp(-volumeSample.density * params.uShadow.x * 0.25);
          let detailLight = 0.67 + volumeSample.detail * 0.52;
          let light = (0.15 + 0.85 * directional * localShadow) * detailLight;
          let rim = pow(1.0 - abs(dot(outward, -rd)), 2.45);
          let sampleColor = gasColor * (
            light
              + rim * (0.11 + volumeSample.activity * 0.18)
              + volumeSample.detail * volumeSample.activity * 0.075
          );
          let alpha = 1.0 - exp(-volumeSample.density * params.uAbsorption.x * stepLength);
          scattering += transmittance * alpha * sampleColor;
          transmittance *= 1.0 - alpha;
          if (transmittance < 0.016) {
            break;
          }
        }
      }
      t += stepLength;
    }
    color = scattering + background * transmittance;
  }

  let audioRunning = 1.0 - params.uAudioPaused.x;
  let waveX = in.uv.x * 2.0 - 1.0;
  let wave = -0.79
    + waveform(waveX, time)
      * (0.020 + frame.pointer.w * 0.015)
      * params.uAudioInfluence.x
      * audioRunning;
  let lineDistance = abs(screen.y - wave);
  let line = exp(-lineDistance * max(resolution.y, 1.0) * 0.42);
  let baseline = exp(-abs(screen.y + 0.79) * max(resolution.y, 1.0) * 0.16) * 0.10;
  color += params.uWaveColor.xyz * (line * 0.68 + baseline);

  color = color / (color + vec3f(1.0));
  color = pow(max(color, vec3f(0.0)), vec3f(1.0 / 2.2));
  return vec4f(color, 1.0);
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uCameraYaw": { "type": "float", "default": 18.0, "min": -180.0, "max": 180.0, "step": 1.0, "label": { "zh": "相机水平角", "en": "Camera Yaw" }, "group": { "zh": "相机", "en": "Camera" } },
    "uCameraPitch": { "type": "float", "default": 8.0, "min": -80.0, "max": 80.0, "step": 1.0, "label": { "zh": "相机俯仰角", "en": "Camera Pitch" }, "group": { "zh": "相机", "en": "Camera" } },
    "uCameraDistance": { "type": "float", "default": 3.15, "min": 1.5, "max": 6.0, "step": 0.02, "label": { "zh": "相机距离", "en": "Camera Distance" }, "group": { "zh": "相机", "en": "Camera" } },
    "uCameraFov": { "type": "float", "default": 46.0, "min": 20.0, "max": 100.0, "step": 1.0, "label": { "zh": "相机视野", "en": "Camera FOV" }, "group": { "zh": "相机", "en": "Camera" } },
    "uCameraOrbitSpeed": { "type": "float", "default": 0.0, "min": -30.0, "max": 30.0, "step": 0.1, "label": { "zh": "自动环绕速度", "en": "Auto Orbit Speed" }, "group": { "zh": "相机", "en": "Camera" } },

    "uDensity": { "type": "float", "default": 0.78, "min": 0.1, "max": 3.0, "step": 0.01, "label": { "zh": "气体密度", "en": "Gas Density" }, "group": { "zh": "体积", "en": "Volume" } },
    "uAbsorption": { "type": "float", "default": 1.22, "min": 0.2, "max": 8.0, "step": 0.01, "label": { "zh": "吸收", "en": "Absorption" }, "group": { "zh": "体积", "en": "Volume" } },

    "uCoreRadius": { "type": "float", "default": 0.40, "min": 0.25, "max": 0.65, "step": 0.005, "label": { "zh": "核心半径", "en": "Core Radius" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uCoreWobble": { "type": "float", "default": 0.17, "min": 0.0, "max": 0.34, "step": 0.005, "label": { "zh": "核心蠕动", "en": "Core Wobble" }, "description": { "zh": "同时驱动核心的三维材质形变和二维低频流场。", "en": "Drives both 3D material deformation and low-frequency 2D flow in the idle core." }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uCoreDetailStrength": { "type": "float", "default": 1.28, "min": 0.0, "max": 2.4, "step": 0.01, "label": { "zh": "表面细节", "en": "Surface Detail" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uNoiseScale": { "type": "float", "default": 4.6, "min": 1.0, "max": 9.0, "step": 0.02, "label": { "zh": "材质分形尺度", "en": "Material Fractal Scale" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uDetailCutoff": { "type": "float", "default": 0.57, "min": 0.18, "max": 0.84, "step": 0.01, "label": { "zh": "内部疏松度", "en": "Internal Porosity" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uTurbulence": { "type": "float", "default": 1.05, "min": 0.0, "max": 2.8, "step": 0.01, "label": { "zh": "翻涌速度", "en": "Rolling Speed" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uExpansion": { "type": "float", "default": 0.10, "min": 0.0, "max": 1.5, "step": 0.01, "label": { "zh": "呼吸扩张", "en": "Breathing Expansion" }, "group": { "zh": "核心形态", "en": "Core Shape" } },

    "uFluidInfluence": { "type": "float", "default": 1.65, "min": 0.0, "max": 3.5, "step": 0.01, "label": { "zh": "材质流形变", "en": "Material Flow Deformation" }, "description": { "zh": "将二维 displacement 三平面重建为三维材质坐标位移；爆裂和回收始终查询同一核心密度。", "en": "Reconstructs 2D displacement into 3D material-coordinate motion; burst and return always sample the same core density." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uMaterialResponse": { "type": "float", "default": 1.15, "min": 0.2, "max": 2.5, "step": 0.01, "label": { "zh": "材质惯性", "en": "Material Response" }, "description": { "zh": "控制速度积累为材质位移的速度。", "en": "Controls how quickly velocity accumulates into material displacement." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uElasticity": { "type": "float", "default": 1.18, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "弹性恢复", "en": "Elastic Restoration" }, "description": { "zh": "真实作用于 displacement 的恢复力，而不是形状 alpha 混合。", "en": "A restoring force applied directly to displacement instead of alpha blending shapes." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uElasticDamping": { "type": "float", "default": 1.05, "min": 0.0, "max": 4.0, "step": 0.01, "label": { "zh": "弹性阻尼", "en": "Elastic Damping" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uMaxDisplacement": { "type": "float", "default": 0.52, "min": 0.10, "max": 0.90, "step": 0.01, "label": { "zh": "最大位移", "en": "Max Displacement" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uFlowSharpen": { "type": "float", "default": 0.34, "min": 0.0, "max": 1.5, "step": 0.01, "label": { "zh": "流场锐化", "en": "Flow Sharpening" }, "description": { "zh": "轻量反扩散修正，减弱半拉格朗日平流造成的位移模糊。", "en": "A light anti-diffusion correction that reduces displacement blur from semi-Lagrangian advection." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uTearThreshold": { "type": "float", "default": 0.10, "min": 0.02, "max": 0.45, "step": 0.005, "label": { "zh": "拉伸撕裂阈值", "en": "Stretch Tear Threshold" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uStrainTearing": { "type": "float", "default": 0.92, "min": 0.0, "max": 1.8, "step": 0.01, "label": { "zh": "拉伸撕裂", "en": "Strain Tearing" }, "description": { "zh": "高位移区域从同一材质中产生孔洞和断裂，不额外叠加第二套爆裂形状。", "en": "Creates holes and breakup from highly displaced material without adding a second burst shape." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uFineStretchDetail": { "type": "float", "default": 0.82, "min": 0.0, "max": 1.5, "step": 0.01, "label": { "zh": "拉丝细节", "en": "Stretch Filament Detail" }, "group": { "zh": "材质流", "en": "Material Flow" } },

    "uAdvection": { "type": "float", "default": 1.10, "min": 0.1, "max": 2.0, "step": 0.01, "label": { "zh": "平流速度", "en": "Advection" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uViscosity": { "type": "float", "default": 0.055, "min": 0.0, "max": 1.0, "step": 0.005, "label": { "zh": "粘性", "en": "Viscosity" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uVorticity": { "type": "float", "default": 1.35, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "涡量保持", "en": "Vorticity" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uVelocityDissipation": { "type": "float", "default": 0.34, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "速度耗散", "en": "Velocity Dissipation" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uSolverSubsteps": { "type": "int", "default": 2, "min": 1, "max": 4, "step": 1, "label": { "zh": "解算子步", "en": "Solver Substeps" }, "group": { "zh": "二维解算", "en": "2D Solver" } },

    "uClickBurstStrength": { "type": "float", "default": 1.35, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "点击冲击强度", "en": "Click Impact Strength" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uBurstDuration": { "type": "float", "default": 1.75, "min": 0.45, "max": 4.0, "step": 0.01, "label": { "zh": "恢复周期", "en": "Recovery Window" }, "description": { "zh": "只用于控制冲击阶段和自动节拍节流；形状恢复由弹性位移解算完成。", "en": "Controls impact timing and beat throttling only; shape recovery comes from the elastic displacement solver." }, "group": { "zh": "冲击", "en": "Impact" } },
    "uBurstForce": { "type": "float", "default": 2.85, "min": 0.0, "max": 5.0, "step": 0.01, "label": { "zh": "冲击推力", "en": "Impact Force" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uFractalBranches": { "type": "float", "default": 7.2, "min": 3.0, "max": 10.0, "step": 0.1, "label": { "zh": "冲击分形复杂度", "en": "Impact Fractal Complexity" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uBranchSharpness": { "type": "float", "default": 4.1, "min": 1.0, "max": 7.0, "step": 0.1, "label": { "zh": "冲击分支锐度", "en": "Impact Branch Sharpness" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uBurstReach": { "type": "float", "default": 0.46, "min": 0.20, "max": 0.80, "step": 0.01, "label": { "zh": "冲击作用范围", "en": "Impact Reach" }, "group": { "zh": "冲击", "en": "Impact" } },

    "uAudioPaused": { "type": "boolean", "default": false, "label": { "zh": "暂停音乐", "en": "Pause Audio" }, "description": { "zh": "暂停音频驱动、自动节拍冲击和波形运动；鼠标点击仍有效。", "en": "Pauses audio drive, automatic beat impacts, and waveform motion; pointer impacts remain active." }, "group": { "zh": "音频", "en": "Audio" } },
    "uAudioBurstEnabled": { "type": "boolean", "default": true, "label": { "zh": "音频触发冲击", "en": "Audio Impact Trigger" }, "group": { "zh": "音频", "en": "Audio" } },
    "uAudioBurstStrength": { "type": "float", "default": 0.82, "min": 0.0, "max": 2.5, "step": 0.01, "label": { "zh": "音频冲击强度", "en": "Audio Impact Strength" }, "group": { "zh": "音频", "en": "Audio" } },
    "uBeatThreshold": { "type": "float", "default": 0.72, "min": 0.45, "max": 0.95, "step": 0.01, "label": { "zh": "节拍阈值", "en": "Beat Threshold" }, "group": { "zh": "音频", "en": "Audio" } },
    "uBeatCooldown": { "type": "float", "default": 1.15, "min": 0.2, "max": 3.0, "step": 0.01, "label": { "zh": "节拍冷却", "en": "Beat Cooldown" }, "group": { "zh": "音频", "en": "Audio" } },
    "uAudioInfluence": { "type": "float", "default": 0.56, "min": 0.0, "max": 2.5, "step": 0.01, "label": { "zh": "音频呼吸", "en": "Audio Breathing" }, "group": { "zh": "音频", "en": "Audio" } },

    "uSteps": { "type": "int", "default": 92, "min": 40, "max": 160, "step": 1, "label": { "zh": "光线步数", "en": "Ray Steps" }, "group": { "zh": "采样", "en": "Sampling" } },
    "uJitter": { "type": "float", "default": 0.18, "min": 0.0, "max": 1.0, "step": 0.01, "label": { "zh": "采样抖动", "en": "Jitter" }, "group": { "zh": "采样", "en": "Sampling" } },
    "uShadow": { "type": "float", "default": 1.22, "min": 0.0, "max": 4.0, "step": 0.01, "label": { "zh": "局部阴影", "en": "Local Shadow" }, "group": { "zh": "光照", "en": "Lighting" } },
    "uGasColor": { "type": "color", "default": "#789dd0", "label": { "zh": "气体颜色", "en": "Gas Color" }, "group": { "zh": "外观", "en": "Appearance" } },
    "uWaveColor": { "type": "color", "default": "#55d8ff", "label": { "zh": "波形颜色", "en": "Wave Color" }, "group": { "zh": "外观", "en": "Appearance" } },
    "uUncappedBenchmark": { "type": "boolean", "default": false, "label": { "zh": "取消帧率限制", "en": "Uncapped Benchmark" }, "group": { "zh": "性能", "en": "Performance" } }
  }
}
@endshaderlab */