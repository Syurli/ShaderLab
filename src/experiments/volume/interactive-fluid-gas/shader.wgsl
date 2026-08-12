struct VertexOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
};

struct Fluid3D {
  velocity: vec3f,
  dye: f32,
  burst: f32,
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

fn sampleFluidNearest(uvInput: vec2f) -> vec4f {
  let uv = clamp(uvInput, vec2f(0.0), vec2f(1.0));
  let p = uv * f32(FLUID_SIZE - 1u);
  let i = vec2i(floor(p + vec2f(0.5)));
  return fluidCell(i.x, i.y);
}

fn branchBand2(p: vec2f, dir: vec2f, phase: f32, sharpness: f32) -> f32 {
  let perpendicular = vec2f(-dir.y, dir.x);
  let along = dot(p, dir);
  let bentSide = dot(p, perpendicular)
    + sin(along * 15.0 + phase) * 0.027
    + sin(along * 31.0 - phase * 1.37) * 0.012;
  let width = mix(0.046, 0.020, clamp(sharpness / 7.0, 0.0, 1.0));
  let ridge = exp(-abs(bentSide) / max(width, 0.006));
  let forward = smoothstep(-0.025, 0.075, along)
    * (1.0 - smoothstep(0.24, 0.53, along));
  return ridge * forward;
}

fn branchPattern2(p: vec2f, seed: f32, branchCount: f32, sharpness: f32) -> f32 {
  let baseAngle = seed * 6.28318530718;
  let dirA = vec2f(cos(baseAngle), sin(baseAngle));
  let dirB = vec2f(cos(baseAngle + 2.15), sin(baseAngle + 2.15));
  let dirC = vec2f(cos(baseAngle - 2.47), sin(baseAngle - 2.47));
  let bands = max(
    branchBand2(p, dirA, seed * 8.1, sharpness),
    max(
      branchBand2(p, dirB, seed * 11.7 + 1.9, sharpness) * 0.86,
      branchBand2(p, dirC, seed * 15.3 - 2.2, sharpness) * 0.72,
    ),
  );

  var q = p * (8.0 + branchCount * 0.62);
  var ridge = 0.0;
  var amplitude = 0.56;
  var frequency = 1.0;
  for (var i = 0; i < 3; i += 1) {
    let wave = abs(
      sin(q.y * frequency + seed * 5.1)
        + cos(q.x * frequency - seed * 3.7)
    ) * 0.5;
    ridge += pow(max(0.0, 1.0 - wave), 1.1 + sharpness * 0.20) * amplitude;
    q = rotate2(q, 0.61 + seed * 0.17 + f32(i) * 0.14);
    frequency *= 1.73;
    amplitude *= 0.53;
  }

  return clamp(max(bands, ridge * 0.66), 0.0, 1.35);
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
    clamp(params.uViscosity.x * dt * 8.0, 0.0, 0.30),
  );

  let curl = (right.y - left.y) - (up.x - down.x);
  velocity += vec2f(-velocity.y, velocity.x)
    * curl
    * params.uVorticity.x
    * dt
    * 2.8;

  let centerDelta = uv - vec2f(0.5);
  let centerRadius = max(length(centerDelta), 0.001);
  let radial = centerDelta / centerRadius;
  let centerFalloff = exp(-centerRadius * 6.6);
  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;

  // Idle motion deliberately avoids a global tangent force. This prevents the whole
  // simulation from collapsing into a single obvious whirlpool.
  let idleVector = vec2f(
    sin((uv.y + time * 0.021) * 12.7) + sin((uv.x - time * 0.016) * 7.3) * 0.45,
    cos((uv.x - time * 0.018) * 11.1) - cos((uv.y + time * 0.013) * 8.7) * 0.42,
  );
  velocity += idleVector
    * centerFalloff
    * params.uTurbulence.x
    * dt
    * (0.010 + audio * 0.006);
  velocity -= centerDelta * centerFalloff * dt * 0.026;
  velocity += radial
    * centerFalloff
    * params.uExpansion.x
    * sin(time * 1.13 + centerRadius * 14.0)
    * dt
    * 0.006;
  dye += centerFalloff * (0.007 + audio * 0.006) * dt;

