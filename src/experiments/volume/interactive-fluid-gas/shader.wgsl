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

struct RadialStructure {
  trunk: f32,
  sheet: f32,
  filament: f32,
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

fn hash11(x: f32) -> f32 {
  return fract(sin(x * 127.1 + 311.7) * 43758.5453123);
}

fn hash31(p: vec3f) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + vec3f(33.33));
  return fract((q.x + q.y) * q.z);
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

fn radialImpulseField(
  p: vec2f,
  seed: f32,
  branchCountInput: f32,
  sharpness: f32,
  targetDirection: vec2f,
) -> vec3f {
  let branchCount = clamp(branchCountInput, 3.0, 8.0);
  let baseWidth = mix(0.055, 0.020, clamp(sharpness / 7.0, 0.0, 1.0));
  var directionSum = vec2f(0.0);
  var weightSum = 0.0;
  var strongest = 0.0;

  for (var i = 0; i < 8; i += 1) {
    if (f32(i) >= branchCount) {
      continue;
    }
    let fi = f32(i);
    let branchSeed = seed * 43.71 + fi * 17.23;
    let angle = seed * 6.28318530718
      + fi * 6.28318530718 / branchCount
      + (hash11(branchSeed) - 0.5) * 0.46;
    var dir = vec2f(cos(angle), sin(angle));
    if (i == 0) {
      dir = normalize(dir * 0.68 + targetDirection * 0.32 + vec2f(0.0001));
    }
    let sideAxis = vec2f(-dir.y, dir.x);
    let along = dot(p, dir);
    let curve = (
      sin(along * 8.3 + branchSeed) * 0.016
        + sin(along * 20.0 - branchSeed * 0.41) * 0.005
    ) * smoothstep(0.02, 0.30, along);
    let side = dot(p, sideAxis) + curve;
    let taper = mix(1.0, 0.46, smoothstep(0.09, 0.46, along));
    let width = baseWidth * taper;
    let window = smoothstep(-0.020, 0.026, along)
      * (1.0 - smoothstep(0.34, 0.54, along));
    let trunk = exp(-side * side / max(width * width, 0.00001)) * window;

    let splitOffset = 0.025 + hash11(branchSeed + 7.0) * 0.020;
    let splitWindow = smoothstep(0.12, 0.21, along)
      * (1.0 - smoothstep(0.32, 0.50, along));
    let splitA = exp(-abs(side - splitOffset) / max(width * 0.42, 0.003));
    let splitB = exp(-abs(side + splitOffset * 0.86) / max(width * 0.40, 0.003));
    let weight = max(trunk, max(splitA, splitB) * splitWindow * 0.46);
    let localDir = normalize(dir - sideAxis * cos(along * 9.0 + branchSeed) * 0.10 + vec2f(0.0001));
    directionSum += localDir * weight;
    weightSum += weight;
    strongest = max(strongest, weight);
  }

  let mask = clamp(max(strongest, weightSum * 0.29), 0.0, 1.12);
  return vec3f(normalize(directionSum + vec2f(0.0001)) * mask, mask);
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
  let midpointUv = uv - current.xy * dt * params.uAdvection.x * 0.5;
  let midpoint = sampleFluid(midpointUv);
  let previousUv = uv - midpoint.xy * dt * params.uAdvection.x;
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
    clamp(params.uViscosity.x * dt * 4.2, 0.0, 0.15),
  );

  let centerDelta = uv - vec2f(0.5);
  let centerRadius = max(length(centerDelta), 0.001);
  let radial = centerDelta / centerRadius;
  let tangent = vec2f(-radial.y, radial.x);
  let centerFalloff = exp(-centerRadius * 6.8);
  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;
  let burstPhase = frame.burstState.x;
  let burstStrength = clamp(frame.burstState.w, 0.0, 2.0);
  let burstMix = clamp(burstStrength, 0.0, 1.0);

  let curl = (rightState.y - leftState.y) - (upState.x - downState.x);
  let curlDelay = clamp(params.uCurlDelay.x, 0.05, 0.82);
  let curlRamp = smoothstep(curlDelay, min(curlDelay + 0.30, 0.96), burstPhase);
  let curlScale = mix(1.0, 0.08 + curlRamp * 0.92, burstMix);
  velocity += vec2f(-velocity.y, velocity.x)
    * curl
    * params.uVorticity.x
    * dt
    * 2.15
    * curlScale;

  let displacementLaplacian = leftState.zw
    + rightState.zw
    + downState.zw
    + upState.zw
    - displacement * 4.0;
  displacement -= displacementLaplacian
    * clamp(params.uFlowSharpen.x * dt, 0.0, 0.040);

  let idleFlow = vec2f(
    sin(uv.y * 12.1 + time * 0.81) + sin((uv.x + uv.y) * 17.7 - time * 0.47) * 0.28,
    cos(uv.x * 11.7 - time * 0.73) - cos((uv.x - uv.y) * 18.9 + time * 0.51) * 0.27,
  );
  velocity += idleFlow
    * centerFalloff
    * params.uCoreWobble.x
    * dt
    * (0.038 + audio * params.uAudioInfluence.x * 0.006);

  let injection = frame.pointer.z;
  if (injection > 0.0005) {
    let targetVector = frame.pointerDelta.xy - vec2f(0.5);
    let targetDirection = targetVector / max(length(targetVector), 0.001);
    let field = radialImpulseField(
      centerDelta,
      frame.pointerDelta.w,
      params.uFractalBranches.x,
      params.uBranchSharpness.x,
      targetDirection,
    );
    let reach = max(params.uBurstReach.x, 0.18);
    let source = injection
      * (1.0 - smoothstep(reach * 0.72, reach, centerRadius))
      * field.z;
    let radialBias = clamp(params.uRadialBias.x, 0.2, 2.5);
    let pushDirection = normalize(
      field.xy * 0.76
        + radial * radialBias * 0.44
        + targetDirection * 0.08
        + vec2f(0.0001),
    );
    let impulse = pushDirection * source * params.uBurstForce.x * dt * 15.2;
    velocity += impulse;
    displacement += impulse * dt * params.uMaterialResponse.x * 0.48;
  }

  if (burstStrength > 0.0005) {
    let earlyRadial = (1.0 - smoothstep(0.08, curlDelay, burstPhase)) * burstMix;
    let radialVelocity = radial * dot(velocity, radial);
    let tangentVelocity = velocity - radialVelocity;
    velocity = radialVelocity + tangentVelocity * (1.0 - earlyRadial * 0.82);

    let lateCurl = smoothstep(curlDelay * 0.90, min(curlDelay + 0.31, 0.95), burstPhase)
      * length(displacement)
      * centerFalloff;
    velocity += tangent
      * sin(centerRadius * 29.0 + frame.pointerDelta.w * 21.0 + time * 1.55)
      * lateCurl
      * params.uVorticity.x
      * dt
      * 1.45;
  }

  let radialDisplacement = radial * dot(displacement, radial);
  let tangentDisplacement = displacement - radialDisplacement;
  let returnRamp = smoothstep(0.27, 0.88, burstPhase);
  let radialSpring = mix(1.0, mix(0.25, 1.14, returnRamp), burstMix);
  let tangentSpring = mix(1.0, mix(0.68, 1.04, returnRamp), burstMix);
  velocity -= (radialDisplacement * radialSpring + tangentDisplacement * tangentSpring)
    * params.uElasticity.x
    * dt
    * 7.7;
  velocity *= exp(-params.uElasticDamping.x * dt);
  velocity *= exp(-params.uVelocityDissipation.x * dt);
  displacement += velocity * dt * params.uMaterialResponse.x;

  let speed = length(velocity);
  if (speed > 3.6) {
    velocity *= 3.6 / speed;
  }

  // Keep simulation freedom. Only the user safety cap is applied here;
  // the visible 1.75x radius limit is enforced continuously in density space.
  let userCap = max(params.uMaxDisplacement.x, 0.05);
  let displacementLength = length(displacement);
  if (displacementLength > userCap) {
    displacement *= userCap / displacementLength;
    velocity *= 0.96;
  }

  let index = gid.y * FLUID_SIZE + gid.x;
  fluidOut.cells[index] = vec4f(velocity, displacement);
}

