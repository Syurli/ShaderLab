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
  let baseWidth = mix(0.062, 0.024, clamp(sharpness / 7.0, 0.0, 1.0));
  var weightedDirection = vec2f(0.0);
  var totalWeight = 0.0;
  var strongest = 0.0;

  for (var i = 0; i < 8; i += 1) {
    let fi = f32(i);
    if (fi >= branchCount) {
      continue;
    }

    let branchSeed = seed * 41.73 + fi * 17.17;
    let angularJitter = (hash11(branchSeed) - 0.5) * 0.52;
    let angle = seed * 6.28318530718
      + fi * 6.28318530718 / branchCount
      + angularJitter;
    var direction = vec2f(cos(angle), sin(angle));
    if (i == 0) {
      direction = normalize(direction * 0.72 + targetDirection * 0.28 + vec2f(0.0001));
    }

    let sideAxis = vec2f(-direction.y, direction.x);
    let along = dot(p, direction);
    let curve = (
      sin(along * (7.0 + hash11(branchSeed + 2.0) * 3.0) + branchSeed) * 0.020
        + sin(along * 18.0 - branchSeed * 0.43) * 0.007
    ) * smoothstep(0.025, 0.34, along);
    let side = dot(p, sideAxis) + curve;
    let taper = mix(1.0, 0.56, smoothstep(0.11, 0.52, along));
    let width = baseWidth * taper;
    let window = smoothstep(-0.025, 0.030, along)
      * (1.0 - smoothstep(0.36, 0.59, along));
    let trunk = exp(-abs(side) / max(width, 0.004)) * window;

    let splitOffset = 0.028 + hash11(branchSeed + 7.0) * 0.026;
    let splitWindow = smoothstep(0.13, 0.23, along)
      * (1.0 - smoothstep(0.33, 0.55, along));
    let splitA = exp(-abs(side - splitOffset) / max(width * 0.52, 0.003));
    let splitB = exp(-abs(side + splitOffset * 0.82) / max(width * 0.48, 0.003));
    let splits = max(splitA, splitB) * splitWindow * 0.56;
    let weight = max(trunk, splits);

    let localDirection = normalize(
      direction - sideAxis * cos(along * 8.0 + branchSeed) * 0.12 + vec2f(0.0001),
    );
    weightedDirection += localDirection * weight;
    totalWeight += weight;
    strongest = max(strongest, weight);
  }

  let mask = clamp(max(strongest, totalWeight * 0.34), 0.0, 1.25);
  let pushDirection = normalize(weightedDirection + vec2f(0.0001));
  return vec3f(pushDirection * mask, mask);
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
    clamp(params.uViscosity.x * dt * 5.0, 0.0, 0.18),
  );

  let centerDelta = uv - vec2f(0.5);
  let centerRadius = max(length(centerDelta), 0.001);
  let radial = centerDelta / centerRadius;
  let tangent = vec2f(-radial.y, radial.x);
  let centerFalloff = exp(-centerRadius * 6.2);
  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;
  let burstPhase = frame.burstState.x;
  let burstStrength = clamp(frame.burstState.w, 0.0, 2.0);
  let burstMix = clamp(burstStrength, 0.0, 1.0);

  let curl = (rightState.y - leftState.y) - (upState.x - downState.x);
  let curlDelay = clamp(params.uCurlDelay.x, 0.04, 0.82);
  let curlRamp = smoothstep(curlDelay, min(curlDelay + 0.34, 0.96), burstPhase);
  let burstCurlScale = 0.10 + curlRamp * 0.90;
  let curlScale = mix(1.0, burstCurlScale, burstMix);
  velocity += vec2f(-velocity.y, velocity.x)
    * curl
    * params.uVorticity.x
    * dt
    * 2.45
    * curlScale;

  let displacementLaplacian = leftState.zw
    + rightState.zw
    + downState.zw
    + upState.zw
    - displacement * 4.0;
  displacement -= displacementLaplacian
    * clamp(params.uFlowSharpen.x * dt, 0.0, 0.050);

  let idleCurl = vec2f(
    sin(uv.y * 12.7 + time * 0.83) + sin((uv.x + uv.y) * 18.3 - time * 0.47) * 0.37,
    cos(uv.x * 11.9 - time * 0.71) - cos((uv.x - uv.y) * 17.1 + time * 0.52) * 0.34,
  );
  velocity += idleCurl
    * centerFalloff
    * params.uCoreWobble.x
    * dt
    * (0.052 + audio * params.uAudioInfluence.x * 0.008);

  let injection = frame.pointer.z;
  if (injection > 0.0005) {
    let seed = frame.pointerDelta.w;
    let targetVector = frame.pointerDelta.xy - vec2f(0.5);
    let targetDirection = targetVector / max(length(targetVector), 0.001);
    let radialField = radialImpulseField(
      centerDelta,
      seed,
      clamp(params.uFractalBranches.x, 3.0, 8.0),
      clamp(params.uBranchSharpness.x, 1.0, 7.0),
      targetDirection,
    );
    let reach = max(params.uBurstReach.x, 0.20);
    let radialEnvelope = 1.0 - smoothstep(reach * 0.72, reach, centerRadius);
    let source = injection * radialEnvelope * radialField.z;
    let trunkDirection = normalize(radialField.xy + vec2f(0.0001));
    let radialBias = clamp(params.uRadialBias.x, 0.2, 2.5);
    let pushDirection = normalize(
      trunkDirection * (0.72 + radialBias * 0.22)
        + radial * radialBias * 0.34
        + targetDirection * 0.10
        + vec2f(0.0001),
    );
    let impulse = pushDirection
      * source
      * params.uBurstForce.x
      * dt
      * 16.8;
    velocity += impulse;
    displacement += impulse * dt * params.uMaterialResponse.x * 0.60;
  }

  if (burstStrength > 0.0005) {
    let earlyRadial = (1.0 - smoothstep(0.10, curlDelay, burstPhase)) * burstMix;
    let radialVelocity = radial * dot(velocity, radial);
    let tangentialVelocity = velocity - radialVelocity;
    velocity = radialVelocity + tangentialVelocity * (1.0 - earlyRadial * 0.74);

    let curlDrive = smoothstep(curlDelay * 0.82, min(curlDelay + 0.34, 0.95), burstPhase)
      * length(displacement)
      * centerFalloff;
    velocity += tangent
      * sin(centerRadius * 31.0 + frame.pointerDelta.w * 19.0 + time * 1.7)
      * curlDrive
      * params.uVorticity.x
      * dt
      * 1.75;
  }

  let displacementRadial = radial * dot(displacement, radial);
  let displacementTangential = displacement - displacementRadial;
  let returnRamp = smoothstep(0.24, 0.86, burstPhase);
  let radialSpring = mix(1.0, mix(0.26, 1.16, returnRamp), burstMix);
  let tangentialSpring = mix(1.0, mix(0.58, 1.02, returnRamp), burstMix);
  let springDisplacement = displacementRadial * radialSpring
    + displacementTangential * tangentialSpring;
  velocity -= springDisplacement
    * params.uElasticity.x
    * dt
    * 8.0;
  velocity *= exp(-params.uElasticDamping.x * dt);
  velocity *= exp(-params.uVelocityDissipation.x * dt);

  displacement += velocity * dt * params.uMaterialResponse.x;

  let speed = length(velocity);
  if (speed > 3.6) {
    velocity *= 3.6 / speed;
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

fn branchDirection3(index: i32, seed: f32) -> vec3f {
  let fi = f32(index);
  let h0 = hash11(seed * 51.7 + fi * 23.1 + 4.0);
  let h1 = hash11(seed * 79.3 + fi * 31.9 + 9.0);
  let z = mix(-0.72, 0.72, h0);
  let angle = h1 * 6.28318530718;
  let planar = sqrt(max(1.0 - z * z, 0.001));
  return normalize(vec3f(cos(angle) * planar, sin(angle) * planar, z));
}

fn radialStructure3(
  p: vec3f,
  seed: f32,
  branchCountInput: f32,
  sharpness: f32,
) -> RadialStructure {
  var result: RadialStructure;
  result.trunk = 0.0;
  result.sheet = 0.0;
  result.filament = 0.0;

  let branchCount = clamp(branchCountInput, 3.0, 8.0);
  let baseWidth = mix(0.105, 0.048, clamp(sharpness / 7.0, 0.0, 1.0));

  for (var i = 0; i < 8; i += 1) {
    if (f32(i) >= branchCount) {
      continue;
    }

    let direction = branchDirection3(i, seed);
    var referenceAxis = vec3f(0.0, 1.0, 0.0);
    if (abs(direction.y) > 0.82) {
      referenceAxis = vec3f(1.0, 0.0, 0.0);
    }
    let sideA = normalize(cross(direction, referenceAxis));
    let sideB = normalize(cross(direction, sideA));
    let along = dot(p, direction);
    let branchSeed = seed * 37.1 + f32(i) * 13.7;
    let bendA = sin(along * 6.5 + branchSeed) * 0.038 * smoothstep(0.06, 0.52, along);
    let bendB = sin(along * 10.7 - branchSeed * 0.47) * 0.022 * smoothstep(0.08, 0.58, along);
    let local = p
      - direction * along
      - sideA * bendA
      - sideB * bendB;
    let localA = dot(local, sideA);
    let localB = dot(local, sideB);
    let distanceToAxis = length(vec2f(localA, localB));
    let taper = mix(1.0, 0.48, smoothstep(0.18, 0.85, along));
    let width = baseWidth * taper;
    let window = smoothstep(-0.035, 0.045, along)
      * (1.0 - smoothstep(0.56, 1.02, along));

    let trunk = exp(-distanceToAxis * distanceToAxis / max(width * width, 0.00001)) * window;
    let sheet = exp(-abs(localA) / max(width * 0.20, 0.004))
      * exp(-abs(localB) / max(width * 1.75, 0.008))
      * window;
    let filamentPulse = 0.58
      + 0.42 * max(0.0, sin(along * 31.0 + branchSeed * 2.1));
    let filament = exp(-distanceToAxis / max(width * 0.27, 0.004))
      * window
      * filamentPulse;

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

  if (length(pWorld) > 1.30) {
    return out;
  }

  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;
  let flow = sampleFlowWorld(pWorld);
  let deformation = params.uFluidInfluence.x;
  let materialPosition = pWorld - flow.displacement * deformation;
  let displacementAmount = length(flow.displacement) * deformation;
  let worldRadius = max(length(pWorld), 0.001);
  let worldRadial = pWorld / worldRadius;
  let radialDisplacement = max(dot(flow.displacement * deformation, worldRadial), 0.0);

  var expansionGradient = 0.0;
  if (displacementAmount > params.uTearThreshold.x * 0.42) {
    let outwardFlow = sampleFlowWorld(pWorld + worldRadial * 0.036);
    let outwardRadial = dot(outwardFlow.displacement * deformation, worldRadial);
    expansionGradient = max((outwardRadial - radialDisplacement) / 0.036, 0.0);
  }

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

  let strainMeasure = max(displacementAmount, radialDisplacement * 1.55);
  let strain = smoothstep(
    params.uTearThreshold.x,
    params.uTearThreshold.x + 0.17,
    strainMeasure,
  );
  let structure = radialStructure3(
    materialPosition,
    frame.pointerDelta.w,
    clamp(params.uFractalBranches.x, 3.0, 8.0),
    clamp(params.uBranchSharpness.x, 1.0, 7.0),
  );
  let sheetSupport = structure.sheet * params.uSheetStrength.x;
  let filamentSupport = structure.filament * params.uFineStretchDetail.x;
  let structureSupport = clamp(
    max(structure.trunk, sheetSupport * 0.92)
      + filamentSupport * 0.32,
    0.0,
    1.25,
  );

  let materialGrain = smoothstep(0.30, 0.74, detail * 0.62 + fine * 0.38);
  let fracturedSupport = clamp(
    0.16
      + structureSupport * 0.88
      + materialGrain * 0.24,
    0.0,
    1.12,
  );
  let fragmentedDensity = mix(
    1.0,
    fracturedSupport,
    strain * 0.88,
  );

  let expansionLoss = clamp(
    expansionGradient * params.uExpansionDensityLoss.x * 0.22,
    0.0,
    0.84,
  );
  let centerEvacuation = smoothstep(
    params.uTearThreshold.x * 0.55,
    params.uTearThreshold.x + 0.12,
    radialDisplacement,
  )
    * (1.0 - smoothstep(0.12, 0.48, worldRadius))
    * params.uExpansionDensityLoss.x
    * 0.88;
  let offStructureTear = strain
    * (1.0 - clamp(structureSupport, 0.0, 1.0))
    * params.uStrainTearing.x
    * 0.72;

  let fineFilament = mix(
    1.0,
    0.62
      + structure.filament * params.uFineStretchDetail.x * 0.58
      + structure.sheet * params.uSheetStrength.x * 0.18,
    strain,
  );
  let baseDensity = coreEnvelope
    * (0.07 + porous * 0.93)
    * fragmentedDensity
    * fineFilament;
  let densityAfterTear = baseDensity
    * max(
      0.0,
      1.0 - expansionLoss - centerEvacuation - offStructureTear,
    );

  out.density = max(0.0, densityAfterTear * params.uDensity.x);
  out.detail = clamp(
    detail * 0.48
      + fine * 0.20
      + structure.trunk * strain * 0.14
      + structure.sheet * strain * params.uSheetStrength.x * 0.12
      + structure.filament * strain * params.uFineStretchDetail.x * 0.22,
    0.0,
    1.0,
  );
  out.activity = clamp(
    strain
      + length(flow.velocity) * 0.13
      + structure.filament * strain * 0.22,
    0.0,
    1.0,
  );
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

  let hit = intersectSphere(ro, rd, 1.32);
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
      if (length(p) < 1.30) {
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
          let detailLight = 0.64 + volumeSample.detail * 0.58;
          let light = (0.14 + 0.86 * directional * localShadow) * detailLight;
          let rim = pow(1.0 - abs(dot(outward, -rd)), 2.35);
          let sampleColor = gasColor * (
            light
              + rim * (0.10 + volumeSample.activity * 0.22)
              + volumeSample.detail * volumeSample.activity * 0.090
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

    "uDensity": { "type": "float", "default": 0.76, "min": 0.1, "max": 3.0, "step": 0.01, "label": { "zh": "气体密度", "en": "Gas Density" }, "group": { "zh": "体积", "en": "Volume" } },
    "uAbsorption": { "type": "float", "default": 1.18, "min": 0.2, "max": 8.0, "step": 0.01, "label": { "zh": "吸收", "en": "Absorption" }, "group": { "zh": "体积", "en": "Volume" } },

    "uCoreRadius": { "type": "float", "default": 0.40, "min": 0.25, "max": 0.65, "step": 0.005, "label": { "zh": "核心半径", "en": "Core Radius" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uCoreWobble": { "type": "float", "default": 0.17, "min": 0.0, "max": 0.34, "step": 0.005, "label": { "zh": "核心蠕动", "en": "Core Wobble" }, "description": { "zh": "同时驱动核心的三维材质形变和二维低频流场。", "en": "Drives both 3D material deformation and low-frequency 2D flow in the idle core." }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uCoreDetailStrength": { "type": "float", "default": 1.30, "min": 0.0, "max": 2.4, "step": 0.01, "label": { "zh": "表面细节", "en": "Surface Detail" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uNoiseScale": { "type": "float", "default": 4.8, "min": 1.0, "max": 9.0, "step": 0.02, "label": { "zh": "材质分形尺度", "en": "Material Fractal Scale" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uDetailCutoff": { "type": "float", "default": 0.58, "min": 0.18, "max": 0.84, "step": 0.01, "label": { "zh": "内部疏松度", "en": "Internal Porosity" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uTurbulence": { "type": "float", "default": 1.04, "min": 0.0, "max": 2.8, "step": 0.01, "label": { "zh": "翻涌速度", "en": "Rolling Speed" }, "group": { "zh": "核心形态", "en": "Core Shape" } },
    "uExpansion": { "type": "float", "default": 0.09, "min": 0.0, "max": 1.5, "step": 0.01, "label": { "zh": "呼吸扩张", "en": "Breathing Expansion" }, "group": { "zh": "核心形态", "en": "Core Shape" } },

    "uFluidInfluence": { "type": "float", "default": 1.82, "min": 0.0, "max": 3.5, "step": 0.01, "label": { "zh": "材质流形变", "en": "Material Flow Deformation" }, "description": { "zh": "二维位移三平面重建成三维材质运动；爆裂和回收始终是同一团核心物质。", "en": "Reconstructs 2D displacement into 3D material motion; burst and return always deform the same core material." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uMaterialResponse": { "type": "float", "default": 1.28, "min": 0.2, "max": 2.5, "step": 0.01, "label": { "zh": "材质惯性", "en": "Material Response" }, "description": { "zh": "控制速度积累为材质位移的速度。", "en": "Controls how quickly velocity accumulates into material displacement." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uElasticity": { "type": "float", "default": 1.04, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "弹性恢复", "en": "Elastic Restoration" }, "description": { "zh": "直接作用于位移的弹簧恢复力；径向和切向在爆裂阶段采用不同恢复速度。", "en": "A spring force applied directly to displacement, with anisotropic radial/tangential recovery during bursts." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uElasticDamping": { "type": "float", "default": 0.86, "min": 0.0, "max": 4.0, "step": 0.01, "label": { "zh": "弹性阻尼", "en": "Elastic Damping" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uMaxDisplacement": { "type": "float", "default": 0.64, "min": 0.10, "max": 0.95, "step": 0.01, "label": { "zh": "最大位移", "en": "Max Displacement" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uFlowSharpen": { "type": "float", "default": 0.30, "min": 0.0, "max": 1.5, "step": 0.01, "label": { "zh": "流场锐化", "en": "Flow Sharpening" }, "description": { "zh": "轻量反扩散修正，减少平流模糊但避免形成周期网纹。", "en": "A light anti-diffusion correction that preserves motion detail without periodic mesh-like ridges." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uTearThreshold": { "type": "float", "default": 0.075, "min": 0.02, "max": 0.45, "step": 0.005, "label": { "zh": "拉伸撕裂阈值", "en": "Stretch Tear Threshold" }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uStrainTearing": { "type": "float", "default": 1.05, "min": 0.0, "max": 1.8, "step": 0.01, "label": { "zh": "拉伸撕裂", "en": "Strain Tearing" }, "description": { "zh": "只在高拉伸且远离径向主干支撑的位置挖去材质，形成切片和空洞。", "en": "Removes material only in highly stretched regions away from radial trunk support, producing slices and cavities." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uFineStretchDetail": { "type": "float", "default": 0.96, "min": 0.0, "max": 1.5, "step": 0.01, "label": { "zh": "主干细丝", "en": "Trunk Filaments" }, "description": { "zh": "细丝仅沿径向主干和高拉伸区域出现，不再使用全空间周期网格。", "en": "Filaments appear only along radial trunks in stretched material instead of a full-space periodic mesh." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uSheetStrength": { "type": "float", "default": 0.88, "min": 0.0, "max": 1.8, "step": 0.01, "label": { "zh": "撕裂薄片", "en": "Torn Sheets" }, "description": { "zh": "沿径向主干保留宽而薄的流体褶皱。", "en": "Preserves broad, thin fluid sheets attached to the radial trunks." }, "group": { "zh": "材质流", "en": "Material Flow" } },
    "uExpansionDensityLoss": { "type": "float", "default": 1.10, "min": 0.0, "max": 2.0, "step": 0.01, "label": { "zh": "膨胀密度损失", "en": "Expansion Density Loss" }, "description": { "zh": "向外拉伸时降低局部密度并挖空中心，避免只把核心压扁。", "en": "Reduces density under outward expansion and evacuates the center instead of merely flattening the core." }, "group": { "zh": "材质流", "en": "Material Flow" } },

    "uAdvection": { "type": "float", "default": 1.10, "min": 0.1, "max": 2.0, "step": 0.01, "label": { "zh": "平流速度", "en": "Advection" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uViscosity": { "type": "float", "default": 0.045, "min": 0.0, "max": 1.0, "step": 0.005, "label": { "zh": "粘性", "en": "Viscosity" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uVorticity": { "type": "float", "default": 1.08, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "后段卷曲", "en": "Late Vorticity" }, "description": { "zh": "爆裂前段会自动压低涡量，先径向拉开；进入中段后再逐渐卷曲。", "en": "Vorticity is suppressed early so material stretches radially first, then ramps up later to curl the extended structures." }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uVelocityDissipation": { "type": "float", "default": 0.30, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "速度耗散", "en": "Velocity Dissipation" }, "group": { "zh": "二维解算", "en": "2D Solver" } },
    "uSolverSubsteps": { "type": "int", "default": 2, "min": 1, "max": 4, "step": 1, "label": { "zh": "解算子步", "en": "Solver Substeps" }, "group": { "zh": "二维解算", "en": "2D Solver" } },

    "uClickBurstStrength": { "type": "float", "default": 1.42, "min": 0.0, "max": 3.0, "step": 0.01, "label": { "zh": "点击冲击强度", "en": "Click Impact Strength" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uBurstDuration": { "type": "float", "default": 1.85, "min": 0.45, "max": 4.0, "step": 0.01, "label": { "zh": "恢复周期", "en": "Recovery Window" }, "description": { "zh": "用于冲击阶段、卷曲延迟和自动节拍节流；实际回收仍由弹性位移解算完成。", "en": "Controls impact staging, curl delay, and beat throttling; the actual return still comes from the elastic displacement solver." }, "group": { "zh": "冲击", "en": "Impact" } },
    "uBurstForce": { "type": "float", "default": 3.18, "min": 0.0, "max": 5.0, "step": 0.01, "label": { "zh": "径向冲击推力", "en": "Radial Impact Force" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uFractalBranches": { "type": "float", "default": 6.0, "min": 3.0, "max": 8.0, "step": 1.0, "label": { "zh": "径向主干数量", "en": "Radial Trunk Count" }, "description": { "zh": "控制一次爆裂中从中心向外展开的主要方向数量。", "en": "Controls the number of major center-outward directions in each burst." }, "group": { "zh": "冲击", "en": "Impact" } },
    "uBranchSharpness": { "type": "float", "default": 3.6, "min": 1.0, "max": 7.0, "step": 0.1, "label": { "zh": "主干收束度", "en": "Trunk Sharpness" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uBurstReach": { "type": "float", "default": 0.58, "min": 0.20, "max": 0.80, "step": 0.01, "label": { "zh": "径向作用范围", "en": "Radial Reach" }, "group": { "zh": "冲击", "en": "Impact" } },
    "uRadialBias": { "type": "float", "default": 1.35, "min": 0.2, "max": 2.5, "step": 0.01, "label": { "zh": "径向偏置", "en": "Radial Bias" }, "description": { "zh": "提高中心向外的速度分量，减弱爆裂初期的网状横向剪切。", "en": "Strengthens center-outward velocity and suppresses mesh-like lateral shear during the initial burst." }, "group": { "zh": "冲击", "en": "Impact" } },
    "uCurlDelay": { "type": "float", "default": 0.36, "min": 0.05, "max": 0.80, "step": 0.01, "label": { "zh": "卷曲延迟", "en": "Curl Delay" }, "description": { "zh": "爆裂周期达到该比例后才逐渐恢复明显涡量。", "en": "Delays strong vorticity until this fraction of the burst cycle." }, "group": { "zh": "冲击", "en": "Impact" } },

    "uAudioPaused": { "type": "boolean", "default": false, "label": { "zh": "暂停音乐", "en": "Pause Audio" }, "description": { "zh": "暂停音频驱动、自动节拍冲击和波形运动；鼠标点击仍有效。", "en": "Pauses audio drive, automatic beat impacts, and waveform motion; pointer impacts remain active." }, "group": { "zh": "音频", "en": "Audio" } },
    "uAudioBurstEnabled": { "type": "boolean", "default": true, "label": { "zh": "音频触发冲击", "en": "Audio Impact Trigger" }, "group": { "zh": "音频", "en": "Audio" } },
    "uAudioBurstStrength": { "type": "float", "default": 0.84, "min": 0.0, "max": 2.5, "step": 0.01, "label": { "zh": "音频冲击强度", "en": "Audio Impact Strength" }, "group": { "zh": "音频", "en": "Audio" } },
    "uBeatThreshold": { "type": "float", "default": 0.72, "min": 0.45, "max": 0.95, "step": 0.01, "label": { "zh": "节拍阈值", "en": "Beat Threshold" }, "group": { "zh": "音频", "en": "Audio" } },
    "uBeatCooldown": { "type": "float", "default": 1.20, "min": 0.2, "max": 3.0, "step": 0.01, "label": { "zh": "节拍冷却", "en": "Beat Cooldown" }, "group": { "zh": "音频", "en": "Audio" } },
    "uAudioInfluence": { "type": "float", "default": 0.54, "min": 0.0, "max": 2.5, "step": 0.01, "label": { "zh": "音频呼吸", "en": "Audio Breathing" }, "group": { "zh": "音频", "en": "Audio" } },

    "uSteps": { "type": "int", "default": 96, "min": 40, "max": 160, "step": 1, "label": { "zh": "光线步数", "en": "Ray Steps" }, "group": { "zh": "采样", "en": "Sampling" } },
    "uJitter": { "type": "float", "default": 0.15, "min": 0.0, "max": 1.0, "step": 0.01, "label": { "zh": "采样抖动", "en": "Jitter" }, "group": { "zh": "采样", "en": "Sampling" } },
    "uShadow": { "type": "float", "default": 1.25, "min": 0.0, "max": 4.0, "step": 0.01, "label": { "zh": "局部阴影", "en": "Local Shadow" }, "group": { "zh": "光照", "en": "Lighting" } },
    "uGasColor": { "type": "color", "default": "#789dd0", "label": { "zh": "气体颜色", "en": "Gas Color" }, "group": { "zh": "外观", "en": "Appearance" } },
    "uWaveColor": { "type": "color", "default": "#55d8ff", "label": { "zh": "波形颜色", "en": "Wave Color" }, "group": { "zh": "外观", "en": "Appearance" } },
    "uUncappedBenchmark": { "type": "boolean", "default": false, "label": { "zh": "取消帧率限制", "en": "Uncapped Benchmark" }, "group": { "zh": "性能", "en": "Performance" } }
  }
}
@endshaderlab */