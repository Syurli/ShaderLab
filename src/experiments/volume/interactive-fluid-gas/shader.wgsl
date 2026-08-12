struct VertexOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
};

struct Fluid3D {
  velocity: vec3f,
  dye: f32,
  burst: f32,
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

fn branchBand2(p: vec2f, dir: vec2f, phase: f32, width: f32) -> f32 {
  let sideAxis = vec2f(-dir.y, dir.x);
  let along = dot(p, dir);
  let side = dot(p, sideAxis)
    + sin(along * 14.0 + phase) * 0.026
    + sin(along * 31.0 - phase * 1.31) * 0.010;
  let ridge = exp(-abs(side) / max(width, 0.005));
  let window = smoothstep(-0.02, 0.06, along)
    * (1.0 - smoothstep(0.24, 0.54, along));
  return ridge * window;
}

fn branchPattern2(p: vec2f, seed: f32, complexity: f32, sharpness: f32) -> f32 {
  let a = seed * 6.28318530718;
  let d0 = vec2f(cos(a), sin(a));
  let d1 = vec2f(cos(a + 2.09), sin(a + 2.09));
  let d2 = vec2f(cos(a - 2.44), sin(a - 2.44));
  let baseWidth = mix(0.046, 0.019, clamp(sharpness / 7.0, 0.0, 1.0));
  let bands = max(
    branchBand2(p, d0, seed * 8.2, baseWidth),
    max(
      branchBand2(p, d1, seed * 12.7 + 1.3, baseWidth * 0.78) * 0.88,
      branchBand2(p, d2, seed * 17.1 - 2.0, baseWidth * 0.66) * 0.76,
    ),
  );

  var q = p * (9.0 + complexity * 0.78);
  var ridge = 0.0;
  var amp = 0.58;
  var freq = 1.0;
  for (var i = 0; i < 3; i += 1) {
    let wave = abs(
      sin(q.y * freq + seed * 5.3)
        + cos(q.x * freq - seed * 3.9)
    ) * 0.5;
    ridge += pow(max(0.0, 1.0 - wave), 1.35 + sharpness * 0.20) * amp;
    q = rotate2(q, 0.57 + seed * 0.19 + f32(i) * 0.17);
    freq *= 1.82;
    amp *= 0.50;
  }
  return clamp(max(bands, ridge * 0.56), 0.0, 1.35);
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
  velocity = mix(
    velocity,
    (left + right + down + up) * 0.25,
    clamp(params.uViscosity.x * dt * 6.0, 0.0, 0.24),
  );

  let curl = (right.y - left.y) - (up.x - down.x);
  velocity += vec2f(-velocity.y, velocity.x)
    * curl
    * params.uVorticity.x
    * dt
    * 3.1;

  let centerDelta = uv - vec2f(0.5);
  let centerRadius = max(length(centerDelta), 0.001);
  let radial = centerDelta / centerRadius;
  let centerFalloff = exp(-centerRadius * 6.6);
  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;

  let idleA = vec2f(
    sin(uv.y * 13.7 + time * 0.79) + sin(uv.x * 8.1 - time * 0.53) * 0.42,
    cos(uv.x * 12.3 - time * 0.67) - cos(uv.y * 9.1 + time * 0.44) * 0.40,
  );
  let idleB = vec2f(
    sin((uv.x + uv.y) * 19.1 - time * 0.91),
    cos((uv.x - uv.y) * 17.3 + time * 0.82),
  );
  velocity += (idleA * 0.78 + idleB * 0.22)
    * centerFalloff
    * params.uTurbulence.x
    * dt
    * (0.020 + audio * 0.006);
  velocity -= centerDelta * centerFalloff * dt * 0.016;

  let injection = frame.pointer.z;
  if (injection > 0.0005) {
    let seed = frame.pointerDelta.w;
    let pattern = branchPattern2(
      centerDelta,
      seed,
      clamp(params.uFractalBranches.x, 3.0, 10.0),
      clamp(params.uBranchSharpness.x, 1.0, 7.0),
    );
    let targetVector = frame.pointerDelta.xy - vec2f(0.5);
    let targetDirection = targetVector / max(length(targetVector), 0.001);
    let directionBias = 0.38
      + 0.62 * smoothstep(-0.72, 0.90, dot(radial, targetDirection));
    let radialEnvelope = exp(-centerRadius * 3.1);
    let source = injection
      * radialEnvelope
      * directionBias
      * pattern;

    let pushDirection = normalize(radial * 0.60 + targetDirection * 0.40 + vec2f(0.0001));
    velocity += pushDirection
      * source
      * params.uBurstForce.x
      * dt
      * 15.0;

    let perpendicular = vec2f(-targetDirection.y, targetDirection.x);
    velocity += perpendicular
      * sin(dot(centerDelta, perpendicular) * 42.0 + seed * 17.0)
      * source
      * params.uBurstForce.x
      * dt
      * 0.96;

    dye += source * params.uBurstDensity.x * dt * 1.55;
    burstField += source * dt * 5.2;
  }

  let speed = length(velocity);
  if (speed > 2.8) {
    velocity *= 2.8 / speed;
  }

  let index = gid.y * FLUID_SIZE + gid.x;
  fluidOut.cells[index] = vec4f(
    velocity,
    clamp(dye, 0.0, 1.5),
    clamp(burstField, 0.0, 1.8),
  );
}

fn hash31(p: vec3f) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + vec3f(33.33));
  return fract((q.x + q.y) * q.z);
}