fn rotateVolume(pInput: vec3f, time: f32) -> vec3f {
  var p = pInput;
  let xz = rotate2(vec2f(p.x, p.z), time * 0.11 + 0.19);
  p = vec3f(xz.x, p.y, xz.y);
  let yz = rotate2(vec2f(p.y, p.z), -time * 0.075 + 0.37);
  return vec3f(p.x, yz.x, yz.y);
}

fn crawlWarp(p: vec3f, time: f32, amount: f32) -> vec3f {
  let a = vec3f(
    sin(p.y * 4.2 + p.z * 2.1 + time * 0.75),
    sin(p.z * 3.8 - p.x * 2.6 - time * 0.68 + 1.7),
    sin(p.x * 4.0 + p.y * 2.8 + time * 0.61 + 3.1),
  );
  let b = vec3f(
    sin(p.z * 8.1 - time * 0.92),
    cos(p.x * 7.7 + time * 0.86),
    sin(p.y * 8.7 + time * 0.73),
  );
  return p + (a * 0.72 + b * 0.28) * amount;
}

fn flowNoise3(pInput: vec3f, phase: f32) -> f32 {
  var p = pInput;
  var sum = 0.0;
  var amplitude = 0.55;
  var frequency = 1.0;
  for (var i = 0; i < 3; i += 1) {
    sum += (sin(p.y * frequency + phase * 0.63) + cos(p.x * frequency - phase * 0.47))
      * 0.25 * amplitude;
    let xz = rotate2(vec2f(p.x, p.z), 0.59 + f32(i) * 0.11);
    p = vec3f(xz.x, p.y, xz.y);
    let yz = rotate2(vec2f(p.y, p.z), -0.45 + f32(i) * 0.08);
    p = vec3f(p.x, yz.x, yz.y);
    frequency *= 1.61;
    amplitude *= 0.46;
  }
  return clamp(0.5 + sum, 0.0, 1.0);
}

