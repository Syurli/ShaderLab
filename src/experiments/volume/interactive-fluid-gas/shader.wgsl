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

fn branchBand2(p: vec2f, dir: vec2f, phase: f32, width: f32) -> f32 {
  let sideAxis = vec2f(-dir.y, dir.x);
  let along = dot(p, dir);
  let bentSide = dot(p, sideAxis)
    + sin(along * 14.0 + phase) * 0.030
    + sin(along * 29.0 - phase * 1.31) * 0.011;
  let ridge = exp(-abs(bentSide) / max(width, 0.006));
  let window = smoothstep(-0.02, 0.07, along)
    * (1.0 - smoothstep(0.28, 0.56, along));
  return ridge * window;
}

fn branchPattern2(p: vec2f, seed: f32, complexity: f32, sharpness: f32) -> f32 {
  let a = seed * 6.28318530718;
  let d0 = vec2f(cos(a), sin(a));
  let d1 = vec2f(cos(a + 2.07), sin(a + 2.07));
  let d2 = vec2f(cos(a - 2.51), sin(a - 2.51));
  let baseWidth = mix(0.052, 0.022, clamp(sharpness / 7.0, 0.0, 1.0));
  let bands = max(
    branchBand2(p, d0, seed * 8.2, baseWidth),
    max(
      branchBand2(p, d1, seed * 12.7 + 1.3, baseWidth * 0.82) * 0.88,
      branchBand2(p, d2, seed * 17.1 - 2.0, baseWidth * 0.70) * 0.76,
    ),
  );

  var q = p * (8.5 + complexity * 0.75);
  var ridge = 0.0;
  var amp = 0.58;
  var freq = 1.0;
  for (var i = 0; i < 3; i += 1) {
    let wave = abs(
      sin(q.y * freq + seed * 5.3)
        + cos(q.x * freq - seed * 3.9)
    ) * 0.5;
    ridge += pow(max(0.0, 1.0 - wave), 1.15 + sharpness * 0.22) * amp;
    q = rotate2(q, 0.57 + seed * 0.19 + f32(i) * 0.17);
    freq *= 1.76;
    amp *= 0.51;
  }
  return clamp(max(bands, ridge * 0.70), 0.0, 1.45);
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
    clamp(params.uViscosity.x * dt * 7.0, 0.0, 0.28),
  );

  let curl = (right.y - left.y) - (up.x - down.x);
  velocity += vec2f(-velocity.y, velocity.x)
    * curl
    * params.uVorticity.x
    * dt
    * 3.0;

  let centerDelta = uv - vec2f(0.5);
  let centerRadius = max(length(centerDelta), 0.001);
  let radial = centerDelta / centerRadius;
  let centerFalloff = exp(-centerRadius * 6.0);
  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;

  // Several low-frequency cartesian cells make the idle core crawl instead of rotate.
  let cellA = vec2f(
    sin(uv.y * 13.1 + time * 0.74) + sin(uv.x * 7.7 - time * 0.49) * 0.55,
    cos(uv.x * 11.9 - time * 0.63) - cos(uv.y * 8.3 + time * 0.42) * 0.52,
  );
  let cellB = vec2f(
    sin((uv.x + uv.y) * 18.7 - time * 0.88),
    cos((uv.x - uv.y) * 16.3 + time * 0.79),
  );
  velocity += (cellA * 0.74 + cellB * 0.26)
    * centerFalloff
    * params.uTurbulence.x
    * dt
    * (0.024 + audio * 0.008);
  velocity -= centerDelta * centerFalloff * dt * 0.018;
  velocity += radial
    * centerFalloff
    * params.uExpansion.x
    * sin(time * 1.37 + centerRadius * 17.0)
    * dt
    * 0.010;
  dye += centerFalloff * (0.006 + audio * 0.004) * dt;

  let burstAmplitude = frame.pointer.z;
  if (burstAmplitude > 0.0005) {
    let seed = frame.pointerDelta.w;
    let pattern = branchPattern2(
      centerDelta,
      seed,
      clamp(params.uFractalBranches.x, 3.0, 10.0),
      clamp(params.uBranchSharpness.x, 1.0, 7.0),
    );

    let targetVector = frame.pointerDelta.xy - vec2f(0.5);
    let targetDirection = targetVector / max(length(targetVector), 0.001);
    let directionBias = 0.52
      + 0.48 * smoothstep(-0.78, 0.86, dot(radial, targetDirection));
    let radialEnvelope = exp(-centerRadius * 2.05);
    let source = burstAmplitude
      * radialEnvelope
      * directionBias
      * (0.12 + pattern * 1.72);

    let pushDirection = normalize(
      radial * 0.66 + targetDirection * 0.34 + vec2f(0.0001)
    );
    velocity += pushDirection
      * source
      * params.uBurstForce.x
      * dt
      * 13.8;

    let perpendicular = vec2f(-targetDirection.y, targetDirection.x);
    velocity += perpendicular
      * sin(dot(centerDelta, perpendicular) * 39.0 + seed * 17.0)
      * source
      * params.uBurstForce.x
      * dt
      * 0.92;

    let coreBlast = exp(-dot(centerDelta, centerDelta) / 0.015);
    velocity += radial
      * coreBlast
      * burstAmplitude
      * params.uBurstForce.x
      * dt
      * 5.8;

    dye += source * params.uBurstDensity.x * dt * 2.8;
    burstField += source * dt * 8.4;
  }

  let speed = length(velocity);
  if (speed > 2.9) {
    velocity *= 2.9 / speed;
  }

  let index = gid.y * FLUID_SIZE + gid.x;
  fluidOut.cells[index] = vec4f(
    velocity,
    clamp(dye, 0.0, 2.2),
    clamp(burstField, 0.0, 2.8),
  );
}