fn rotateVolume(pInput: vec3f, time: f32) -> vec3f {
  var p = pInput;
  let xz = rotate2(vec2f(p.x, p.z), time * 0.16 + 0.23);
  p = vec3f(xz.x, p.y, xz.y);
  let yz = rotate2(vec2f(p.y, p.z), -time * 0.10 + 0.41);
  return vec3f(p.x, yz.x, yz.y);
}

fn crawlWarp(p: vec3f, time: f32, amount: f32) -> vec3f {
  let w = vec3f(
    sin(p.y * 3.9 + p.z * 2.3 + time * 0.89),
    sin(p.z * 3.3 - p.x * 2.9 - time * 0.77 + 1.7),
    sin(p.x * 3.6 + p.y * 2.7 + time * 0.72 + 3.1),
  );
  let w2 = vec3f(
    sin(p.z * 7.9 - time * 1.21),
    cos(p.x * 7.1 + time * 1.02),
    sin(p.y * 8.5 + time * 0.84),
  );
  return p + (w * 0.70 + w2 * 0.30) * amount;
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

fn sampleFluidWorld(p: vec3f) -> Fluid3D {
  let weightsRaw = abs(p) + vec3f(0.20);
  let weights = weightsRaw / max(dot(weightsRaw, vec3f(1.0)), 0.001);
  let xy = sampleFluid(p.xy * 0.47 + vec2f(0.5));
  let yz = sampleFluid(p.yz * 0.47 + vec2f(0.5));
  let zx = sampleFluid(vec2f(p.z, p.x) * 0.47 + vec2f(0.5));
  var result: Fluid3D;
  result.velocity = vec3f(xy.x, xy.y, 0.0) * weights.z
    + vec3f(0.0, yz.x, yz.y) * weights.x
    + vec3f(zx.y, 0.0, zx.x) * weights.y;
  result.dye = xy.z * weights.z + yz.z * weights.x + zx.z * weights.y;
  result.burst = xy.w * weights.z + yz.w * weights.x + zx.w * weights.y;
  return result;
}

fn seedDirection(seed: f32, offset: f32) -> vec3f {
  let a = seed * 6.28318530718 + offset * 2.173;
  let z = sin(a * 1.731 + offset * 0.83) * 0.72;
  let planar = sqrt(max(0.05, 1.0 - z * z));
  return normalize(vec3f(cos(a) * planar, z, sin(a) * planar));
}

fn branchCoords(p: vec3f, dir: vec3f, phase: f32, bendScale: f32) -> vec3f {
  var referenceAxis = vec3f(0.0, 1.0, 0.0);
  if (abs(dir.y) > 0.82) {
    referenceAxis = vec3f(1.0, 0.0, 0.0);
  }
  let sideA = normalize(cross(dir, referenceAxis));
  let sideB = normalize(cross(dir, sideA));
  let along = dot(p, dir);
  let bendA = (
    sin(along * 9.7 + phase) * 0.052
      + sin(along * 21.0 - phase * 0.71) * 0.019
  ) * bendScale;
  let bendB = (
    cos(along * 7.9 - phase * 0.83) * 0.043
      + sin(along * 15.0 + phase * 1.31) * 0.015
  ) * bendScale;
  return vec3f(
    along,
    dot(p, sideA) - bendA,
    dot(p, sideB) - bendB,
  );
}

fn branchBody3(
  p: vec3f,
  dir: vec3f,
  phase: f32,
  width: f32,
  reach: f32,
  spread: f32,
  returnMix: f32,
) -> f32 {
  let reachNow = mix(0.24, reach, clamp(spread, 0.0, 1.0));
  let coords = branchCoords(p, dir, phase, 0.35 + spread * 0.95);
  let along = coords.x;
  let normalizedAlong = clamp(along / max(reachNow, 0.001), 0.0, 1.0);
  let widthNow = width
    * mix(1.15, 0.72, normalizedAlong)
    * (1.0 + returnMix * 0.32);
  let mainRadius = length(coords.yz);
  let mainTube = 1.0 - smoothstep(widthNow * 0.58, widthNow * 1.16, mainRadius);
  let mainWindow = smoothstep(0.045, 0.14, along)
    * (1.0 - smoothstep(reachNow * 0.82, reachNow, along));
  let corrugation = 0.70
    + 0.30 * smoothstep(
      -0.55,
      0.55,
      sin(along * 43.0 + coords.y * 31.0 + phase * 1.7)
        + sin(along * 71.0 - coords.z * 27.0 - phase * 0.9) * 0.45,
    );

  let splitStart = reachNow * 0.31;
  let splitDistance = max(along - splitStart, 0.0);
  let splitGate = smoothstep(splitStart, splitStart + 0.07, along);
  let splitOffset = splitDistance
    * (0.19 + params.uFineBranching.x * 0.11)
    * (0.55 + spread * 0.45);
  let splitY = coords.y - splitOffset * sin(phase * 1.3 + 1.1);
  let splitZ = coords.z - splitOffset * cos(phase * 1.1 + 2.2);
  let splitRadius = length(vec2f(splitY, splitZ));
  let splitTube = 1.0 - smoothstep(widthNow * 0.30, widthNow * 0.62, splitRadius);
  let splitWindow = splitGate
    * (1.0 - smoothstep(reachNow * 0.72, reachNow * 0.93, along));

  return max(
    mainTube * mainWindow * corrugation,
    splitTube * splitWindow * 0.84,
  );
}

fn filamentTrain3(
  p: vec3f,
  dir: vec3f,
  phase: f32,
  width: f32,
  reach: f32,
  spread: f32,
) -> f32 {
  let reachNow = mix(0.22, reach, clamp(spread, 0.0, 1.0));
  let coords = branchCoords(p, dir, phase + 1.7, 0.45 + spread * 1.08);
  let along = coords.x;
  let sideOffset = width * (1.25 + 0.55 * sin(along * 18.0 + phase));
  let strandA = length(vec2f(coords.y - sideOffset, coords.z + sideOffset * 0.38));
  let strandB = length(vec2f(coords.y + sideOffset * 0.65, coords.z - sideOffset));
  let thin = width * 0.20;
  let filaments = max(
    1.0 - smoothstep(thin * 0.55, thin * 1.25, strandA),
    (1.0 - smoothstep(thin * 0.48, thin * 1.15, strandB)) * 0.78,
  );
  let window = smoothstep(reachNow * 0.18, reachNow * 0.30, along)
    * (1.0 - smoothstep(reachNow * 0.82, reachNow, along));
  let gaps = smoothstep(
    -0.25,
    0.55,
    sin(along * 61.0 + phase * 2.3) + sin(along * 97.0 - phase) * 0.35,
  );
  return filaments * window * (0.36 + gaps * 0.64);
}

fn metaballTrain3(
  p: vec3f,
  dir: vec3f,
  phase: f32,
  width: f32,
  reach: f32,
  spread: f32,
) -> f32 {
  let reachNow = mix(0.24, reach, clamp(spread, 0.0, 1.0));
  let coords = branchCoords(p, dir, phase - 0.9, 0.40 + spread * 0.92);
  let along = coords.x;
  let normalizedAlong = clamp(along / max(reachNow, 0.001), 0.0, 1.0);
  let cell = fract(normalizedAlong * (7.0 + params.uFineBranching.x * 2.0) + phase * 0.11);
  let beadAxis = abs(cell - 0.5);
  let beadGate = 1.0 - smoothstep(0.17, 0.33, beadAxis);
  let lateralOffset = vec2f(
    sin(normalizedAlong * 29.0 + phase) * width * 0.62,
    cos(normalizedAlong * 23.0 - phase * 0.7) * width * 0.52,
  );
  let beadRadius = length(coords.yz - lateralOffset);
  let beadSize = width * mix(0.24, 0.46, 1.0 - normalizedAlong);
  let bead = 1.0 - smoothstep(beadSize * 0.58, beadSize * 1.18, beadRadius);
  let window = smoothstep(reachNow * 0.16, reachNow * 0.27, along)
    * (1.0 - smoothstep(reachNow * 0.80, reachNow, along));
  return bead * beadGate * window;
}

fn foldedSheet3(
  p: vec3f,
  normal: vec3f,
  phase: f32,
  thickness: f32,
  reach: f32,
  spread: f32,
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
  let fold = (
    sin(u * 12.0 + phase) * 0.034
      + sin(v * 16.1 - phase * 1.2) * 0.026
      + sin((u + v) * 23.0 + phase * 0.43) * 0.014
  ) * (0.45 + spread * 0.90);
  let sheet = 1.0 - smoothstep(thickness * 0.44, thickness * 1.14, abs(plane - fold));
  let radius = length(p);
  let reachNow = mix(0.28, reach, clamp(spread, 0.0, 1.0));
  let window = smoothstep(0.18, 0.31, radius)
    * (1.0 - smoothstep(reachNow * 0.80, reachNow, radius));
  let tear = smoothstep(
    -0.15,
    0.58,
    sin(u * 31.0 + phase * 1.4) + sin(v * 37.0 - phase * 0.7) * 0.48,
  );
  return sheet * window * (0.38 + tear * 0.62);
}

fn densityField(pInput: vec3f) -> VolumeSample {
  var out: VolumeSample;
  out.density = 0.0;
  out.detail = 0.0;
  out.activity = 0.0;

  if (length(pInput) > 1.10) {
    return out;
  }

  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;
  let phase = frame.burstState.x;
  let spread = frame.burstState.y;
  let collapse = frame.burstState.z;
  let eventStrength = frame.burstState.w;
  let active = smoothstep(0.001, 0.03, eventStrength);
  let returnMix = smoothstep(0.62, 0.98, phase) * active;

  let fluid = sampleFluidWorld(pInput);
  let fluidWarpScale = params.uFluidInfluence.x
    * (0.030 + active * (0.075 + clamp(fluid.burst, 0.0, 1.0) * 0.035));
  var p = pInput - fluid.velocity * fluidWarpScale;
  p = crawlWarp(
    p,
    time,
    params.uCoreWobble.x * (0.32 + params.uTurbulence.x * 0.12),
  );

  let radius = max(length(p), 0.001);
  let direction = p / radius;
  let q = rotateVolume(p, time * (0.43 + params.uTurbulence.x * 0.11));
  let coarse = spiralFlow3(
    q * 1.72 + vec3f(0.37, -0.21, 0.13),
    time * (0.38 + params.uTurbulence.x * 0.09),
  );
  let detail = spiralRidged3(
    q * params.uNoiseScale.x,
    time * (0.76 + params.uTurbulence.x * 0.15),
  );
  let fine = clamp(
    0.5
      + (sin(q.x * 17.3 + time * 1.31)
        + sin(q.y * 21.7 - time * 1.13)
        + sin(q.z * 27.1 + time * 0.97)) / 6.0,
    0.0,
    1.0,
  );

  let directionalLobe = (
    sin(direction.x * 3.5 + time * 0.35)
      + sin(direction.y * 4.3 - time * 0.29)
      + sin(direction.z * 5.1 + time * 0.23 + 1.4)
  ) / 3.0;
  let coreRadius = params.uCoreRadius.x
    + (coarse - 0.5) * params.uCoreWobble.x * 1.55
    + directionalLobe * params.uCoreWobble.x * 0.54
    + (audio - 0.5) * params.uAudioInfluence.x * 0.007;
  let surfaceWarp = (detail - 0.5) * params.uCoreDetailStrength.x * 0.116
    + (fine - 0.5) * params.uCoreDetailStrength.x * 0.038;
  let coreEnvelope = 1.0 - smoothstep(
    coreRadius - 0.060,
    coreRadius + 0.066,
    radius - surfaceWarp,
  );
  let porous = smoothstep(
    params.uDetailCutoff.x - 0.18,
    params.uDetailCutoff.x + 0.18,
    detail * 0.70 + fine * 0.30,
  );
  let idleDensity = coreEnvelope * (0.10 + porous * 0.90) * 0.88;

  if (active < 0.001) {
    out.density = max(0.0, idleDensity * params.uDensity.x);
    out.detail = detail * 0.72 + fine * 0.28;
    return out;
  }

  let seed = frame.pointerDelta.w;
  let reach = params.uBurstReach.x;
  let width = params.uBranchWidth.x;
  let d0 = seedDirection(seed, 0.0);
  let d1 = seedDirection(seed, 1.0);
  let d2 = seedDirection(seed, 2.0);
  let d3 = seedDirection(seed, 3.0);
  let d4 = seedDirection(seed, 4.0);

  let b0 = branchBody3(p, d0, seed * 12.1 + 0.7, width, reach, spread, returnMix);
  let b1 = branchBody3(p, d1, seed * 15.3 + 2.1, width * 0.86, reach * 0.95, spread, returnMix);
  let b2 = branchBody3(p, d2, seed * 18.7 - 1.4, width * 0.92, reach * 0.90, spread, returnMix);
  let b3 = branchBody3(p, d3, seed * 21.2 + 3.7, width * 0.72, reach * 0.82, spread, returnMix);
  let b4 = branchBody3(p, d4, seed * 24.5 - 2.9, width * 0.58, reach * 0.76, spread, returnMix);
  let branchVolume = max(
    b0,
    max(b1 * 0.94, max(b2 * 0.88, max(b3 * 0.76, b4 * 0.66))),
  );

  let f0 = filamentTrain3(p, d0, seed * 9.1, width, reach, spread);
  let f1 = filamentTrain3(p, d1, seed * 11.7 + 1.4, width * 0.88, reach * 0.95, spread);
  let f2 = filamentTrain3(p, d2, seed * 14.9 - 2.1, width * 0.80, reach * 0.88, spread);
  let filamentVolume = max(f0, max(f1 * 0.86, f2 * 0.72));

  let m0 = metaballTrain3(p, d0, seed * 7.3 + 0.4, width, reach, spread);
  let m1 = metaballTrain3(p, d1, seed * 10.1 - 1.6, width * 0.90, reach * 0.93, spread);
  let m2 = metaballTrain3(p, d3, seed * 13.9 + 2.7, width * 0.76, reach * 0.80, spread);
  let linkedFragments = max(m0, max(m1 * 0.88, m2 * 0.74));

  let sheet0 = foldedSheet3(p, d1, seed * 9.7 + 1.2, width * 0.34, reach * 0.97, spread);
  let sheet1 = foldedSheet3(p, d3, seed * 13.4 - 2.0, width * 0.29, reach * 0.87, spread);
  let sheets = max(sheet0, sheet1 * 0.82) * params.uSheetStrength.x;

  let burstTexture = smoothstep(
    params.uDetailCutoff.x - 0.27,
    params.uDetailCutoff.x + 0.13,
    detail * 0.61 + fine * 0.39,
  );
  let branchMask = max(branchVolume, max(sheets * 0.82, filamentVolume * 0.88));
  let fineStructure = filamentVolume * params.uFineBranching.x
    + linkedFragments * params.uFragmentStrength.x;

  let coreDensity = idleDensity * (1.0 - collapse);
  let structureStrength = eventStrength
    * params.uBurstVisualStrength.x
    * (0.48 + spread * 0.72)
    * (1.0 - returnMix * 0.18);
  let structural = (
    branchVolume
      + sheets
      + fineStructure * 0.74
  ) * structureStrength * (0.34 + burstTexture * 0.92);

  let trailGate = branchMask
    * (0.42 + filamentVolume * 0.58)
    * (1.0 - smoothstep(0.90, 1.10, radius));
  let smokeTrail = clamp(fluid.dye, 0.0, 1.2)
    * trailGate
    * eventStrength
    * 0.10;

  out.density = max(
    0.0,
    (coreDensity + structural + smokeTrail) * params.uDensity.x,
  );
  out.detail = clamp(
    burstTexture * 0.50
      + branchVolume * 0.28
      + filamentVolume * 0.22,
    0.0,
    1.0,
  );
  out.activity = active;
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

  let hit = intersectSphere(ro, rd, 1.11);
  var background = mix(
    vec3f(0.007, 0.010, 0.017),
    vec3f(0.030, 0.047, 0.070),
    in.uv.y,
  );
  let vignette = 1.0 - 0.22 * dot(screen * 0.48, screen * 0.48);
  background *= max(vignette, 0.58);

  var color = background;
  if (hit.y > max(hit.x, 0.0)) {
    let steps = clamp(i32(params.uSteps.x), 36, 152);
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

    for (var i = 0; i < 152; i += 1) {
      if (i >= steps) {
        break;
      }
      let p = ro + rd * t;
      if (length(p) < 1.10) {
        let sample = densityField(p);
        if (sample.density > 0.0018) {
          let q = crawlWarp(
            rotateVolume(p, time * 0.19),
            time,
            params.uCoreWobble.x * 0.16,
          );
          let normalPerturbation = vec3f(
            sin(q.y * 8.3 + time * 0.57),
            sin(q.z * 9.1 - time * 0.51),
            sin(q.x * 8.7 + time * 0.43 + 1.2),
          ) * params.uCoreDetailStrength.x * 0.090;
          let outward = normalize(p + normalPerturbation + vec3f(0.0001));
          let directional = clamp(dot(outward, lightDir) * 0.5 + 0.5, 0.0, 1.0);
          let localShadow = exp(-sample.density * params.uShadow.x * 0.27);
          let detailLight = 0.70 + sample.detail * 0.44;
          let light = (0.17 + 0.83 * directional * localShadow) * detailLight;
          let rim = pow(1.0 - abs(dot(outward, -rd)), 2.35);
          let burstGlow = clamp(frame.burstState.w * 0.28 + frame.pointer.w * 0.08, 0.0, 1.0);
          let sampleColor = gasColor * (
            light
              + rim * (0.13 + sample.activity * 0.10)
              + sample.detail * sample.activity * 0.045
              + burstGlow * 0.018
          );
          let alpha = 1.0 - exp(-sample.density * params.uAbsorption.x * stepLength);
          scattering += transmittance * alpha * sampleColor;
          transmittance *= 1.0 - alpha;
          if (transmittance < 0.018) {
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

    "uDensity": { "type": "float", "default": 0.72, "min": 0.1, "max": 3.0, "step": 0.01, "label": { "zh": "气体密度", "en": "Gas Density" }, "group": { "zh": "体积", "en": "Volume" } },
    "uAbsorption": { "type": "float", "default": 1.30, "min": 0.2, "max": 8.0, "step": 0.01, "label": { "zh": "吸收", "en": "Absorption" }, "group": { "zh": "体积", "en": "Volume" } },

    "uCoreRadius": { "type": "float", "default": 0.39, "min": 0.25, "max": 0.65, "step": 0.005, "label": { "zh": "核心半径", "en": "Core Radius" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uCoreWobble": { "type": "float", "default": 0.15, "min": 0.0, "max": 0.30, "step": 0.005, "label": { "zh": "核心蠕动", "en": "Core Wobble" }, "description": { "zh": "连续三维域形变，控制未爆裂时的明显蠕动。", "en": "Continuous 3D domain deformation controlling visible idle crawling." }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uCoreDetailStrength": { "type": "float", "default": 1.20, "min": 0.0, "max": 2.2, "step": 0.01, "label": { "zh": "表面细节", "en": "Surface Detail" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uNoiseScale": { "type": "float", "default": 4.2, "min": 1.0, "max": 9.0, "step": 0.02, "label": { "zh": "分形细节尺度", "en": "Fractal Detail Scale" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uDetailCutoff": { "type": "float", "default": 0.56, "min": 0.18, "max": 0.84, "step": 0.01, "label": { "zh": "内部疏松度", "en": "Internal Porosity" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uTurbulence": { "type": "float", "default": 1.12, "min": 0.0, "max": 2.8, "step": 0.01, "label": { "zh": "翻涌速度", "en": "Rolling Speed" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uExpansion": { "type": "float", "default": 0.10, "min": 0.0, "max": 1.5, "step": 0.01, "label": { "zh": "呼吸扩张", "en": "Breathing Expansion" }, "group": { "zh": "核心形态", "en": "Core Shape" } },

    "uFluidInfluence": { "type": "float", "default": 1.52, "min": 0.0, "max": 3.5, "step": 0.01, "label": { "zh": "流体形变", "en": "Fluid Deformation" }, "description": { "zh": "二维速度场只扭曲三维主干，不直接增加整体密度。", "en": "The 2D velocity field deforms 3D branches without directly filling the volume." }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uAdvection": { "type": "float", "default": 1.08, "min": 0.1, "max": 2.0, "step": 0.01, "label": { "zh": "平流速度", "en": "Advection" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uViscosity": { "type": "float", "default": 0.08, "min": 0.0, "max": 1.0, "step": 0.01, "label": { "zh": "粘性", "en": "Viscosity" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uVorticity": { "type": "float", "default": 1.18, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "涡量保持", "en": "Vorticity" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uVelocityDissipation": { "type": "float", "default": 0.52, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "速度耗散", "en": "Velocity Dissipation" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uDyeDissipation": { "type": "float", "default": 0.78, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "烟雾耗散", "en": "Smoke Dissipation" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uBurstFieldDissipation": { "type": "float", "default": 1.35, "min": 0.1, "max": 4.0, "step": 0.01, "label": { "zh": "爆裂记忆耗散", "en": "Burst Memory Dissipation" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uSolverSubsteps": { "type": "int", "default": 2, "min": 1, "max": 4, "step": 1, "label": { "zh": "解算子步", "en": "Solver Substeps" }, "group": { "zh": "二维解算", "en": "2D Solver" } },

    "uClickBurstStrength": { "type": "float", "default": 1.25, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "点击爆裂强度", "en": "Click Burst Strength" }, "group": { "zh": "爆裂", "en": "Burst" } },
    "uBurstDuration": { "type": "float", "default": 1.55, "min": 0.45, "max": 4.0, "step": 0.01, "label": { "zh": "爆裂周期", "en": "Burst Cycle" }, "description": { "zh": "完整的展开、最大形变和弹性回收周期。", "en": "Full expansion, peak deformation, and elastic return cycle." }, "group": { "zh": "爆裂", "en": "Burst" } },
    "uElasticity": { "type": "float", "default": 1.0, "min": 0.0, "max": 2.0, "step": 0.01, "label": { "zh": "回弹弹性", "en": "Return Elasticity" }, "description": { "zh": "控制回收阶段的轻微过冲与弹性融合感。", "en": "Controls slight overshoot and elastic fusion during the return stage." }, "group": { "zh": "爆裂", "en": "Burst" } },
    "uBurstForce": { "type": "float", "default": 2.48, "min": 0.0, "max": 5.0, "step": 0.01, "label": { "zh": "爆裂推力", "en": "Burst Force" }, "group": { "zh": "爆裂", "en": "Burst" } },
    "uBurstDensity": { "type": "float", "default": 0.82, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "二维烟雾注入", "en": "2D Smoke Injection" }, "group": { "zh": "爆裂", "en": "Burst" } },
    "uBurstVisualStrength": { "type": "float", "default": 1.20, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "爆裂结构强度", "en": "Burst Structure Strength" }, "group": { "zh": "爆裂", "en": "Burst" } },
    "uFractalBranches": { "type": "float", "default": 6.8, "min": 3.0, "max": 10.0, "step": 0.1, "label": { "zh": "二维分形复杂度", "en": "2D Fractal Complexity" }, "group": { "zh": "爆裂", "en": "Burst" } },
    "uBranchSharpness": { "type": "float", "default": 3.8, "min": 1.0, "max": 7.0, "step": 0.1, "label": { "zh": "二维分支锐度", "en": "2D Branch Sharpness" }, "group": { "zh": "爆裂", "en": "Burst" } },
    "uBurstReach": { "type": "float", "default": 0.96, "min": 0.50, "max": 1.10, "step": 0.01, "label": { "zh": "爆裂范围", "en": "Burst Reach" }, "group": { "zh": "爆裂", "en": "Burst" } },
    "uBranchWidth": { "type": "float", "default": 0.044, "min": 0.016, "max": 0.14, "step": 0.002, "label": { "zh": "主干宽度", "en": "Branch Width" }, "group": { "zh": "爆裂", "en": "Burst" } },
    "uSheetStrength": { "type": "float", "default": 0.70, "min": 0.0, "max": 2.0, "step": 0.01, "label": { "zh": "褶皱薄片", "en": "Folded Sheets" }, "group": { "zh": "爆裂", "en": "Burst" } },
    "uFineBranching": { "type": "float", "default": 1.10, "min": 0.0, "max": 2.5, "step": 0.01, "label": { "zh": "次级分叉", "en": "Secondary Branching" }, "description": { "zh": "沿主干生成相关联的细丝和次级分叉，而不是独立随机碎片。", "en": "Generates linked filaments and secondary splits along the main branches instead of unrelated random fragments." }, "group": { "zh": "爆裂", "en": "Burst" } },
    "uFragmentStrength": { "type": "float", "default": 1.0, "min": 0.0, "max": 2.5, "step": 0.01, "label": { "zh": "主干微团", "en": "Linked Metaballs" }, "description": { "zh": "沿分形主干排列的小体积微团，随主干一起展开和融合。", "en": "Small metaball-like volumes arranged along the fractal trunks, expanding and merging with them." }, "group": { "zh": "爆裂", "en": "Burst" } },

    "uAudioPaused": { "type": "boolean", "default": false, "label": { "zh": "暂停音乐", "en": "Pause Audio" }, "description": { "zh": "暂停音频驱动、自动节拍爆裂和波形运动；鼠标点击仍有效。", "en": "Pauses audio drive, automatic beat bursts and waveform motion; pointer bursts remain active." }, "group": { "zh": "音频", "en": "Audio" } },
    "uAudioBurstEnabled": { "type": "boolean", "default": true, "label": { "zh": "音频触发爆裂", "en": "Audio Burst Trigger" }, "group": { "zh": "音频", "en": "Audio" } },
    "uAudioBurstStrength": { "type": "float", "default": 0.74, "min": 0.0, "max": 2.5, "step": 0.01, "label": { "zh": "音频爆裂强度", "en": "Audio Burst Strength" }, "group": { "zh": "音频", "en": "Audio" } },
    "uBeatThreshold": { "type": "float", "default": 0.72, "min": 0.45, "max": 0.95, "step": 0.01, "label": { "zh": "节拍阈值", "en": "Beat Threshold" }, "group": { "zh": "音频", "en": "Audio" } },
    "uBeatCooldown": { "type": "float", "default": 1.05, "min": 0.2, "max": 3.0, "step": 0.01, "label": { "zh": "节拍冷却", "en": "Beat Cooldown" }, "group": { "zh": "音频", "en": "Audio" } },
    "uAudioInfluence": { "type": "float", "default": 0.58, "min": 0.0, "max": 2.5, "step": 0.01, "label": { "zh": "音频呼吸", "en": "Audio Breathing" }, "group": { "zh": "音频", "en": "Audio" } },

    "uSteps": { "type": "int", "default": 88, "min": 36, "max": 152, "step": 1, "label": { "zh": "光线步数", "en": "Ray Steps" }, "group": { "zh": "采样", "en": "Sampling" } },
    "uJitter": { "type": "float", "default": 0.22, "min": 0.0, "max": 1.0, "step": 0.01, "label": { "zh": "采样抖动", "en": "Jitter" }, "group": { "zh": "采样", "en": "Sampling" } },
    "uShadow": { "type": "float", "default": 1.18, "min": 0.0, "max": 4.0, "step": 0.01, "label": { "zh": "局部阴影", "en": "Local Shadow" }, "group": { "zh": "光照", "en": "Lighting" } },
    "uGasColor": { "type": "color", "default": "#789dd0", "label": { "zh": "气体颜色", "en": "Gas Color" }, "group": { "zh": "外观", "en": "Appearance" } },
    "uWaveColor": { "type": "color", "default": "#55d8ff", "label": { "zh": "波形颜色", "en": "Wave Color" }, "group": { "zh": "外观", "en": "Appearance" } },
    "uUncappedBenchmark": { "type": "boolean", "default": false, "label": { "zh": "取消帧率限制", "en": "Uncapped Benchmark" }, "group": { "zh": "性能", "en": "Performance" } }
  }
}
@endshaderlab */