  let burstAmplitude = frame.pointer.z;
  if (burstAmplitude > 0.0005) {
    let seed = frame.pointerDelta.w;
    let branches = clamp(params.uFractalBranches.x, 3.0, 9.0);
    let sharpness = clamp(params.uBranchSharpness.x, 1.0, 7.0);
    let pattern = branchPattern2(centerDelta, seed, branches, sharpness);

    let targetVector = frame.pointerDelta.xy - vec2f(0.5);
    let targetDirection = targetVector / max(length(targetVector), 0.001);
    let directionBias = 0.58
      + 0.42 * smoothstep(-0.72, 0.82, dot(radial, targetDirection));
    let radialEnvelope = exp(-centerRadius * 2.25);
    let source = burstAmplitude
      * radialEnvelope
      * directionBias
      * (0.16 + pattern * 1.42);

    let pushDirection = normalize(radial * 0.72 + targetDirection * 0.28 + vec2f(0.0001));
    velocity += pushDirection
      * source
      * params.uBurstForce.x
      * dt
      * 12.0;

    let perpendicular = vec2f(-targetDirection.y, targetDirection.x);
    velocity += perpendicular
      * sin(dot(centerDelta, perpendicular) * 34.0 + seed * 13.0)
      * source
      * params.uBurstForce.x
      * dt
      * 0.75;

    let coreBlast = exp(-dot(centerDelta, centerDelta) / 0.018);
    velocity += radial
      * coreBlast
      * burstAmplitude
      * params.uBurstForce.x
      * dt
      * 4.2;

    dye += source * params.uBurstDensity.x * dt * 2.4;
    burstField += source * dt * 7.2;
  }

  let speed = length(velocity);
  if (speed > 2.5) {
    velocity *= 2.5 / speed;
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

fn rotateVolume(pInput: vec3f, time: f32) -> vec3f {
  var p = pInput;
  let xz = rotate2(vec2f(p.x, p.z), time * 0.19 + 0.23);
  p = vec3f(xz.x, p.y, xz.y);
  let yz = rotate2(vec2f(p.y, p.z), -time * 0.13 + 0.41);
  p = vec3f(p.x, yz.x, yz.y);
  return p;
}

// Continuous 3D spiral-ridge noise inspired by the supplied static reference. It uses
// repeated sine/cosine bands and full-vector rotations, so there is no angular seam.
fn spiralRidged3(pInput: vec3f, phase: f32) -> f32 {
  var p = pInput;
  var sum = 0.0;
  var amplitude = 0.52;
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

    frequency *= 1.69;
    amplitude *= 0.5;
  }
  return clamp(sum / 0.975, 0.0, 1.0);
}

fn spiralFlow3(pInput: vec3f, phase: f32) -> f32 {
  var p = pInput;
  var sum = 0.0;
  var amplitude = 0.58;
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

    frequency *= 1.54;
    amplitude *= 0.49;
  }
  return 0.5 + 0.5 * clamp(sum / 1.01, -1.0, 1.0);
}

fn sampleFluidWorld(p: vec3f) -> Fluid3D {
  let weightsRaw = abs(p) + vec3f(0.18);
  let weights = weightsRaw / max(dot(weightsRaw, vec3f(1.0)), 0.001);

  let xy = sampleFluidNearest(p.xy * 0.47 + vec2f(0.5));
  let yz = sampleFluidNearest(p.yz * 0.47 + vec2f(0.5));
  let zx = sampleFluidNearest(vec2f(p.z, p.x) * 0.47 + vec2f(0.5));

  let velocityXY = vec3f(xy.x, xy.y, 0.0);
  let velocityYZ = vec3f(0.0, yz.x, yz.y);
  let velocityZX = vec3f(zx.y, 0.0, zx.x);

  var result: Fluid3D;
  result.velocity = velocityXY * weights.z
    + velocityYZ * weights.x
    + velocityZX * weights.y;
  result.dye = xy.z * weights.z + yz.z * weights.x + zx.z * weights.y;
  result.burst = xy.w * weights.z + yz.w * weights.x + zx.w * weights.y;
  return result;
}

