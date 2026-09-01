precision highp float;
precision highp int;

in vec3 position;

uniform float uTime;
uniform mat4 uViewProj;
uniform vec3 uCamRight;
uniform vec3 uCamUp;
uniform float uParticleCount;
uniform float uFlareCount;
uniform float uEruptionRate;
uniform float uEruptionChance;
uniform float uInfluenceRadius;
uniform float uRibbonLength;
uniform float uRibbonWidth;
uniform float uEjectionDensity;
uniform float uSourceExcavation;
uniform float uArcHeight;
uniform float uArcLength;
uniform float uShapeRandomness;
uniform float uFlightDuration;
uniform float uSurfaceWave;
uniform float uWaveRange;
uniform float uWaveSpeed;
uniform float uWaveDamping;
uniform float uParticleSize;
uniform float uRotationSpeed;
uniform float uShellCoverage;
uniform float uShellPatternScale;
uniform vec3 uShellColor;
uniform float uShellBrightness;
uniform float uProminenceSaturation;
uniform float uProminenceBrightness;
uniform float uDispersionSeparation;
uniform float uOrbitRotationSpeed;
uniform float uOrbitPullStrength;
uniform float uFlareSize;
uniform float uFlareBrightness;
uniform float uFlareSpread;

out vec2 vUv;
out vec3 vColor;
out float vAlpha;
out float vSpark;
out float vFlare;
flat out float vSeed;

const float PI = 3.141592653589793;
const float TAU = 6.283185307179586;