fn ridgeNoise3(pInput: vec3f, phase: f32) -> f32 {
  var p = pInput;
  var sum = 0.0;
  var amplitude = 0.55;
  var frequency = 1.0;
  for (var i = 0; i < 4; i += 1) {
    let wave = abs(
      sin(p.y * frequency + phase * 0.71)
        + cos(p.x * frequency - phase * 0.53)
    ) * 0.5;
    sum += pow(max(0.0, 1.0 - wave), 1.45) * amplitude;
    let xy = rotate2(vec2f(p.x, p.y), 0.63 + f32(i) * 0.08);
    p = vec3f(xy.x, xy.y, p.z);
    let xz = rotate2(vec2f(p.x, p.z), -0.52 + f32(i) * 0.06);
    p = vec3f(xz.x, p.y, xz.y);
    frequency *= 1.76;
    amplitude *= 0.48;
  }
  return clamp(sum / 1.02, 0.0, 1.0);
}

fn fineNoise3(p: vec3f, time: f32) -> f32 {
  return clamp(
    0.5 + (
      sin(p.x * 16.7 + p.y * 4.9 + time * 0.33)
        + sin(p.y * 21.3 - p.z * 4.1 - time * 0.29)
        + sin(p.z * 27.1 + p.x * 5.3 + time * 0.25)
    ) / 6.0,
    0.0,
    1.0,
  );
}

fn detailGradient(p: vec3f, time: f32) -> vec3f {
  let a = p.x * 16.7 + p.y * 4.9 + time * 0.33;
  let b = p.y * 21.3 - p.z * 4.1 - time * 0.29;
  let c = p.z * 27.1 + p.x * 5.3 + time * 0.25;
  let gx = cos(a) * 16.7 + cos(c) * 5.3;
  let gy = cos(a) * 4.9 + cos(b) * 21.3;
  let gz = -cos(b) * 4.1 + cos(c) * 27.1;
  return vec3f(gx, gy, gz) / 34.0;
}

fn sampleFlowWorld(p: vec3f) -> Flow3D {
  let axis = abs(p) + vec3f(0.055);
  let weightsRaw = axis * axis * axis;
  let weights = weightsRaw / max(dot(weightsRaw, vec3f(1.0)), 0.001);
  let xy = sampleFluid(p.xy * 0.46 + vec2f(0.5));
  let yz = sampleFluid(p.yz * 0.46 + vec2f(0.5));
  let zx = sampleFluid(vec2f(p.z, p.x) * 0.46 + vec2f(0.5));

  let velocityRaw = vec3f(xy.x, xy.y, 0.0) * weights.z
    + vec3f(0.0, yz.x, yz.y) * weights.x
    + vec3f(zx.y, 0.0, zx.x) * weights.y;
  let displacementRaw = vec3f(xy.z, xy.w, 0.0) * weights.z
    + vec3f(0.0, yz.z, yz.w) * weights.x
    + vec3f(zx.w, 0.0, zx.z) * weights.y;

  let radial = normalize(p + vec3f(0.0001));
  let velocityR = radial * dot(velocityRaw, radial);
  let displacementR = radial * dot(displacementRaw, radial);
  var result: Flow3D;
  result.velocity = velocityR * 1.12 + (velocityRaw - velocityR) * 0.70;
  result.displacement = displacementR * 1.30 + (displacementRaw - displacementR) * 0.54;
  return result;
}

fn branchDirection3(index: i32, seed: f32) -> vec3f {
  let fi = f32(index);
  let h0 = hash11(seed * 51.7 + fi * 23.1 + 4.0);
  let h1 = hash11(seed * 79.3 + fi * 31.9 + 9.0);
  let z = mix(-0.70, 0.70, h0);
  let angle = h1 * 6.28318530718;
  let planar = sqrt(max(1.0 - z * z, 0.001));
  return normalize(vec3f(cos(angle) * planar, sin(angle) * planar, z));
}