fn seedDirection(seed: f32, offset: f32) -> vec3f {
  let a = seed * 6.28318530718 + offset * 2.173;
  let z = sin(a * 1.731 + offset * 0.83) * 0.68;
  let planar = sqrt(max(0.05, 1.0 - z * z));
  return normalize(vec3f(cos(a) * planar, z, sin(a) * planar));
}

fn branchTube3(
  p: vec3f,
  dir: vec3f,
  phase: f32,
  width: f32,
  reach: f32,
) -> f32 {
  var referenceAxis = vec3f(0.0, 1.0, 0.0);
  if (abs(dir.y) > 0.82) {
    referenceAxis = vec3f(1.0, 0.0, 0.0);
  }
  let sideA = normalize(cross(dir, referenceAxis));
  let sideB = normalize(cross(dir, sideA));
  let along = dot(p, dir);
  let bendA = sin(along * 9.0 + phase) * 0.046
    + sin(along * 19.0 - phase * 0.71) * 0.018;
  let bendB = cos(along * 7.0 - phase * 0.83) * 0.038
    + sin(along * 13.0 + phase * 1.31) * 0.014;
  let side = vec2f(
    dot(p, sideA) - bendA,
    dot(p, sideB) - bendB,
  );
  let tube = 1.0 - smoothstep(width, width * 1.85, length(side));
  let window = smoothstep(0.10, 0.26, along)
    * (1.0 - smoothstep(reach * 0.82, reach, along));
  return tube * window;
}

fn foldedSheet3(
  p: vec3f,
  normal: vec3f,
  phase: f32,
  thickness: f32,
  reach: f32,
) -> f32 {
  var referenceAxis = vec3f(0.0, 1.0, 0.0);
  if (abs(normal.y) > 0.82) {
    referenceAxis = vec3f(1.0, 0.0, 0.0);
  }
  let tangentA = normalize(cross(normal, referenceAxis));
  let tangentB = normalize(cross(normal, tangentA));
  let u = dot(p, tangentA);
  let v = dot(p, tangentB);
  let plane = dot(p, normal);
  let fold = sin(u * 9.5 + phase) * 0.034
    + sin(v * 12.7 - phase * 1.2) * 0.027
    + sin((u + v) * 18.0 + phase * 0.43) * 0.014;
  let sheet = 1.0 - smoothstep(thickness, thickness * 2.4, abs(plane - fold));
  let radius = length(p);
  let window = smoothstep(0.28, 0.42, radius)
    * (1.0 - smoothstep(reach * 0.82, reach, radius));
  return sheet * window;
}