fn hash31(p: vec3f) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + vec3f(33.33));
  return fract((q.x + q.y) * q.z);
}

fn hash11(x: f32) -> f32 {
  return fract(sin(x * 127.1 + 311.7) * 43758.5453123);
}

fn rotateVolume(pInput: vec3f, time: f32) -> vec3f {
  var p = pInput;
  let xz = rotate2(vec2f(p.x, p.z), time * 0.17 + 0.23);
  p = vec3f(xz.x, p.y, xz.y);
  let yz = rotate2(vec2f(p.y, p.z), -time * 0.11 + 0.41);
  return vec3f(p.x, yz.x, yz.y);
}

fn crawlWarp(p: vec3f, time: f32, amount: f32) -> vec3f {
  let w = vec3f(
    sin(p.y * 3.7 + p.z * 2.1 + time * 0.83),
    sin(p.z * 3.1 - p.x * 2.8 - time * 0.71 + 1.7),
    sin(p.x * 3.4 + p.y * 2.5 + time * 0.67 + 3.1),
  );
  let w2 = vec3f(
    sin(p.z * 7.3 - time * 1.11),
    cos(p.x * 6.7 + time * 0.91),
    sin(p.y * 7.9 + time * 0.77),
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
    frequency *= 1.71;
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

  let xy = sampleFluidNearest(p.xy * 0.47 + vec2f(0.5));
  let yz = sampleFluidNearest(p.yz * 0.47 + vec2f(0.5));
  let zx = sampleFluidNearest(vec2f(p.z, p.x) * 0.47 + vec2f(0.5));

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
  let z = sin(a * 1.731 + offset * 0.83) * 0.70;
  let planar = sqrt(max(0.05, 1.0 - z * z));
  return normalize(vec3f(cos(a) * planar, z, sin(a) * planar));
}

fn branchTube3(p: vec3f, dir: vec3f, phase: f32, width: f32, reach: f32) -> f32 {
  var referenceAxis = vec3f(0.0, 1.0, 0.0);
  if (abs(dir.y) > 0.82) {
    referenceAxis = vec3f(1.0, 0.0, 0.0);
  }
  let sideA = normalize(cross(dir, referenceAxis));
  let sideB = normalize(cross(dir, sideA));
  let along = dot(p, dir);
  let bendA = sin(along * 9.7 + phase) * 0.052
    + sin(along * 21.0 - phase * 0.71) * 0.021;
  let bendB = cos(along * 7.9 - phase * 0.83) * 0.043
    + sin(along * 15.0 + phase * 1.31) * 0.016;
  let side = vec2f(
    dot(p, sideA) - bendA,
    dot(p, sideB) - bendB,
  );
  let tube = 1.0 - smoothstep(width * 0.72, width * 1.42, length(side));
  let window = smoothstep(0.075, 0.20, along)
    * (1.0 - smoothstep(reach * 0.82, reach, along));
  return tube * window;
}

fn foldedSheet3(p: vec3f, normal: vec3f, phase: f32, thickness: f32, reach: f32) -> f32 {
  var referenceAxis = vec3f(0.0, 1.0, 0.0);
  if (abs(normal.y) > 0.82) {
    referenceAxis = vec3f(1.0, 0.0, 0.0);
  }
  let tangentA = normalize(cross(normal, referenceAxis));
  let tangentB = normalize(cross(normal, tangentA));
  let u = dot(p, tangentA);
  let v = dot(p, tangentB);
  let plane = dot(p, normal);
  let fold = sin(u * 11.0 + phase) * 0.036
    + sin(v * 14.9 - phase * 1.2) * 0.028
    + sin((u + v) * 21.0 + phase * 0.43) * 0.015;
  let sheet = 1.0 - smoothstep(
    thickness * 0.58,
    thickness * 1.55,
    abs(plane - fold),
  );
  let radius = length(p);
  let window = smoothstep(0.23, 0.36, radius)
    * (1.0 - smoothstep(reach * 0.84, reach, radius));
  return sheet * window;
}

fn fragmentParticleField(p: vec3f, seed: f32, activity: f32, reach: f32) -> f32 {
  var field = 0.0;
  for (var i = 0; i < 10; i += 1) {
    let fi = f32(i);
    let h0 = hash11(seed * 41.7 + fi * 13.1 + 0.7);
    let h1 = hash11(seed * 63.3 + fi * 19.7 + 2.1);
    let h2 = hash11(seed * 87.1 + fi * 7.9 + 4.3);
    let dir = seedDirection(seed + h0 * 0.31, fi * 0.73 + h1);
    var sideAxis = cross(dir, vec3f(0.0, 1.0, 0.0));
    if (length(sideAxis) < 0.08) {
      sideAxis = cross(dir, vec3f(1.0, 0.0, 0.0));
    }
    sideAxis = normalize(sideAxis);
    let spread = mix(0.20, reach * 0.88, h0) * (0.48 + activity * 0.52);
    let sideOffset = (h1 - 0.5) * 0.19 * activity;
    let upOffset = (h2 - 0.5) * 0.13 * activity;
    let center = dir * spread
      + sideAxis * sideOffset
      + vec3f(0.0, upOffset, 0.0);
    let radius = mix(0.020, 0.060, h2) * params.uFragmentScale.x;
    let d = length(p - center);
    let blob = 1.0 - smoothstep(radius * 0.62, radius * 1.45, d);
    field += blob * mix(0.52, 1.0, h1);
  }
  return smoothstep(0.22, 0.84, field);
}

fn densityField(pInput: vec3f) -> f32 {
  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;
  let inputRadius = length(pInput);
  if (inputRadius > 1.08) {
    return 0.0;
  }

  let fluid = sampleFluidWorld(pInput);
  let burstLocal = clamp(
    fluid.burst * params.uBurstVisualStrength.x + frame.pointer.z * 0.30,
    0.0,
    1.8,
  );
  let activity = smoothstep(0.018, 0.34, burstLocal);
  let coreCollapse = smoothstep(
    0.035,
    0.24,
    frame.pointer.z * 0.95 + min(fluid.burst, 0.9) * 0.28,
  );

  var p = pInput - fluid.velocity
    * params.uFluidInfluence.x
    * (0.048 + activity * 0.115);
  p = crawlWarp(
    p,
    time,
    params.uCoreWobble.x * (0.26 + params.uTurbulence.x * 0.10),
  );
  let radius = max(length(p), 0.001);
  let direction = p / radius;

  let q = rotateVolume(p, time * (0.41 + params.uTurbulence.x * 0.12));
  let coarse = spiralFlow3(
    q * 1.66 + vec3f(0.37, -0.21, 0.13),
    time * (0.34 + params.uTurbulence.x * 0.09),
  );
  let detail = spiralRidged3(
    q * params.uNoiseScale.x,
    time * (0.70 + params.uTurbulence.x * 0.15),
  );
  let fine = clamp(
    0.5
      + (sin(q.x * 14.3 + time * 1.21)
        + sin(q.y * 17.7 - time * 1.07)
        + sin(q.z * 21.1 + time * 0.89)) / 6.0,
    0.0,
    1.0,
  );

  let directionalLobe = (
    sin(direction.x * 3.3 + time * 0.31)
      + sin(direction.y * 4.1 - time * 0.27)
      + sin(direction.z * 4.7 + time * 0.19 + 1.4)
  ) / 3.0;
  let coreRadius = params.uCoreRadius.x
    + (coarse - 0.5) * params.uCoreWobble.x * 1.42
    + directionalLobe * params.uCoreWobble.x * 0.46
    + (audio - 0.5) * params.uAudioInfluence.x * 0.008;
  let surfaceWarp = (detail - 0.5) * params.uCoreDetailStrength.x * 0.105
    + (fine - 0.5) * params.uCoreDetailStrength.x * 0.032;
  let coreEnvelope = 1.0 - smoothstep(
    coreRadius - 0.070,
    coreRadius + 0.080,
    radius - surfaceWarp,
  );
  let porous = smoothstep(
    params.uDetailCutoff.x - 0.20,
    params.uDetailCutoff.x + 0.20,
    detail * 0.72 + fine * 0.28,
  );
  let coreTexture = 0.18 + porous * 0.82;
  let idleDensity = coreEnvelope * coreTexture * 0.92;

  if (activity < 0.001 && coreCollapse < 0.001) {
    return max(0.0, idleDensity * params.uDensity.x);
  }

  let seed = frame.pointerDelta.w;
  let reach = params.uBurstReach.x;
  let width = params.uBranchWidth.x;
  let d0 = seedDirection(seed, 0.0);
  let d1 = seedDirection(seed, 1.0);
  let d2 = seedDirection(seed, 2.0);
  let d3 = seedDirection(seed, 3.0);
  let d4 = seedDirection(seed, 4.0);

  let tube0 = branchTube3(p, d0, seed * 12.1 + 0.7, width, reach);
  let tube1 = branchTube3(p, d1, seed * 15.3 + 2.1, width * 0.80, reach * 0.94);
  let tube2 = branchTube3(p, d2, seed * 18.7 - 1.4, width * 0.92, reach * 0.88);
  let tube3 = branchTube3(p, d3, seed * 21.2 + 3.7, width * 0.60, reach * 0.81);
  let tube4 = branchTube3(p, d4, seed * 24.5 - 2.9, width * 0.48, reach * 0.74);
  let branchVolume = max(
    tube0,
    max(tube1 * 0.94, max(tube2 * 0.86, max(tube3 * 0.72, tube4 * 0.62))),
  );

  let sheet0 = foldedSheet3(p, d1, seed * 9.7 + 1.2, width * 0.40, reach * 0.96);
  let sheet1 = foldedSheet3(p, d3, seed * 13.4 - 2.0, width * 0.32, reach * 0.86);
  let sheets = max(sheet0, sheet1 * 0.84) * params.uSheetStrength.x;

  let fragments = fragmentParticleField(p, seed, activity, reach)
    * params.uFragmentStrength.x;

  // Once the burst opens, the intact sphere disappears. Only sparse irregular remnants
  // survive in the center, so no spherical contour remains behind the exploded shapes.
  let residualMask = smoothstep(
    0.62,
    0.88,
    detail * 0.72 + fine * 0.28,
  ) * (0.35 + 0.65 * coarse);
  let intactCore = idleDensity * (1.0 - coreCollapse);
  let shatteredCore = idleDensity
    * residualMask
    * coreCollapse
    * params.uCoreRemnant.x
    * (1.0 - smoothstep(0.34, params.uCoreRadius.x + 0.15, radius));
  let coreDensity = intactCore + shatteredCore;

  let burstTexture = smoothstep(
    params.uDetailCutoff.x - 0.24,
    params.uDetailCutoff.x + 0.16,
    detail * 0.66 + fine * 0.34,
  );
  let structural = activity
    * (branchVolume + sheets + fragments * 0.88)
    * (0.42 + burstTexture * 0.78)
    * (0.58 + burstLocal * 0.76);
  let smokeTrail = clamp(fluid.dye, 0.0, 1.7)
    * activity
    * (1.0 - smoothstep(0.68, 1.05, radius))
    * (0.035 + detail * 0.090);

  return max(
    0.0,
    (coreDensity + structural + smokeTrail) * params.uDensity.x,
  );
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

  let hit = intersectSphere(ro, rd, 1.09);
  var background = mix(
    vec3f(0.007, 0.010, 0.017),
    vec3f(0.030, 0.047, 0.070),
    in.uv.y,
  );
  let vignette = 1.0 - 0.22 * dot(screen * 0.48, screen * 0.48);
  background *= max(vignette, 0.58);

  var color = background;
  if (hit.y > max(hit.x, 0.0)) {
    let steps = clamp(i32(params.uSteps.x), 32, 140);
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

    for (var i = 0; i < 140; i += 1) {
      if (i >= steps) {
        break;
      }
      let p = ro + rd * t;
      if (length(p) < 1.08) {
        let density = densityField(p);
        if (density > 0.0025) {
          let q = crawlWarp(
            rotateVolume(p, time * 0.19),
            time,
            params.uCoreWobble.x * 0.18,
          );
          let normalPerturbation = vec3f(
            sin(q.y * 7.3 + time * 0.51),
            sin(q.z * 8.1 - time * 0.47),
            sin(q.x * 7.7 + time * 0.39 + 1.2),
          ) * params.uCoreDetailStrength.x * 0.082;
          let outward = normalize(p + normalPerturbation + vec3f(0.0001));
          let directional = clamp(dot(outward, lightDir) * 0.5 + 0.5, 0.0, 1.0);
          let localShadow = exp(-density * params.uShadow.x * 0.31);
          let light = 0.20 + 0.80 * directional * localShadow;
          let rim = pow(1.0 - abs(dot(outward, -rd)), 2.2);
          let burstGlow = clamp(frame.pointer.z + frame.pointer.w * 0.10, 0.0, 1.2);
          let sampleColor = gasColor * (
            light + rim * (0.17 + burstGlow * 0.07) + burstGlow * 0.022
          );
          let alpha = 1.0 - exp(
            -density * params.uAbsorption.x * stepLength
          );
          scattering += transmittance * alpha * sampleColor;
          transmittance *= 1.0 - alpha;
          if (transmittance < 0.022) {
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
  let baseline = exp(
    -abs(screen.y + 0.79) * max(resolution.y, 1.0) * 0.16
  ) * 0.10;
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
      "description": { "zh": "绕世界空间体积水平环绕。", "en": "Horizontal orbit around the world-space volume." },
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
      "description": { "zh": "自动水平环绕速度。", "en": "Automatic yaw orbit speed." },
      "group": { "zh": "相机", "en": "Camera" }
    },
    "uDensity": {
      "type": "float", "default": 0.78, "min": 0.1, "max": 3.0, "step": 0.01,
      "label": { "zh": "气体密度", "en": "Gas Density" },
      "description": { "zh": "整体体积密度。", "en": "Overall volume density." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uAbsorption": {
      "type": "float", "default": 1.52, "min": 0.2, "max": 8.0, "step": 0.01,
      "label": { "zh": "吸收", "en": "Absorption" },
      "description": { "zh": "Beer-Lambert 吸收强度。", "en": "Beer-Lambert absorption strength." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uCoreRadius": {
      "type": "float", "default": 0.40, "min": 0.25, "max": 0.65, "step": 0.005,
      "label": { "zh": "核心半径", "en": "Core Radius" },
      "description": { "zh": "平静状态的基础核心尺寸。", "en": "Base size of the idle core." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uCoreWobble": {
      "type": "float", "default": 0.135, "min": 0.0, "max": 0.28, "step": 0.005,
      "label": { "zh": "核心蠕动", "en": "Core Wobble" },
      "description": { "zh": "三维连续域形变强度；默认值强化可见的蠕动和翻涌。", "en": "Continuous 3D domain deformation; the default makes crawling and rolling clearly visible." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uCoreDetailStrength": {
      "type": "float", "default": 1.05, "min": 0.0, "max": 2.0, "step": 0.01,
      "label": { "zh": "表面细节", "en": "Surface Detail" },
      "description": { "zh": "连续 3D ridged 细节对边界和光照的影响。", "en": "Continuous 3D ridged detail on the boundary and lighting." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uNoiseScale": {
      "type": "float", "default": 3.7, "min": 1.0, "max": 8.0, "step": 0.02,
      "label": { "zh": "分形细节尺度", "en": "Fractal Detail Scale" },
      "description": { "zh": "三维连续 ridged noise 的空间频率。", "en": "Spatial frequency of the seamless 3D ridged noise." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uDetailCutoff": {
      "type": "float", "default": 0.54, "min": 0.18, "max": 0.82, "step": 0.01,
      "label": { "zh": "内部疏松度", "en": "Internal Porosity" },
      "description": { "zh": "提高后会削弱低分形密度区域，使核心不再像实心球。", "en": "Suppresses low-fractal-density regions so the core reads less like a solid sphere." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uTurbulence": {
      "type": "float", "default": 1.05, "min": 0.0, "max": 2.8, "step": 0.01,
      "label": { "zh": "翻涌速度", "en": "Rolling Speed" },
      "description": { "zh": "控制平静核心的持续蠕动速度。", "en": "Controls continuous crawling speed of the idle core." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uExpansion": {
      "type": "float", "default": 0.18, "min": 0.0, "max": 1.5, "step": 0.01,
      "label": { "zh": "呼吸扩张", "en": "Breathing Expansion" },
      "description": { "zh": "弱呼吸运动，不持续放大主体。", "en": "Subtle breathing without continuous inflation." },
      "group": { "zh": "核心形态", "en": "Core Shape" }
    },
    "uFluidInfluence": {
      "type": "float", "default": 1.42, "min": 0.0, "max": 3.5, "step": 0.01,
      "label": { "zh": "流体形变", "en": "Fluid Deformation" },
      "description": { "zh": "二维场通过三平面采样形变三维密度。", "en": "Tri-planar lifting of the 2D field into 3D density deformation." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uAdvection": {
      "type": "float", "default": 1.08, "min": 0.1, "max": 2.0, "step": 0.01,
      "label": { "zh": "平流速度", "en": "Advection" },
      "description": { "zh": "半拉格朗日平流回溯距离。", "en": "Semi-Lagrangian backtrace distance." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uViscosity": {
      "type": "float", "default": 0.11, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "粘性", "en": "Viscosity" },
      "description": { "zh": "速度场邻域平滑。", "en": "Neighborhood smoothing of the velocity field." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uVorticity": {
      "type": "float", "default": 1.05, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "涡量保持", "en": "Vorticity" },
      "description": { "zh": "保持爆裂后的局部卷曲。", "en": "Preserves local curls after a burst." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uVelocityDissipation": {
      "type": "float", "default": 0.42, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "速度耗散", "en": "Velocity Dissipation" },
      "description": { "zh": "二维速度场衰减。", "en": "2D velocity-field decay." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uDyeDissipation": {
      "type": "float", "default": 0.44, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "烟雾耗散", "en": "Smoke Dissipation" },
      "description": { "zh": "二维烟雾辅助场衰减。", "en": "2D smoke helper-field decay." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uBurstFieldDissipation": {
      "type": "float", "default": 0.92, "min": 0.1, "max": 4.0, "step": 0.01,
      "label": { "zh": "爆裂记忆耗散", "en": "Burst Memory Dissipation" },
      "description": { "zh": "爆裂结构重新聚合的速度。", "en": "How quickly burst memory decays and the core reforms." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uSolverSubsteps": {
      "type": "int", "default": 2, "min": 1, "max": 4, "step": 1,
      "label": { "zh": "解算子步", "en": "Solver Substeps" },
      "description": { "zh": "每帧二维解算子步数。", "en": "2D solver substeps per frame." },
      "group": { "zh": "二维解算", "en": "2D Solver" }
    },
    "uClickBurstStrength": {
      "type": "float", "default": 1.30, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "点击爆裂强度", "en": "Click Burst Strength" },
      "description": { "zh": "鼠标按下触发的一次性爆裂强度。", "en": "One-shot burst strength on pointer down." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstDuration": {
      "type": "float", "default": 0.98, "min": 0.15, "max": 2.5, "step": 0.01,
      "label": { "zh": "注入持续时间", "en": "Injection Duration" },
      "description": { "zh": "一次爆裂及核心坍塌包络的持续时间。", "en": "Duration of burst injection and core-collapse envelope." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstForce": {
      "type": "float", "default": 2.42, "min": 0.0, "max": 5.0, "step": 0.01,
      "label": { "zh": "爆裂推力", "en": "Burst Force" },
      "description": { "zh": "分形注入对二维速度场的推力。", "en": "Force applied by fractal injection to the 2D field." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstDensity": {
      "type": "float", "default": 1.12, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "爆裂烟雾", "en": "Burst Smoke" },
      "description": { "zh": "爆裂注入的二维烟雾量。", "en": "2D smoke injected by a burst." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstVisualStrength": {
      "type": "float", "default": 1.35, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "爆裂结构强度", "en": "Burst Structure Strength" },
      "description": { "zh": "二维爆裂记忆抬升成三维结构的强度。", "en": "Strength used when lifting burst memory into 3D structures." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uFractalBranches": {
      "type": "float", "default": 6.4, "min": 3.0, "max": 10.0, "step": 0.1,
      "label": { "zh": "二维分形复杂度", "en": "2D Fractal Complexity" },
      "description": { "zh": "主爆裂场的多尺度复杂度。", "en": "Multi-scale complexity of the main burst field." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBranchSharpness": {
      "type": "float", "default": 3.45, "min": 1.0, "max": 7.0, "step": 0.1,
      "label": { "zh": "二维分支锐度", "en": "2D Branch Sharpness" },
      "description": { "zh": "主分形分支锐度。", "en": "Sharpness of the main fractal branches." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBurstReach": {
      "type": "float", "default": 0.92, "min": 0.50, "max": 1.08, "step": 0.01,
      "label": { "zh": "爆裂范围", "en": "Burst Reach" },
      "description": { "zh": "主干、薄片和碎片的最大展开范围。", "en": "Maximum reach of trunks, sheets, and fragments." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uBranchWidth": {
      "type": "float", "default": 0.052, "min": 0.018, "max": 0.14, "step": 0.002,
      "label": { "zh": "主干宽度", "en": "Branch Width" },
      "description": { "zh": "三维主干的厚度，默认更细以获得清晰分叉。", "en": "Thickness of 3D trunks; the default is thinner for clearer branching." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uSheetStrength": {
      "type": "float", "default": 0.58, "min": 0.0, "max": 2.0, "step": 0.01,
      "label": { "zh": "褶皱薄片", "en": "Folded Sheets" },
      "description": { "zh": "宽褶皱膜状结构强度。", "en": "Strength of broad folded membrane-like structures." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uFragmentStrength": {
      "type": "float", "default": 1.15, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "细碎体积", "en": "Micro Fragments" },
      "description": { "zh": "爆裂时独立 metaball-like 小体积碎片的密度。", "en": "Density of independent metaball-like micro fragments during bursts." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uFragmentScale": {
      "type": "float", "default": 0.82, "min": 0.35, "max": 1.8, "step": 0.01,
      "label": { "zh": "碎片尺寸", "en": "Fragment Scale" },
      "description": { "zh": "独立细碎体积的平均尺寸。", "en": "Average size of independent micro-volume fragments." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uCoreRemnant": {
      "type": "float", "default": 0.10, "min": 0.0, "max": 0.6, "step": 0.01,
      "label": { "zh": "中心残块", "en": "Core Remnants" },
      "description": { "zh": "爆裂后允许留在中心的不规则残块量；0 会完全移除中心核心。", "en": "Sparse irregular remnants allowed after the burst; zero removes the center completely." },
      "group": { "zh": "爆裂", "en": "Burst" }
    },
    "uAudioPaused": {
      "type": "boolean", "default": false,
      "label": { "zh": "暂停音乐", "en": "Pause Audio" },
      "description": { "zh": "暂停合成音频驱动、自动节拍爆裂和波形运动；鼠标点击仍可触发。", "en": "Pauses synthetic audio drive, automatic beat bursts, and waveform motion; pointer bursts remain active." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uAudioBurstEnabled": {
      "type": "boolean", "default": true,
      "label": { "zh": "音频触发爆裂", "en": "Audio Burst Trigger" },
      "description": { "zh": "未暂停时，合成音频越过阈值会触发爆裂。", "en": "When audio is running, upward threshold crossings trigger bursts." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uAudioBurstStrength": {
      "type": "float", "default": 0.78, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "音频爆裂强度", "en": "Audio Burst Strength" },
      "description": { "zh": "节拍事件触发的爆裂强度。", "en": "Burst strength triggered by a beat event." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uBeatThreshold": {
      "type": "float", "default": 0.71, "min": 0.45, "max": 0.95, "step": 0.01,
      "label": { "zh": "节拍阈值", "en": "Beat Threshold" },
      "description": { "zh": "音频包络上升沿阈值。", "en": "Upward-crossing threshold for the audio envelope." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uBeatCooldown": {
      "type": "float", "default": 0.82, "min": 0.2, "max": 3.0, "step": 0.01,
      "label": { "zh": "节拍冷却", "en": "Beat Cooldown" },
      "description": { "zh": "自动爆裂事件之间的最短间隔。", "en": "Minimum interval between automatic burst events." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uAudioInfluence": {
      "type": "float", "default": 0.54, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "音频呼吸", "en": "Audio Breathing" },
      "description": { "zh": "音频对平静核心呼吸和波形的影响。", "en": "Audio influence on idle breathing and the waveform." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uSteps": {
      "type": "int", "default": 76, "min": 32, "max": 140, "step": 1,
      "label": { "zh": "光线步数", "en": "Ray Steps" },
      "description": { "zh": "体积 raymarch 采样步数。", "en": "Volume ray-marching sample count." },
      "group": { "zh": "采样", "en": "Sampling" }
    },
    "uJitter": {
      "type": "float", "default": 0.42, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "采样抖动", "en": "Jitter" },
      "description": { "zh": "降低默认抖动以提高清晰度，同时保留少量抗条带。", "en": "Lower default jitter improves clarity while retaining some banding suppression." },
      "group": { "zh": "采样", "en": "Sampling" }
    },
    "uShadow": {
      "type": "float", "default": 1.12, "min": 0.0, "max": 4.0, "step": 0.01,
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
      "description": { "zh": "底部音频波形颜色。", "en": "Color of the audio waveform." },
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