fn radialStructure3(p: vec3f, seed: f32, branchCountInput: f32, sharpness: f32) -> RadialStructure {
  var result: RadialStructure;
  result.trunk = 0.0;
  result.sheet = 0.0;
  result.filament = 0.0;
  let branchCount = clamp(branchCountInput, 3.0, 8.0);
  let core = params.uCoreRadius.x;
  let extent = core * clamp(params.uBurstRadiusLimit.x, 1.10, 1.75);
  let widthBase = mix(core * 0.24, core * 0.095, clamp(sharpness / 7.0, 0.0, 1.0));

  for (var i = 0; i < 8; i += 1) {
    if (f32(i) >= branchCount) {
      continue;
    }
    let dir = branchDirection3(i, seed);
    var refAxis = vec3f(0.0, 1.0, 0.0);
    if (abs(dir.y) > 0.82) {
      refAxis = vec3f(1.0, 0.0, 0.0);
    }
    let sideA = normalize(cross(dir, refAxis));
    let sideB = normalize(cross(dir, sideA));
    let along = dot(p, dir);
    let branchSeed = seed * 37.1 + f32(i) * 13.7;
    let bendA = sin(along / max(core, 0.1) * 7.0 + branchSeed) * core * 0.072
      * smoothstep(core * 0.12, extent * 0.72, along);
    let bendB = sin(along / max(core, 0.1) * 12.0 - branchSeed * 0.47) * core * 0.038
      * smoothstep(core * 0.16, extent * 0.80, along);
    let local = p - dir * along - sideA * bendA - sideB * bendB;
    let a = dot(local, sideA);
    let b = dot(local, sideB);
    let dist = length(vec2f(a, b));
    let taper = mix(1.0, 0.38, smoothstep(extent * 0.25, extent * 0.90, along));
    let width = widthBase * taper;
    let window = smoothstep(-core * 0.05, core * 0.08, along)
      * (1.0 - smoothstep(extent * 0.76, extent * 0.98, along));
    let trunk = exp(-dist * dist / max(width * width, 0.00001)) * window;
    let sheet = exp(-abs(a) / max(width * 0.14, 0.0025))
      * exp(-abs(b) / max(width * 1.45, 0.005))
      * window;
    let pulse = 0.38 + 0.62 * max(0.0, sin(along / max(core, 0.1) * 34.0 + branchSeed * 2.1));
    let filament = exp(-dist / max(width * 0.18, 0.0025)) * window * pulse;
    result.trunk = max(result.trunk, trunk);
    result.sheet = max(result.sheet, sheet);
    result.filament = max(result.filament, filament);
  }
  return result;
}