float hash11(float p) {
  p = fract(p * 0.1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
}

vec3 safeNorm(vec3 v) {
  return v / max(length(v), 0.0001);
}

vec3 rotateAxis(vec3 v, vec3 axis, float a) {
  float s = sin(a);
  float c = cos(a);
  return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

vec3 sphereDir(float id) {
  float z = 1.0 - 2.0 * hash11(id * 1.371 + 0.17);
  float a = TAU * hash11(id * 2.417 + 7.13);
  float r = sqrt(max(0.0, 1.0 - z * z));
  return vec3(r * cos(a), z, r * sin(a));
}

float shellField(vec3 p) {
  float s = max(uShellPatternScale, 0.25);
  float f = 0.0;
  f += sin(dot(p, vec3(1.10, 0.31, 0.82)) * 2.15 * s + 0.80) * 0.43;
  f += sin(dot(p, vec3(-0.54, 1.28, 0.63)) * 3.10 * s - 1.30) * 0.29;
  f += sin(dot(p, vec3(0.91, -0.96, 1.24)) * 4.35 * s + 2.20) * 0.18;
  f += sin((p.x * p.z * 1.62 + p.y * 0.55) * 3.75 * s + 0.40) * 0.10;
  return f;
}

// Must stay aligned with ParticleWebGL2Backend.sampleOrbitDirection().
vec3 orbitCurveDir(float t) {
  float phase = TAU * fract(t);
  float driftA = 0.075 * sin(uTime * 0.137) + 0.031 * sin(uTime * 0.053 + 1.7);
  float driftB = 0.052 * sin(uTime * 0.091 + 2.3) + 0.024 * sin(uTime * 0.039 + 0.6);
  float latitudeAmp = 0.34 + 0.026 * sin(uTime * 0.071) + 0.014 * sin(uTime * 0.029 + 1.3);

  float azimuth = 2.0 * phase
    + 0.020 * sin(3.0 * phase + driftA)
    + 0.009 * sin(5.0 * phase - uTime * 0.043 + driftB);
  float latitude = latitudeAmp * sin(3.0 * phase + 0.28 + driftA)
    + 0.034 * sin(2.0 * phase + uTime * 0.067 + 0.7)
    + 0.014 * sin(5.0 * phase - 0.4 + driftB);

  float cosLat = cos(latitude);
  vec3 p = vec3(cosLat * cos(azimuth), sin(latitude), cosLat * sin(azimuth));
  vec3 spinAxis = safeNorm(vec3(0.18, 1.0, 0.07));
  float irregularSpin = uTime * 0.082 * uOrbitRotationSpeed
    + 0.075 * sin(uTime * 0.061)
    + 0.028 * sin(uTime * 0.027 + 1.2);
  return safeNorm(rotateAxis(p, spinAxis, irregularSpin));
}

vec3 orbitCurveTangent(float t) {
  const float e = 0.0014;
  vec3 radial = orbitCurveDir(t);
  vec3 tangent = orbitCurveDir(fract(t + e)) - orbitCurveDir(fract(t - e));
  tangent -= radial * dot(tangent, radial);
  return safeNorm(tangent);
}

float orbitEventT(float eventId, float lane) {
  return fract(hash11(eventId * 2.713 + lane * 13.17) + lane * 0.173);
}

void orbitFrame(float eventId, float lane, out vec3 radial, out vec3 tangent) {
  float t = orbitEventT(eventId, lane);
  radial = orbitCurveDir(t);
  tangent = orbitCurveTangent(t);
}

vec3 solarDispersion(float t) {
  t = clamp(t, 0.0, 1.0);
  vec3 red = vec3(1.00, 0.025, 0.008);
  vec3 orange = vec3(1.00, 0.30, 0.008);
  vec3 gold = vec3(1.00, 0.94, 0.03);
  vec3 green = vec3(0.05, 1.00, 0.18);
  vec3 cyan = vec3(0.00, 0.98, 1.00);
  vec3 blue = vec3(0.02, 0.14, 1.00);
  vec3 violet = vec3(0.78, 0.02, 1.00);
  if (t < 0.16) return mix(red, orange, t / 0.16);
  if (t < 0.34) return mix(orange, gold, (t - 0.16) / 0.18);
  if (t < 0.50) return mix(gold, green, (t - 0.34) / 0.16);
  if (t < 0.67) return mix(green, cyan, (t - 0.50) / 0.17);
  if (t < 0.84) return mix(cyan, blue, (t - 0.67) / 0.17);
  return mix(blue, violet, (t - 0.84) / 0.16);
}

void eventTiming(float lane, float history, out float eventIndex, out float eventAge, out float enabled) {
  float randomPeriod = mix(4.2, 5.8, hash11(lane * 41.7 + 3.1));
  float slotLength = max(randomPeriod / max(uEruptionRate, 0.15), max(uFlightDuration * 0.78, 0.70));
  float shiftedTime = uTime + lane * 1.413;
  float currentSlot = floor(shiftedTime / slotLength);
  eventIndex = currentSlot - history;
  float slotLocalAge = shiftedTime - eventIndex * slotLength;
  enabled = step(hash11(eventIndex * 5.73 + lane * 19.17), uEruptionChance);
  float startDelay = 0.08 + hash11(eventIndex * 3.11 + lane * 7.77) * 0.24;
  eventAge = slotLocalAge - startDelay;
  enabled *= 1.0 - smoothstep(slotLength * 2.05, slotLength * 2.55, max(eventAge, 0.0));
}

void placeBillboard(vec3 world, float size) {
  vec3 billboard = world + (uCamRight * position.x + uCamUp * position.y) * size;
  gl_Position = uViewProj * vec4(billboard, 1.0);
  vUv = position.xy;
}

void main() {
  float id = float(gl_InstanceID);
  float sa = hash11(id * 4.123 + 1.7);
  float sb = hash11(id * 8.711 + 9.2);
  float sc = hash11(id * 1.993 + 5.4);
  float baseR = 1.08;

  // Extra large chromatic flare particles live after the shell instance range.
  if (id >= uParticleCount) {
    float flareId = id - uParticleCount;
    float lane = mod(floor(flareId), 3.0);
    float history = mod(floor(flareId / 3.0), 2.0);
    float eventIndex;
    float eventAge;
    float enabled;
    eventTiming(lane, history, eventIndex, eventAge, enabled);

    float life = max(uFlightDuration * 1.12, 0.4);
    float p = clamp(eventAge / life, 0.0, 1.0);
    float alive = enabled * step(0.0, eventAge) * step(eventAge, life);
    float fade = 1.0 - smoothstep(0.58, 1.0, p);

    vec3 emitDir;
    vec3 tangentA;
    orbitFrame(eventIndex + lane * 9.17, lane, emitDir, tangentA);
    vec3 tangentB = safeNorm(cross(tangentA, emitDir));

    float rf0 = hash11(flareId * 3.17 + 1.1);
    float rf1 = hash11(flareId * 7.31 + 4.7);
    float rf2 = hash11(flareId * 11.7 + 8.2);
    float plume = pow(max(sin(p * PI), 0.0), 0.72);
    float forward = uArcLength * (0.12 + p * 0.88) * mix(0.35, 1.0, rf0);
    float lift = uArcHeight * plume * mix(0.45, 1.18, rf1);
    float swirl = sin(p * TAU * mix(0.7, 1.6, rf1) + rf2 * TAU) * uFlareSpread;
    float side = (rf0 - 0.5) * uFlareSpread * (0.35 + 1.8 * p);

    vec3 world = emitDir * (baseR + 0.045 + lift)
      + tangentA * (forward + swirl * 0.34)
      + tangentB * (side + swirl * 0.22);

    float spectrumT = fract(rf0 * 0.72 + rf1 * 0.28 + p * 0.16);
    vec3 spectrum = solarDispersion(spectrumT);
    vColor = spectrum * uFlareBrightness;
    vAlpha = alive * fade * mix(0.30, 0.86, rf2);
    vSpark = 0.7 + 0.3 * sin(uTime * 3.0 + rf1 * 12.0);
    vFlare = 1.0;
    vSeed = rf2;
    float size = mix(0.038, 0.095, rf1) * uFlareSize * (0.72 + 0.65 * plume);
    if (vAlpha < 0.001) {
      gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
      vUv = position.xy;
      return;
    }
    placeBillboard(world, size);
    return;
  }

  vec3 materialDir = sphereDir(id);
  float coverageThreshold = mix(0.34, -0.55, clamp(uShellCoverage, 0.0, 1.0));
  float shellVisibility = smoothstep(
    coverageThreshold - 0.12,
    coverageThreshold + 0.055,
    shellField(materialDir)
  );

  vec3 dir = materialDir;
  vec3 spinAxis = safeNorm(vec3(0.18, 1.0, 0.07));
  float latitude = abs(dot(dir, spinAxis));
  float spinRate = mix(0.082, 0.052, latitude) * uRotationSpeed;
  dir = rotateAxis(dir, spinAxis, uTime * spinRate + (sa - 0.5) * 0.032);

  vec3 eruptionOffset = vec3(0.0);
  vec3 surfaceShear = vec3(0.0);
  float surfaceResponse = 0.0;
  float plasmaVisual = 0.0;
  float cutVisual = 0.0;
  vec3 spectrumSum = vec3(0.0);
  float spectrumWeight = 0.0;

  for (int i = 0; i < 3; ++i) {
    float lane = float(i);
    for (int h = 0; h < 3; ++h) {
      float history = float(h);
      float eventIndex;
      float eventAge;
      float enabled;
      eventTiming(lane, history, eventIndex, eventAge, enabled);

      vec3 cutDir;
      vec3 tangentA;
      orbitFrame(eventIndex + lane * 9.17, lane, cutDir, tangentA);
      vec3 tangentB = safeNorm(cross(tangentA, cutDir));

      float facing = dot(dir, cutDir);
      float along = dot(dir, tangentA);
      float across = dot(dir, tangentB);
      float cutLength = max(uRibbonLength * uSourceExcavation, 0.01);
      float cutWidth = max(uRibbonWidth * uSourceExcavation, 0.003);
      float segmentAlong = 1.0 - smoothstep(cutLength * 0.72, cutLength, abs(along));
      float ragged = 1.0 + 0.18 * uShapeRandomness * sin(along * 27.0 + sc * 6.0 + eventIndex);
      float segmentAcross = 1.0 - smoothstep(cutWidth * 0.70, cutWidth, abs(across) * ragged);
      float contact = smoothstep(0.70, 0.997, facing);
      float cutPatch = segmentAlong * segmentAcross * contact * shellVisibility;

      float life = max(uFlightDuration, 0.25);
      float p = clamp(eventAge / life, 0.0, 1.0);
      float active = enabled * step(0.0, eventAge) * step(eventAge, life);
      float cutEnvelope = enabled
        * smoothstep(-0.18, 0.04, eventAge)
        * (1.0 - smoothstep(life * 0.78, life * 1.10, eventAge));

      float filamentNoise = clamp(
        0.62
        + 0.22 * sin(along * 37.0 + sa * 4.0 + eventIndex)
        + 0.16 * sin(across * 81.0 - sc * 5.0 - lane),
        0.0,
        1.0
      );
      float density01 = clamp((uEjectionDensity - 0.5) / 3.5, 0.0, 1.0);
      float densityThreshold = mix(0.62, 0.05, density01);
      float densityMask = smoothstep(densityThreshold, min(densityThreshold + 0.18, 0.98), filamentNoise);
      float detached = cutPatch * densityMask;

      float flame = pow(max(sin(p * PI), 0.0), 0.78) * (1.0 - 0.18 * p);
      float scatterGrow = p * p;
      float travelSign = mix(-1.0, 1.0, step(0.5, hash11(eventIndex * 8.2 + lane * 7.1)));
      float forward = uArcLength * (0.18 + 0.82 * p) * travelSign;
      float lift = uArcHeight * flame * mix(0.72, 1.18, sb);
      float lateral = (sa - 0.5) * uRibbonWidth * (1.2 + 5.0 * scatterGrow) * uShapeRandomness;
      float curl = sin(p * TAU * (0.82 + 0.75 * sc) + sa * TAU + eventIndex)
        * uRibbonWidth * (0.7 + 2.4 * p) * uShapeRandomness;
      float rejoin = smoothstep(0.82, 1.0, p);
      float travelMask = detached * active * (1.0 - rejoin);

      vec3 plumeOffset = dir * lift
        + tangentA * forward
        + tangentB * (lateral + curl);
      eruptionOffset += plumeOffset * travelMask;
      plasmaVisual += travelMask * (0.45 + 0.55 * flame);
      cutVisual += cutPatch * cutEnvelope;

      float signedCross = clamp(across / cutWidth, -1.0, 1.0);
      float spectrumT = clamp(0.5 + signedCross * 0.47 + (sa - 0.5) * 0.08 + p * 0.08, 0.0, 1.0);
      vec3 spectrum = solarDispersion(spectrumT);
      spectrum = mix(vec3(1.0, 0.98, 0.90), spectrum, clamp(uProminenceSaturation, 0.0, 1.0));
      spectrum *= uProminenceBrightness;
      float specWeight = travelMask * (0.42 + 0.58 * flame);
      spectrumSum += spectrum * specWeight;
      spectrumWeight += specWeight;

      // The line cut launches a lateral surface ripple from the entire cutting segment, not from the center.
      float excessAlong = max(abs(along) - cutLength, 0.0);
      float segmentDistance = sqrt(excessAlong * excessAlong + across * across);
      float waveAge = max(eventAge, 0.0);
      float front = waveAge * uWaveSpeed - segmentDistance;
      float reached = step(0.0, front);
      float rangeMask = 1.0 - smoothstep(uWaveRange * 0.78, uWaveRange, segmentDistance);
      float waveEnvelope = exp(-uWaveDamping * waveAge) * exp(-max(front, 0.0) * 0.12);
      float phase = front * (8.0 + 2.0 * uShapeRandomness)
        + 0.55 * sin(along * 9.0 + lane * 1.3)
        + 0.24 * sin(across * 17.0 - sc * 5.0);
      float waveMask = enabled * step(0.0, eventAge) * reached * rangeMask * waveEnvelope;
      surfaceResponse += sin(phase) * waveMask * uSurfaceWave;
      surfaceShear += (
        tangentB * cos(phase)
        + tangentA * sin(phase * 0.61 + lane)
      ) * waveMask * uSurfaceWave * 0.28;
    }
  }

  surfaceResponse = clamp(surfaceResponse, -uSurfaceWave * 2.0, uSurfaceWave * 2.0);
  surfaceShear = clamp(surfaceShear, vec3(-0.075), vec3(0.075));
  plasmaVisual = clamp(plasmaVisual, 0.0, 1.0);
  cutVisual = clamp(cutVisual, 0.0, 1.0);

  vec3 world = dir * (baseR + surfaceResponse) + surfaceShear + eruptionOffset;
  vec3 shellColor = uShellColor * uShellBrightness;
  vec3 plasmaColor = spectrumWeight > 0.0001 ? spectrumSum / spectrumWeight : vec3(1.0, 0.97, 0.88);
  float hotRoot = cutVisual * (1.0 - plasmaVisual) * 0.42;
  vColor = mix(shellColor, plasmaColor, plasmaVisual) + vec3(1.0, 0.86, 0.55) * hotRoot;

  float tw = 0.5 + 0.5 * sin(uTime * mix(1.7, 4.9, sb) + sa * 61.0);
  vSpark = pow(tw, 10.0) * (0.22 + 0.58 * sc) + plasmaVisual * 0.35;
  vFlare = 0.0;
  vSeed = sa;

  // The actual cut source is absent because those same shell instances have been moved into the plume.
  float shellPresence = shellVisibility * (1.0 - cutVisual * (0.70 + 0.30 * uOrbitPullStrength));
  vAlpha = max(shellPresence * (0.40 + 0.16 * sb), plasmaVisual * (0.54 + 0.44 * sb));

  float size = mix(0.0055, 0.0082, sb)
    * uParticleSize
    * mix(1.0, 1.28, plasmaVisual)
    * (1.0 + vSpark * 0.18);
  placeBillboard(world, size);
}