fn densityField(pInput: vec3f) -> f32 {
  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;
  let inputRadius = length(pInput);
  if (inputRadius > 1.075) {
    return 0.0;
  }

  let fluid = sampleFluidWorld(pInput);
  let burstLocal = clamp(
    fluid.burst * params.uBurstVisualStrength.x + frame.pointer.z * 0.22,
    0.0,
    1.65,
  );
  let activity = smoothstep(0.025, 0.42, burstLocal);

  // The 2D solver is world-anchored through tri-planar sampling. It no longer follows
  // the camera, so orbiting exposes genuinely different sides of the same 3D volume.
  var p = pInput - fluid.velocity
    * params.uFluidInfluence.x
    * (0.040 + activity * 0.095);
  let radius = max(length(p), 0.001);
  let direction = p / radius;

  let q = rotateVolume(p, time * (0.45 + params.uTurbulence.x * 0.08));
  let coarse = spiralFlow3(q * 1.72 + vec3f(0.37, -0.21, 0.13), time * 0.28);
  let detail = spiralRidged3(q * params.uNoiseScale.x, time * 0.61);
  let fine = clamp(
    0.5
      + (sin(q.x * 11.3 + time * 0.91)
        + sin(q.y * 13.7 - time * 0.73)
        + sin(q.z * 17.1 + time * 0.47)) / 6.0,
    0.0,
    1.0,
  );

  let directionalLobe = (
    sin(direction.x * 2.9 + time * 0.13)
      + sin(direction.y * 3.7 - time * 0.11)
      + sin(direction.z * 4.3 + 1.4)
  ) / 3.0;
  let coreRadius = params.uCoreRadius.x
    + (coarse - 0.5) * params.uCoreWobble.x
    + directionalLobe * params.uCoreWobble.x * 0.22
    + (audio - 0.5) * params.uAudioInfluence.x * 0.010;
  let surfaceWarp = (detail - 0.5) * params.uCoreDetailStrength.x * 0.055
    + (fine - 0.5) * params.uCoreDetailStrength.x * 0.018;
  let coreEnvelope = 1.0 - smoothstep(
    coreRadius - 0.080,
    coreRadius + 0.100,
    radius - surfaceWarp,
  );
  let coreTexture = 0.46 + 0.54 * smoothstep(
    params.uDetailCutoff.x - 0.16,
    params.uDetailCutoff.x + 0.28,
    detail * 0.82 + fine * 0.18,
  );
  let idleDensity = coreEnvelope * coreTexture * 0.92;

  // Branch tubes and folded sheets are the expensive part of the burst. In the normal
  // intact-core state, return before evaluating any of them.
  if (activity < 0.001) {
    return max(0.0, idleDensity * params.uDensity.x);
  }

  let seed = frame.pointerDelta.w;
  let reach = params.uBurstReach.x;
  let width = params.uBranchWidth.x;
  let dirA = seedDirection(seed, 0.0);
  let dirB = seedDirection(seed, 1.0);
  let dirC = seedDirection(seed, 2.0);
  let dirD = seedDirection(seed, 3.0);
  let dirE = seedDirection(seed, 4.0);

  let tubeA = branchTube3(p, dirA, seed * 12.1 + 0.7, width, reach);
  let tubeB = branchTube3(p, dirB, seed * 15.3 + 2.1, width * 0.88, reach * 0.92);
  let tubeC = branchTube3(p, dirC, seed * 18.7 - 1.4, width * 1.08, reach * 0.86);
  let tubeD = branchTube3(p, dirD, seed * 21.2 + 3.7, width * 0.72, reach * 0.78);
  let tubeE = branchTube3(p, dirE, seed * 24.5 - 2.9, width * 0.64, reach * 0.72);
  let branchVolume = max(
    tubeA,
    max(tubeB * 0.92, max(tubeC * 0.84, max(tubeD * 0.70, tubeE * 0.58))),
  );

  let sheetA = foldedSheet3(p, dirB, seed * 9.7 + 1.2, width * 0.52, reach * 0.96);
  let sheetB = foldedSheet3(p, dirD, seed * 13.4 - 2.0, width * 0.44, reach * 0.84);
  let sheets = max(sheetA, sheetB * 0.82) * params.uSheetStrength.x;

  let fracture = clamp(
    activity
      * max(branchVolume, sheets * 0.58)
      * params.uCoreBreakup.x,
    0.0,
    0.90,
  );
  let coreDensity = idleDensity
    * (1.0 - fracture * smoothstep(0.12, params.uCoreRadius.x + 0.12, radius));

  let burstTexture = 0.42 + 0.58 * smoothstep(
    params.uDetailCutoff.x - 0.18,
    params.uDetailCutoff.x + 0.24,
    detail * 0.70 + fine * 0.30,
  );
  let explodedDensity = activity
    * (branchVolume + sheets)
    * burstTexture
    * (0.55 + burstLocal * 0.72);

  let smokeTrail = clamp(fluid.dye, 0.0, 1.5)
    * activity
    * (1.0 - smoothstep(0.72, 1.04, radius))
    * (0.08 + detail * 0.18);

  let density = coreDensity
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
  let rd = normalize(
    forward * focalLength
      + cameraRight * screen.x
      + cameraUp * screen.y
  );

  let hit = intersectSphere(ro, rd, 1.085);
  var background = mix(
    vec3f(0.007, 0.010, 0.017),
    vec3f(0.030, 0.047, 0.070),
    in.uv.y,
  );
  let vignette = 1.0 - 0.22 * dot(screen * 0.48, screen * 0.48);
  background *= max(vignette, 0.58);

  var color = background;
  if (hit.y > max(hit.x, 0.0)) {
    let steps = clamp(i32(params.uSteps.x), 28, 132);
    let startT = max(hit.x, 0.0);
    let travelDistance = hit.y - startT;
    let stepLength = travelDistance / f32(steps);
    let jitter = (
      hash31(vec3f(in.position.xy, fract(time))) - 0.5
    ) * stepLength * params.uJitter.x;

    var t = startT + jitter;
    var transmittance = 1.0;
    var scattering = vec3f(0.0);
    let lightDir = normalize(vec3f(-0.52, 0.71, 0.47));
    let gasColor = params.uGasColor.xyz;

    for (var i = 0; i < 132; i += 1) {
      if (i >= steps) {
        break;
      }

      let p = ro + rd * t;
      let radius = length(p);
      if (radius < 1.075) {
        let density = densityField(p);
        if (density > 0.0035) {
          let q = rotateVolume(p, time * 0.22);
          let normalPerturbation = vec3f(
            sin(q.y * 5.3 + time * 0.31),
            sin(q.z * 6.1 - time * 0.27),
            sin(q.x * 5.7 + 1.2),
          ) * params.uCoreDetailStrength.x * 0.065;
          let outward = normalize(p + normalPerturbation + vec3f(0.0001));
          let directional = clamp(
            dot(outward, lightDir) * 0.5 + 0.5,
            0.0,
            1.0,
          );
          let localShadow = exp(-density * params.uShadow.x * 0.37);
          let light = 0.23 + 0.77 * directional * localShadow;
          let rim = pow(1.0 - abs(dot(outward, -rd)), 2.1);
          let burstGlow = clamp(frame.pointer.z + frame.pointer.w * 0.12, 0.0, 1.2);
          let sampleColor = gasColor * (
            light
              + rim * (0.18 + burstGlow * 0.08)
              + burstGlow * 0.025
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
      }
      t += stepLength;
    }

    color = scattering + background * transmittance;
  }

  let waveX = in.uv.x * 2.0 - 1.0;
  let wave = -0.79
    + waveform(waveX, time)
      * (0.020 + frame.pointer.w * 0.015)
      * params.uAudioInfluence.x;
  let lineDistance = abs(screen.y - wave);
  let line = exp(-lineDistance * max(resolution.y, 1.0) * 0.42);
  let baseline = exp(
    -abs(screen.y + 0.79) * max(resolution.y, 1.0) * 0.16
  ) * 0.12;
  color += params.uWaveColor.xyz * (line * 0.68 + baseline);

  color = color / (color + vec3f(1.0));
  color = pow(max(color, vec3f(0.0)), vec3f(1.0 / 2.2));
  return vec4f(color, 1.0);
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uCameraYaw": {
      "type": "float", "default": 18.0, "min": -180.0, "max": 180.0, "step": 1.0,
      "label": { "zh": "相机水平角", "en": "Camera Yaw" },
      "description": { "zh": "绕世界空间体积水平环绕；新密度场不再跟随相机投影。", "en": "World-space horizontal orbit; the density field no longer follows the camera projection." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraPitch": {
      "type": "float", "default": 8.0, "min": -80.0, "max": 80.0, "step": 1.0,
      "label": { "zh": "相机俯仰角", "en": "Camera Pitch" },
      "description": { "zh": "控制上下观察角度。", "en": "Vertical orbit angle." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraDistance": {
      "type": "float", "default": 3.15, "min": 1.5, "max": 6.0, "step": 0.02,
      "label": { "zh": "相机距离", "en": "Camera Distance" },
      "description": { "zh": "控制相机到体积中心的距离。", "en": "Distance from camera to volume center." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraFov": {
      "type": "float", "default": 46.0, "min": 20.0, "max": 100.0, "step": 1.0,
      "label": { "zh": "相机视野", "en": "Camera FOV" },
      "description": { "zh": "垂直视野角。", "en": "Vertical field of view." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uCameraOrbitSpeed": {
      "type": "float", "default": 0.0, "min": -30.0, "max": 30.0, "step": 0.1,
      "label": { "zh": "自动环绕速度", "en": "Auto Orbit Speed" },
      "description": { "zh": "用于验证三维结构的自动水平环绕速度。", "en": "Automatic yaw speed useful for inspecting the true 3D structure." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uDensity": {
      "type": "float", "default": 0.86, "min": 0.1, "max": 3.0, "step": 0.01,
      "label": { "zh": "气体密度", "en": "Gas Density" },
      "description": { "zh": "整体体积密度。", "en": "Overall volume density." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uAbsorption": {
      "type": "float", "default": 1.72, "min": 0.2, "max": 8.0, "step": 0.01,
      "label": { "zh": "吸收", "en": "Absorption" },
      "description": { "zh": "Beer-Lambert 吸收强度。", "en": "Beer-Lambert absorption strength." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uCoreRadius": {
      "type": "float", "default": 0.43, "min": 0.25, "max": 0.65, "step": 0.005,
      "label": { "zh": "核心半径", "en": "Core Radius" },
      "description": { "zh": "平静状态的基础球体尺寸。", "en": "Base radius of the intact idle core." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uCoreWobble": {
      "type": "float", "default": 0.075, "min": 0.0, "max": 0.22, "step": 0.005,
      "label": { "zh": "核心蠕动", "en": "Core Wobble" },
      "description": { "zh": "低频世界空间形变；保持球体但能从不同相机角度看到不同轮廓。", "en": "Low-frequency world-space deformation that keeps a spherical core while revealing different silhouettes from different camera angles." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uCoreDetailStrength": {
      "type": "float", "default": 0.72, "min": 0.0, "max": 1.8, "step": 0.01,
      "label": { "zh": "表面细节", "en": "Surface Detail" },
      "description": { "zh": "控制连续 3D spiral/ridged 细节对表面和光照的影响。", "en": "Strength of continuous 3D spiral/ridged detail on the surface and lighting." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uNoiseScale": {
      "type": "float", "default": 3.1, "min": 1.0, "max": 7.0, "step": 0.02,
      "label": { "zh": "分形细节尺度", "en": "Fractal Detail Scale" },
      "description": { "zh": "连续三维 spiral noise 的空间频率。", "en": "Spatial frequency of the seamless 3D spiral noise." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uDetailCutoff": {
      "type": "float", "default": 0.48, "min": 0.18, "max": 0.80, "step": 0.01,
      "label": { "zh": "内部疏松度", "en": "Internal Porosity" },
      "description": { "zh": "提高后会削弱低分形密度区域。", "en": "Higher values suppress low-fractal-density regions." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uTurbulence": {
      "type": "float", "default": 0.72, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "翻涌速度", "en": "Rolling Speed" },
      "description": { "zh": "控制核心 3D 噪声与二维场的缓慢运动速度，不再产生整体旋涡。", "en": "Controls slow 3D noise and 2D field motion without imposing a global whirlpool." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uExpansion": {
      "type": "float", "default": 0.16, "min": 0.0, "max": 1.5, "step": 0.01,
      "label": { "zh": "呼吸扩张", "en": "Breathing Expansion" },
      "description": { "zh": "仅用于很弱的平静呼吸，不持续把主体吹大。", "en": "Subtle idle breathing only; it does not continuously inflate the body." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uFluidInfluence": {
      "type": "float", "default": 1.25, "min": 0.0, "max": 3.5, "step": 0.01,
      "label": { "zh": "流体形变", "en": "Fluid Deformation" },
      "description": { "zh": "二维场通过无接缝三平面采样对三维密度的形变强度。", "en": "Strength of seam-free tri-planar lifting of the 2D field into the 3D density." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uAdvection": {
      "type": "float", "default": 1.05, "min": 0.1, "max": 2.0, "step": 0.01,
      "label": { "zh": "平流速度", "en": "Advection" },
      "description": { "zh": "半拉格朗日平流回溯距离。", "en": "Semi-Lagrangian backtrace distance." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uViscosity": {
      "type": "float", "default": 0.15, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "粘性", "en": "Viscosity" },
      "description": { "zh": "速度场邻域平滑。", "en": "Neighborhood smoothing of the velocity field." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uVorticity": {
      "type": "float", "default": 0.82, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "涡量保持", "en": "Vorticity" },
      "description": { "zh": "只保留局部卷曲，不再添加全局切向旋转。", "en": "Preserves local curls without adding a global tangent rotation." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uVelocityDissipation": {
      "type": "float", "default": 0.45, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "速度耗散", "en": "Velocity Dissipation" },
      "description": { "zh": "二维速度场衰减；默认更快消除启动时残留的旋转速度。", "en": "2D velocity decay; the default removes residual startup rotation more quickly." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uDyeDissipation": {
      "type": "float", "default": 0.38, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "烟雾耗散", "en": "Smoke Dissipation" },
      "description": { "zh": "二维烟雾辅助场衰减。", "en": "2D smoke helper-field decay." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uBurstFieldDissipation": {
      "type": "float", "default": 1.05, "min": 0.1, "max": 4.0, "step": 0.01,
      "label": { "zh": "爆裂记忆耗散", "en": "Burst Memory Dissipation" },
      "description": { "zh": "爆裂结构重新收拢的速度。", "en": "How quickly the transient burst structure collapses back." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uSolverSubsteps": {
      "type": "int", "default": 2, "min": 1, "max": 4, "step": 1,
      "label": { "zh": "解算子步", "en": "Solver Substeps" },
      "description": { "zh": "每帧二维流体子步数。", "en": "2D solver substeps per frame." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uClickBurstStrength": {
      "type": "float", "default": 1.15, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "点击爆裂强度", "en": "Click Burst Strength" },
      "description": { "zh": "每次鼠标按下触发的一次性爆裂强度。", "en": "One-shot burst strength on pointer down." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstDuration": {
      "type": "float", "default": 0.72, "min": 0.15, "max": 2.0, "step": 0.01,
      "label": { "zh": "注入持续时间", "en": "Injection Duration" },
      "description": { "zh": "CPU 侧一次爆裂注入包络的持续时间。", "en": "Duration of the CPU-side burst injection envelope." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstForce": {
      "type": "float", "default": 2.15, "min": 0.0, "max": 5.0, "step": 0.01,
      "label": { "zh": "爆裂推力", "en": "Burst Force" },
      "description": { "zh": "分形注入对二维速度场的推力。", "en": "Force applied by the fractal injection to the 2D velocity field." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstDensity": {
      "type": "float", "default": 1.05, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "爆裂烟雾", "en": "Burst Smoke" },
      "description": { "zh": "爆裂注入的二维烟雾量。", "en": "Amount of 2D smoke injected by a burst." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstVisualStrength": {
      "type": "float", "default": 1.15, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "爆裂结构强度", "en": "Burst Structure Strength" },
      "description": { "zh": "二维爆裂记忆抬升为三维枝杈和褶皱的强度。", "en": "Strength used when lifting 2D burst memory into 3D branches and folds." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uFractalBranches": {
      "type": "float", "default": 5.5, "min": 3.0, "max": 9.0, "step": 0.1,
      "label": { "zh": "二维分形复杂度", "en": "2D Fractal Complexity" },
      "description": { "zh": "影响爆裂注入的多尺度分支复杂度，不使用极坐标角度。", "en": "Controls multi-scale branch complexity in the burst injection without polar-angle mapping." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBranchSharpness": {
      "type": "float", "default": 2.7, "min": 1.0, "max": 7.0, "step": 0.1,
      "label": { "zh": "二维分支锐度", "en": "2D Branch Sharpness" },
      "description": { "zh": "控制二维爆裂图案的锐度；默认保持较宽避免尖刺。", "en": "Sharpness of the 2D burst pattern; the default remains broad to avoid spikes." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBranchWidth": {
      "type": "float", "default": 0.075, "min": 0.025, "max": 0.18, "step": 0.002,
      "label": { "zh": "三维枝杈宽度", "en": "3D Branch Width" },
      "description": { "zh": "炸开后粗大弯曲体积枝杈的宽度。", "en": "Width of broad curved volumetric branches after a burst." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstReach": {
      "type": "float", "default": 0.90, "min": 0.55, "max": 1.05, "step": 0.01,
      "label": { "zh": "爆裂伸展", "en": "Burst Reach" },
      "description": { "zh": "炸开结构从核心伸出的最大范围。", "en": "Maximum reach of exploded structures from the core." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uSheetStrength": {
      "type": "float", "default": 0.72, "min": 0.0, "max": 2.0, "step": 0.01,
      "label": { "zh": "褶皱薄片", "en": "Folded Sheets" },
      "description": { "zh": "参考静态形态加入的宽褶皱/膜状体积结构。", "en": "Broad folded membrane-like volume structures inspired by the supplied static shape reference." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uCoreBreakup": {
      "type": "float", "default": 1.05, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "核心撕裂", "en": "Core Breakup" },
      "description": { "zh": "爆裂枝杈穿过核心时削减核心密度的程度。", "en": "How strongly burst branches tear density out of the core." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uAudioBurstEnabled": {
      "type": "boolean", "default": true,
      "label": { "zh": "音频触发爆裂", "en": "Audio Burst Trigger" },
      "description": { "zh": "合成音频包络向上越过阈值时触发随机爆裂。", "en": "Triggers a randomized burst when the synthetic audio envelope crosses the threshold upward." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uAudioBurstStrength": {
      "type": "float", "default": 0.72, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "音频爆裂强度", "en": "Audio Burst Strength" },
      "description": { "zh": "节拍事件触发的爆裂强度。", "en": "Burst strength triggered by a beat event." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uBeatThreshold": {
      "type": "float", "default": 0.71, "min": 0.45, "max": 0.95, "step": 0.01,
      "label": { "zh": "节拍阈值", "en": "Beat Threshold" },
      "description": { "zh": "合成音频包络的上升沿触发阈值。", "en": "Upward-crossing threshold for the synthetic audio envelope." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uBeatCooldown": {
      "type": "float", "default": 0.78, "min": 0.2, "max": 3.0, "step": 0.01,
      "label": { "zh": "节拍冷却", "en": "Beat Cooldown" },
      "description": { "zh": "两个自动爆裂事件之间的最短间隔。", "en": "Minimum interval between automatic burst events." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uAudioInfluence": {
      "type": "float", "default": 0.62, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "音频呼吸", "en": "Audio Breathing" },
      "description": { "zh": "音频包络对平静核心呼吸和底部波形的影响。", "en": "Influence of the audio envelope on idle breathing and the bottom waveform." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uSteps": {
      "type": "int", "default": 68, "min": 28, "max": 132, "step": 1,
      "label": { "zh": "光线步数", "en": "Ray Steps" },
      "description": { "zh": "体积 raymarch 采样步数。", "en": "Volume ray-marching sample count." },
      "group": { "zh": "采样", "en": "Sampling" }
    },
    "uJitter": {
      "type": "float", "default": 0.82, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "采样抖动", "en": "Jitter" },
      "description": { "zh": "减弱低步数下的固定采样条带。", "en": "Reduces fixed-step banding at lower sample counts." },
      "group": { "zh": "采样", "en": "Sampling" }
    },
    "uShadow": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 4.0, "step": 0.01,
      "label": { "zh": "局部阴影", "en": "Local Shadow" },
      "description": { "zh": "低成本局部密度阴影。", "en": "Low-cost local density shadowing." },
      "group": { "zh": "光照", "en": "Lighting" }
    },
    "uGasColor": {
      "type": "color", "default": "#789dd0",
      "label": { "zh": "气体颜色", "en": "Gas Color" },
      "description": { "zh": "体积散射颜色。", "en": "Volumetric scattering color." },
      "group": { "zh": "外观", "en": "Appearance" }
    },
    "uWaveColor": {
      "type": "color", "default": "#55d8ff",
      "label": { "zh": "波形颜色", "en": "Wave Color" },
      "description": { "zh": "底部音频波动曲线颜色。", "en": "Color of the audio waveform." },
      "group": { "zh": "外观", "en": "Appearance" }
    },
    "uUncappedBenchmark": {
      "type": "boolean", "default": false,
      "label": { "zh": "取消帧率限制", "en": "Uncapped Benchmark" },
      "description": { "zh": "绕过显示刷新同步测试 GPU 吞吐，可能显著提高功耗。", "en": "Bypasses display synchronization to benchmark GPU throughput and may increase power use." },
      "group": { "zh": "性能", "en": "Performance" }
    }
  }
}
@endshaderlab */