fn densityField(pWorld: vec3f) -> VolumeSample {
  var out: VolumeSample;
  out.density = 0.0;
  out.detail = 0.0;
  out.activity = 0.0;

  let baseCore = params.uCoreRadius.x;
  let burstLimit = clamp(params.uBurstRadiusLimit.x, 1.10, 1.75);
  let visibleRadius = baseCore * burstLimit;
  let worldRadius = length(pWorld);
  if (worldRadius >= visibleRadius) {
    return out;
  }
  let boundaryFade = 1.0 - smoothstep(visibleRadius * 0.965, visibleRadius, worldRadius);

  let time = frame.timeResolution.x;
  let flow = sampleFlowWorld(pWorld);
  let deformation = params.uFluidInfluence.x;
  let worldDisplacement = flow.displacement * deformation;
  let displacementAmount = length(worldDisplacement);
  let radial = normalize(pWorld + vec3f(0.0001));
  let radialDisplacement = max(dot(worldDisplacement, radial), 0.0);
  let materialPosition = pWorld - worldDisplacement;

  let crawled = crawlWarp(materialPosition, time, params.uCoreWobble.x * 0.24);
  let materialRadius = max(length(crawled), 0.001);
  let direction = crawled / materialRadius;
  let q = rotateVolume(crawled, time * (0.15 + params.uTurbulence.x * 0.035));
  let coarse = flowNoise3(
    q * 2.1 + vec3f(0.37, -0.21, 0.13),
    time * (0.18 + params.uTurbulence.x * 0.052),
  );
  let mid = ridgeNoise3(
    q * params.uNoiseScale.x * 0.82,
    time * (0.25 + params.uTurbulence.x * 0.070),
  );
  let fine = fineNoise3(q * (1.0 + params.uNoiseScale.x * 0.13), time);

  let directionalLobe = (
    sin(direction.x * 4.7 + time * 0.23)
      + sin(direction.y * 5.3 - time * 0.19)
      + sin(direction.z * 6.1 + time * 0.17 + 1.4)
  ) / 3.0;
  let breathing = sin(time * 1.43) * params.uExpansion.x * 0.006
    + (frame.pointer.w - 0.5) * params.uAudioInfluence.x * 0.005;
  let localRadius = baseCore
    + breathing
    + (coarse - 0.5) * params.uCoreWobble.x * 0.55
    + directionalLobe * params.uCoreWobble.x * 0.18;
  let surfaceWarp = (mid - 0.5) * params.uCoreDetailStrength.x * 0.036
    + (fine - 0.5) * params.uCoreDetailStrength.x * 0.018;
  let edge = materialRadius - surfaceWarp - localRadius;
  let coreEnvelope = 1.0 - smoothstep(-0.020, 0.024, edge);

  let porositySignal = mid * 0.66 + fine * 0.34;
  let porous = smoothstep(
    params.uDetailCutoff.x - 0.075,
    params.uDetailCutoff.x + 0.065,
    porositySignal,
  );
  let crispCore = pow(max(coreEnvelope * (0.12 + porous * 0.88), 0.0), 1.16);

  let strainMeasure = max(displacementAmount, radialDisplacement * 1.42);
  let strain = smoothstep(
    params.uTearThreshold.x,
    params.uTearThreshold.x + 0.13,
    strainMeasure,
  );
  let structure = radialStructure3(
    pWorld,
    frame.pointerDelta.w,
    params.uFractalBranches.x,
    params.uBranchSharpness.x,
  );
  let structureSupport = clamp(
    max(structure.trunk, structure.sheet * params.uSheetStrength.x * 0.94)
      + structure.filament * params.uFineStretchDetail.x * 0.30,
    0.0,
    1.20,
  );
  let grain = smoothstep(0.43, 0.66, mid * 0.62 + fine * 0.38);
  let stretchedMaterial = clamp(
    0.07 + structureSupport * 0.98 + grain * 0.16,
    0.0,
    1.12,
  );

  let centerEvacuation = smoothstep(
    params.uTearThreshold.x * 0.52,
    params.uTearThreshold.x + 0.10,
    radialDisplacement,
  ) * (1.0 - smoothstep(baseCore * 0.22, baseCore * 1.08, worldRadius))
    * params.uExpansionDensityLoss.x
    * 0.84;
  let expansionLoss = strain
    * (1.0 - clamp(structureSupport, 0.0, 1.0))
    * params.uStrainTearing.x
    * 0.66;
  let burstDensityShape = mix(1.0, stretchedMaterial, strain * 0.92);
  let density = crispCore
    * burstDensityShape
    * max(0.0, 1.0 - centerEvacuation - expansionLoss)
    * boundaryFade;

  out.density = max(0.0, density * params.uDensity.x);
  out.detail = clamp(
    mid * 0.46
      + fine * 0.25
      + structure.sheet * strain * 0.12
      + structure.filament * strain * 0.22,
    0.0,
    1.0,
  );
  out.activity = clamp(strain + length(flow.velocity) * 0.12, 0.0, 1.0);
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
  let screen = vec2f((in.uv.x * 2.0 - 1.0) * aspect, in.uv.y * 2.0 - 1.0);
  let time = frame.timeResolution.x;
  let radians = 0.017453292519943295;
  let yaw = (params.uCameraYaw.x + time * params.uCameraOrbitSpeed.x) * radians;
  let pitch = clamp(params.uCameraPitch.x, -82.0, 82.0) * radians;
  let cameraDistance = clamp(params.uCameraDistance.x, 1.45, 6.0);
  let cp = cos(pitch);
  let ro = vec3f(sin(yaw) * cp, sin(pitch), cos(yaw) * cp) * cameraDistance;
  let forward = normalize(-ro);
  let cameraRight = normalize(cross(forward, vec3f(0.0, 1.0, 0.0)));
  let cameraUp = normalize(cross(cameraRight, forward));
  let focal = 1.0 / tan(clamp(params.uCameraFov.x, 20.0, 100.0) * radians * 0.5);
  let rd = normalize(forward * focal + cameraRight * screen.x + cameraUp * screen.y);

  let renderRadius = params.uCoreRadius.x * clamp(params.uBurstRadiusLimit.x, 1.10, 1.75) + 0.025;
  let hit = intersectSphere(ro, rd, renderRadius);
  var background = mix(vec3f(0.007, 0.010, 0.017), vec3f(0.030, 0.047, 0.070), in.uv.y);
  background *= max(1.0 - 0.22 * dot(screen * 0.48, screen * 0.48), 0.58);

  var color = background;
  if (hit.y > max(hit.x, 0.0)) {
    let steps = clamp(i32(params.uSteps.x), 56, 176);
    let startT = max(hit.x, 0.0);
    let stepLength = (hit.y - startT) / f32(steps);
    let jitter = (hash31(vec3f(in.position.xy, 0.371)) - 0.5) * stepLength * params.uJitter.x;
    var t = startT + jitter;
    var transmittance = 1.0;
    var scattering = vec3f(0.0);
    var previousDensity = 0.0;
    let lightDir = normalize(vec3f(-0.52, 0.71, 0.47));
    let gasColor = params.uGasColor.xyz;

    for (var i = 0; i < 176; i += 1) {
      if (i >= steps) {
        break;
      }
      let p = ro + rd * t;
      let sample = densityField(p);
      let densityEdge = abs(sample.density - previousDensity);
      previousDensity = sample.density;
      if (sample.density > 0.0010) {
        let q = rotateVolume(p, time * 0.10);
        let microNormal = detailGradient(q * (1.0 + params.uNoiseScale.x * 0.10), time);
        let outward = normalize(
          p
            + microNormal * params.uCoreRadius.x * params.uCoreDetailStrength.x * (0.10 + sample.detail * 0.10)
            + vec3f(0.0001),
        );
        let directional = clamp(dot(outward, lightDir) * 0.5 + 0.5, 0.0, 1.0);
        let localShadow = exp(-sample.density * params.uShadow.x * 0.30);
        let detailContrast = 0.48 + sample.detail * 0.88;
        let light = (0.075 + 0.925 * directional * localShadow) * detailContrast;
        let rim = pow(1.0 - abs(dot(outward, -rd)), 2.8);
        let edgeLight = min(densityEdge * 1.8, 0.26) * (0.45 + sample.activity * 0.25);
        let sampleColor = gasColor * (
          light
            + rim * (0.06 + sample.activity * 0.19)
            + edgeLight
        );
        let alpha = 1.0 - exp(-sample.density * params.uAbsorption.x * stepLength);
        scattering += transmittance * alpha * sampleColor;
        transmittance *= 1.0 - alpha;
        if (transmittance < 0.010) {
          break;
        }
      }
      t += stepLength;
    }
    color = scattering + background * transmittance;
  }

  let audioRunning = 1.0 - params.uAudioPaused.x;
  let waveX = in.uv.x * 2.0 - 1.0;
  let wave = -0.79
    + waveform(waveX, time) * (0.020 + frame.pointer.w * 0.015)
      * params.uAudioInfluence.x * audioRunning;
  let line = exp(-abs(screen.y - wave) * max(resolution.y, 1.0) * 0.42);
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
    "uCameraDistance": { "type": "float", "default": 2.95, "min": 1.5, "max": 6.0, "step": 0.02, "label": { "zh": "相机距离", "en": "Camera Distance" }, "group": { "zh": "相机", "en": "Camera" } },
    "uCameraFov": { "type": "float", "default": 44.0, "min": 20.0, "max": 100.0, "step": 1.0, "label": { "zh": "相机视野", "en": "Camera FOV" }, "group": { "zh": "相机", "en": "Camera" } },
    "uCameraOrbitSpeed": { "type": "float", "default": 0.0, "min": -30.0, "max": 30.0, "step": 0.1, "label": { "zh": "自动环绕速度", "en": "Auto Orbit Speed" }, "group": { "zh": "相机", "en": "Camera" } },

    "uDensity": { "type": "float", "default": 0.92, "min": 0.1, "max": 3.0, "step": 0.01, "label": { "zh": "气体密度", "en": "Gas Density" }, "group": { "zh": "体积", "en": "Volume" } },
    "uAbsorption": { "type": "float", "default": 1.42, "min": 0.2, "max": 8.0, "step": 0.01, "label": { "zh": "吸收", "en": "Absorption" }, "group": { "zh": "体积", "en": "Volume" } },

    "uCoreRadius": { "type": "float", "default": 0.375, "min": 0.25, "max": 0.60, "step": 0.005, "label": { "zh": "核心半径", "en": "Core Radius" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uCoreWobble": { "type": "float", "default": 0.125, "min": 0.0, "max": 0.30, "step": 0.005, "label": { "zh": "核心蠕动", "en": "Core Wobble" }, "description": { "zh": "低频只负责核心轮廓缓慢蠕动，不再承担可见宽条纹。", "en": "Low-frequency motion only deforms the broad contour instead of creating visible wide bands." }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uCoreDetailStrength": { "type": "float", "default": 1.28, "min": 0.0, "max": 2.4, "step": 0.01, "label": { "zh": "表面结构", "en": "Surface Structure" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uNoiseScale": { "type": "float", "default": 5.25, "min": 1.0, "max": 10.0, "step": 0.02, "label": { "zh": "材质分形尺度", "en": "Material Fractal Scale" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uDetailCutoff": { "type": "float", "default": 0.56, "min": 0.18, "max": 0.84, "step": 0.01, "label": { "zh": "内部疏松度", "en": "Internal Porosity" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uTurbulence": { "type": "float", "default": 1.08, "min": 0.0, "max": 2.8, "step": 0.01, "label": { "zh": "翻涌速度", "en": "Rolling Speed" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uExpansion": { "type": "float", "default": 0.07, "min": 0.0, "max": 1.5, "step": 0.01, "label": { "zh": "呼吸扩张", "en": "Breathing Expansion" }, "group": { "zh": "核心形态", "en": "Core Shape" } },

    "uFluidInfluence": { "type": "float", "default": 1.48, "min": 0.0, "max": 3.5, "step": 0.01, "label": { "zh": "材质流形变", "en": "Material Flow Deformation" }, "description": { "zh": "三平面位移重建会强化径向分量并减弱切向平均，减少面团式压扁。", "en": "Tri-planar displacement reconstruction favors radial motion and suppresses tangential averaging to reduce dough-like flattening." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uMaterialResponse": { "type": "float", "default": 1.20, "min": 0.2, "max": 2.5, "step": 0.01, "label": { "zh": "材质惯性", "en": "Material Response" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uElasticity": { "type": "float", "default": 1.04, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "弹性恢复", "en": "Elastic Restoration" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uElasticDamping": { "type": "float", "default": 0.82, "min": 0.0, "max": 4.0, "step": 0.01, "label": { "zh": "弹性阻尼", "en": "Elastic Damping" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uMaxDisplacement": { "type": "float", "default": 0.34, "min": 0.05, "max": 0.75, "step": 0.01, "label": { "zh": "模拟位移上限", "en": "Simulation Displacement Cap" }, "description": { "zh": "只作为安全上限，不再按爆裂半径把大量网格单元压到同一位移值。", "en": "Acts only as a safety cap; it no longer clamps many grid cells to the same burst-radius-derived displacement." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uBurstRadiusLimit": { "type": "float", "default": 1.68, "min": 1.10, "max": 1.75, "step": 0.01, "label": { "zh": "最大爆裂比例", "en": "Burst Radius Limit" }, "description": { "zh": "最终可见体积的世界空间限制，硬上限仍为核心半径的 1.75 倍。", "en": "World-space limit for final visible density; the hard maximum remains 1.75 times the core radius." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uFlowSharpen": { "type": "float", "default": 0.24, "min": 0.0, "max": 1.5, "step": 0.01, "label": { "zh": "流场锐化", "en": "Flow Sharpening" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uTearThreshold": { "type": "float", "default": 0.070, "min": 0.02, "max": 0.40, "step": 0.004, "label": { "zh": "拉伸撕裂阈值", "en": "Stretch Tear Threshold" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uStrainTearing": { "type": "float", "default": 1.04, "min": 0.0, "max": 1.8, "step": 0.01, "label": { "zh": "拉伸撕裂", "en": "Strain Tearing" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uFineStretchDetail": { "type": "float", "default": 1.06, "min": 0.0, "max": 1.5, "step": 0.01, "label": { "zh": "主干细丝", "en": "Trunk Filaments" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uSheetStrength": { "type": "float", "default": 0.92, "min": 0.0, "max": 1.8, "step": 0.01, "label": { "zh": "撕裂薄片", "en": "Torn Sheets" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uExpansionDensityLoss": { "type": "float", "default": 1.06, "min": 0.0, "max": 2.0, "step": 0.01, "label": { "zh": "中心抽离", "en": "Center Evacuation" }, "group": { "zh": "材质流", "en": "Material Flow" } },

    "uAdvection": { "type": "float", "default": 1.08, "min": 0.1, "max": 2.0, "step": 0.01, "label": { "zh": "平流速度", "en": "Advection" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uViscosity": { "type": "float", "default": 0.035, "min": 0.0, "max": 1.0, "step": 0.005, "label": { "zh": "粘性", "en": "Viscosity" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uVorticity": { "type": "float", "default": 1.06, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "后段卷曲", "en": "Late Vorticity" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uVelocityDissipation": { "type": "float", "default": 0.30, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "速度耗散", "en": "Velocity Dissipation" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uSolverSubsteps": { "type": "int", "default": 2, "min": 1, "max": 4, "step": 1, "label": { "zh": "解算子步", "en": "Solver Substeps" }, "group": { "zh": "二维解算", "en": "2D Solver" } },

    "uClickBurstStrength": { "type": "float", "default": 1.28, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "点击冲击强度", "en": "Click Impact Strength" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uBurstDuration": { "type": "float", "default": 1.82, "min": 0.45, "max": 4.0, "step": 0.01, "label": { "zh": "恢复周期", "en": "Recovery Window" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uBurstForce": { "type": "float", "default": 2.82, "min": 0.0, "max": 5.0, "step": 0.01, "label": { "zh": "径向冲击推力", "en": "Radial Impact Force" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uFractalBranches": { "type": "float", "default": 6.0, "min": 3.0, "max": 8.0, "step": 1.0, "label": { "zh": "径向主干数量", "en": "Radial Trunk Count" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uBranchSharpness": { "type": "float", "default": 4.4, "min": 1.0, "max": 7.0, "step": 0.1, "label": { "zh": "主干收束度", "en": "Trunk Sharpness" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uBurstReach": { "type": "float", "default": 0.46, "min": 0.18, "max": 0.70, "step": 0.01, "label": { "zh": "径向作用范围", "en": "Radial Reach" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uRadialBias": { "type": "float", "default": 1.52, "min": 0.2, "max": 2.5, "step": 0.01, "label": { "zh": "径向偏置", "en": "Radial Bias" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uCurlDelay": { "type": "float", "default": 0.40, "min": 0.05, "max": 0.80, "step": 0.01, "label": { "zh": "卷曲延迟", "en": "Curl Delay" }, "group": { "zh": "冲击", "en": "Impact" } },

    "uAudioPaused": { "type": "boolean", "default": false, "label": { "zh": "暂停音乐", "en": "Pause Audio" }, "group": { "zh": "音频", "en": "Audio" } },
    "uAudioBurstEnabled": { "type": "boolean", "default": true, "label": { "zh": "音频触发冲击", "en": "Audio Impact Trigger" }, "group": { "zh": "音频", "en": "Audio" } },
    "uAudioBurstStrength": { "type": "float", "default": 0.78, "min": 0.0, "max": 2.5, "step": 0.01, "label": { "zh": "音频冲击强度", "en": "Audio Impact Strength" }, "group": { "zh": "音频", "en": "Audio" } },
    "uBeatThreshold": { "type": "float", "default": 0.72, "min": 0.45, "max": 0.95, "step": 0.01, "label": { "zh": "节拍阈值", "en": "Beat Threshold" }, "group": { "zh": "音频", "en": "Audio" } },
    "uBeatCooldown": { "type": "float", "default": 1.20, "min": 0.2, "max": 3.0, "step": 0.01, "label": { "zh": "节拍冷却", "en": "Beat Cooldown" }, "group": { "zh": "音频", "en": "Audio" } },
    "uAudioInfluence": { "type": "float", "default": 0.46, "min": 0.0, "max": 2.5, "step": 0.01, "label": { "zh": "音频呼吸", "en": "Audio Breathing" }, "group": { "zh": "音频", "en": "Audio" } },

    "uSteps": { "type": "int", "default": 120, "min": 56, "max": 176, "step": 1, "label": { "zh": "光线步数", "en": "Ray Steps" }, "group": { "zh": "采样", "en": "Sampling" } },
    "uJitter": { "type": "float", "default": 0.02, "min": 0.0, "max": 0.5, "step": 0.01, "label": { "zh": "采样抖动", "en": "Jitter" }, "group": { "zh": "采样", "en": "Sampling" } },
    "uShadow": { "type": "float", "default": 1.55, "min": 0.0, "max": 4.0, "step": 0.01, "label": { "zh": "局部阴影", "en": "Local Shadow" }, "group": { "zh": "光照", "en": "Lighting" } },
    "uGasColor": { "type": "color", "default": "#789dd0", "label": { "zh": "气体颜色", "en": "Gas Color" }, "group": { "zh": "外观", "en": "Appearance" } },
    "uWaveColor": { "type": "color", "default": "#55d8ff", "label": { "zh": "波形颜色", "en": "Wave Color" }, "group": { "zh": "外观", "en": "Appearance" } },
    "uUncappedBenchmark": { "type": "boolean", "default": false, "label": { "zh": "取消帧率限制", "en": "Uncapped Benchmark" }, "group": { "zh": "性能", "en": "Performance" } }
  }
}
@endshaderlab */