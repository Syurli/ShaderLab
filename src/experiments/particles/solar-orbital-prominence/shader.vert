precision highp float;
precision highp int;

in vec3 position;

uniform float uTime;
uniform mat4 uViewProj;
uniform vec3 uCamRight;
uniform vec3 uCamUp;
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
uniform float uReturnDamping;
uniform float uReturnFrequency;
uniform float uSurfaceWave;
uniform float uWaveRange;
uniform float uWaveSpeed;
uniform float uWaveDamping;
uniform float uParticleSize;
uniform float uRotationSpeed;
uniform float uShellCoverage;
uniform float uShellPatternScale;
uniform float uCameraDistance;
uniform float uParticleCount;
uniform vec3 uShellColor;
uniform float uShellBrightness;
uniform float uProminenceHueOffset;
uniform float uProminenceHueSpan;
uniform float uProminenceSaturation;
uniform float uProminenceBrightness;
uniform float uDispersionSeparation;
uniform float uOrbitRotationSpeed;
uniform float uOrbitPullStrength;

out vec2 vUv;
out vec3 vColor;
out float vAlpha;
out float vSpark;
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
  f += sin(dot(p, vec3(1.10, 0.31, 0.82)) * 2.25 * s + 0.80) * 0.42;
  f += sin(dot(p, vec3(-0.54, 1.28, 0.63)) * 3.35 * s - 1.30) * 0.29;
  f += sin(dot(p, vec3(0.91, -0.96, 1.24)) * 4.90 * s + 2.20) * 0.18;
  f += sin((p.x * p.z * 1.75 + p.y * 0.55) * 4.10 * s + 0.40) * 0.11;
  return f;
}

// One continuous orbital filament. Several incommensurate low-frequency terms make the line
// breathe and drift irregularly while keeping the path closed and smooth at every instant.
vec3 orbitCurveDir(float t) {
  float phase = TAU * fract(t);
  float slowA = 0.11 * sin(uTime * 0.173) + 0.045 * sin(uTime * 0.071 + 1.37);
  float slowB = 0.075 * sin(uTime * 0.113 + 2.1) + 0.035 * sin(uTime * 0.047 + 0.4);
  float latitudeAmp = 0.38 + 0.035 * sin(uTime * 0.087) + 0.018 * sin(uTime * 0.031 + 1.8);
  float azimuth = 2.0 * phase
    + 0.026 * sin(4.0 * phase + 0.25 + slowA)
    + 0.014 * sin(3.0 * phase - uTime * 0.061 + slowB);
  float latitude = latitudeAmp * sin(3.0 * phase + 0.30 + slowA)
    + 0.047 * sin(2.0 * phase + uTime * 0.097 + 0.8)
    + 0.026 * sin(6.0 * phase - 0.45 + slowB);
  float cosLat = cos(latitude);
  vec3 p = vec3(
    cosLat * cos(azimuth),
    sin(latitude),
    cosLat * sin(azimuth)
  );
  vec3 spinAxis = safeNorm(vec3(0.18, 1.0, 0.07));
  float irregularSpin = uTime * 0.105 * uOrbitRotationSpeed
    + 0.10 * sin(uTime * 0.083)
    + 0.042 * sin(uTime * 0.037 + 1.1);
  return safeNorm(rotateAxis(p, spinAxis, irregularSpin));
}

vec3 orbitCurveTangent(float t) {
  const float e = 0.0012;
  vec3 p0 = orbitCurveDir(fract(t - e));
  vec3 p1 = orbitCurveDir(fract(t + e));
  vec3 radial = orbitCurveDir(t);
  vec3 tangent = p1 - p0;
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
  vec3 warmWhite = vec3(1.00, 0.99, 0.96);
  vec3 red = vec3(1.00, 0.015, 0.005);
  vec3 orange = vec3(1.00, 0.24, 0.005);
  vec3 gold = vec3(1.00, 0.92, 0.015);
  vec3 green = vec3(0.04, 1.00, 0.16);
  vec3 cyan = vec3(0.00, 0.98, 1.00);
  vec3 blue = vec3(0.015, 0.12, 1.00);
  vec3 violet = vec3(0.78, 0.015, 1.00);

  if (t < 0.06) return mix(warmWhite, red, t / 0.06);
  if (t < 0.18) return mix(red, orange, (t - 0.06) / 0.12);
  if (t < 0.32) return mix(orange, gold, (t - 0.18) / 0.14);
  if (t < 0.47) return mix(gold, green, (t - 0.32) / 0.15);
  if (t < 0.62) return mix(green, cyan, (t - 0.47) / 0.15);
  if (t < 0.80) return mix(cyan, blue, (t - 0.62) / 0.18);
  return mix(blue, violet, (t - 0.80) / 0.20);
}

void main() {
  float id = float(gl_InstanceID);
  float sa = hash11(id * 4.123 + 1.7);
  float sb = hash11(id * 8.711 + 9.2);
  float sc = hash11(id * 1.993 + 5.4);

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
  dir = rotateAxis(dir, spinAxis, uTime * spinRate + (sa - 0.5) * 0.035);

  // About one third smaller in diameter than the previous preset, leaving more room around the
  // bright body for the orbital line and the detached chromatic prominences.
  float baseR = 1.08 + (sb - 0.5) * 0.020;
  vec3 eruptionOffset = vec3(0.0);
  vec3 surfaceShear = vec3(0.0);
  float eruptionVisual = 0.0;
  float surfaceResponse = 0.0;
  float settlingVisual = 0.0;
  float tractionVisual = 0.0;
  vec3 spectrumColorSum = vec3(0.0);
  float spectrumWeight = 0.0;

  for (int i = 0; i < 3; ++i) {
    float fi = float(i);
    float randomPeriod = mix(4.2, 5.8, hash11(fi * 41.7 + 3.1));
    float slotLength = max(randomPeriod / max(uEruptionRate, 0.15), max(uFlightDuration * 0.78, 0.70));
    float shiftedTime = uTime + fi * 1.413;
    float currentSlot = floor(shiftedTime / slotLength);

    for (int h = 0; h < 3; ++h) {
      float eventIndex = currentSlot - float(h);
      float slotLocalAge = shiftedTime - eventIndex * slotLength;
      float enabled = step(hash11(eventIndex * 5.73 + fi * 19.17), uEruptionChance);
      float startDelay = 0.08 + hash11(eventIndex * 3.11 + fi * 7.77) * 0.24;
      float eventAge = slotLocalAge - startDelay;
      enabled *= 1.0 - smoothstep(slotLength * 2.15, slotLength * 2.70, max(eventAge, 0.0));

      vec3 emitDir;
      vec3 tangentA;
      orbitFrame(eventIndex + fi * 9.17, fi, emitDir, tangentA);
      vec3 tangentB = safeNorm(cross(tangentA, emitDir));

      float facing = dot(dir, emitDir);
      float along = dot(dir, tangentA);
      float across = dot(dir, tangentB);
      float localRadius = sqrt(along * along + across * across);
      float influence = (1.0 - smoothstep(uInfluenceRadius * 0.48, uInfluenceRadius, localRadius))
        * smoothstep(0.58, 0.995, facing);

      float randomBend = (hash11(eventIndex * 13.7 + fi * 2.1) - 0.5) * uShapeRandomness;
      float centerLine = sin(along * mix(9.0, 14.0, sc) + eventIndex * 1.13 + fi)
        * uRibbonWidth * (0.18 + 0.42 * uShapeRandomness)
        + randomBend * uRibbonWidth * 0.34;
      float strandOffset = (sa - 0.5) * uRibbonWidth * 0.18;
      float crossDistance = abs(across - centerLine - strandOffset);
      float sourceWidth = max(uRibbonWidth * uSourceExcavation, 0.002);
      float sourceLength = max(uRibbonLength * uSourceExcavation, 0.004);
      float raggedEdge = 1.0 + 0.10 * uShapeRandomness * sin(along * 22.0 + sc * 7.0 + eventIndex);
      float sourceAcross = 1.0 - smoothstep(sourceWidth * 0.72, sourceWidth, crossDistance * raggedEdge);
      float sourceAlong = 1.0 - smoothstep(sourceLength * 0.74, sourceLength, abs(along));
      float sourcePatch = sourceAcross * sourceAlong * shellVisibility;

      float flightDuration = max(uFlightDuration, 0.15);
      float tractionEnvelope = enabled
        * smoothstep(-0.26, 0.08, eventAge)
        * (1.0 - smoothstep(flightDuration * 0.74, flightDuration * 1.04, eventAge));
      float tractionMask = sourcePatch * tractionEnvelope;
      vec3 tractionOffset = dir * (0.012 + uSurfaceWave * 0.24) * uOrbitPullStrength
        + tangentA * 0.018 * uOrbitPullStrength;
      eruptionOffset += tractionOffset * tractionMask;
      tractionVisual += tractionMask;

      float filamentNoise = clamp(
        0.60
        + 0.23 * sin(along * 31.0 + sa * 3.0 + eventIndex)
        + 0.17 * sin(along * 53.0 - sc * 6.0 - fi * 1.7),
        0.0,
        1.0
      );
      float density01 = clamp((uEjectionDensity - 0.5) / 3.5, 0.0, 1.0);
      float threshold = mix(0.58, 0.08, density01);
      float densityMask = smoothstep(
        threshold,
        min(threshold + mix(0.22, 0.13, density01), 0.98),
        filamentNoise
      );
      float liftedSource = sourcePatch * densityMask;

      float particleDelay = sa * mix(0.05, 0.18, uShapeRandomness) + abs(along) * 0.12;
      float travelAge = eventAge - particleDelay;
      float p = clamp(travelAge / flightDuration, 0.0, 1.0);
      float travelling = enabled * step(0.0, travelAge) * step(travelAge, flightDuration);
      float arch = pow(max(sin(p * PI), 0.0), 1.10);
      float asymmetry = 1.0 + (hash11(eventIndex * 9.31 + fi * 3.7) - 0.5) * 0.24 * uShapeRandomness;
      float peelProfile = mix(0.74, 1.0, 1.0 - smoothstep(0.0, sourceWidth, crossDistance));
      float height = uArcHeight * arch * asymmetry * peelProfile;

      float travelSign = mix(-1.0, 1.0, step(0.5, hash11(eventIndex * 8.2 + fi * 7.1)));
      float side = uArcLength * sin(p * PI) * (0.78 + 0.22 * sin(p * PI * 0.5));
      side *= travelSign * (0.78 + 0.34 * uOrbitPullStrength);

      float gather = arch * smoothstep(0.02, 0.28, p);
      float funnel = clamp(0.88 + 0.04 * uShapeRandomness + 0.03 * (uSourceExcavation - 1.0), 0.84, 0.96);
      vec3 gatherOffset = tangentB * (-(across - centerLine) * funnel * gather)
        + tangentA * (-along * 0.16 * gather);
      vec3 tubeOffset = tangentB * ((sa - 0.5) * uRibbonWidth * 0.48 * arch);
      float travelMask = liftedSource * travelling;

      float signedCross = clamp((across - centerLine) / max(sourceWidth, 0.001), -1.0, 1.0);
      float crossCoord = signedCross * 0.5 + 0.5;
      float edgeFringe = smoothstep(0.16, 0.74, abs(signedCross));
      float prismCoord = clamp(
        uProminenceHueOffset
        + (0.01 + 0.92 * crossCoord + 0.10 * p) * uProminenceHueSpan,
        0.0,
        1.0
      );
      vec3 localSpectrum = solarDispersion(prismCoord);
      float chromaStrength = clamp(0.34 + 0.66 * edgeFringe, 0.0, 1.0)
        * clamp(uProminenceSaturation, 0.0, 1.0);
      localSpectrum = mix(vec3(1.0, 0.995, 0.98), localSpectrum, chromaStrength);
      localSpectrum *= uProminenceBrightness;

      // Strong real spatial spectrum separation. The post effect reinforces this again in screen
      // space, so the reference-style RGB fringes remain visible even under additive blending.
      float prismShiftAmount = (0.045 + 0.105 * arch)
        * uDispersionSeparation
        * (prismCoord - 0.5)
        * (0.35 + 0.65 * edgeFringe);
      vec3 prismShift = tangentB * prismShiftAmount;

      eruptionOffset += (
        dir * height
        + tangentA * side
        + gatherOffset
        + tubeOffset
        + prismShift
      ) * travelMask;
      eruptionVisual += travelMask * arch;

      float localSpectrumWeight = travelMask * (0.52 + 0.48 * arch);
      spectrumColorSum += localSpectrum * localSpectrumWeight;
      spectrumWeight += localSpectrumWeight;

      float settleT = max(travelAge - flightDuration, 0.0);
      float settleEnvelope = exp(-uReturnDamping * settleT);
      float settling = enabled * step(flightDuration, travelAge) * settleEnvelope;
      float residual = sin(settleT * uReturnFrequency * TAU) * settleEnvelope;
      float residualSide = sin(settleT * uReturnFrequency * TAU * 0.82) * settleEnvelope;
      float settleMask = liftedSource * settling;
      eruptionOffset += dir * (residual * uSurfaceWave * 0.72 * settleMask)
        + tangentA * (residualSide * uSurfaceWave * 0.18 * settleMask);
      settlingVisual += settleMask * abs(residual);

      float chordDistance = sqrt(max(0.0, 2.0 * (1.0 - clamp(facing, -1.0, 1.0))));
      float waveAge = max(eventAge, 0.0);
      float behindFront = waveAge * uWaveSpeed - chordDistance;
      float reached = step(0.0, behindFront);
      float rangeMask = 1.0 - smoothstep(uWaveRange * 0.80, uWaveRange, chordDistance);
      float waveEnvelope = exp(-uWaveDamping * waveAge) * exp(-max(behindFront, 0.0) * 0.08);
      float detail = 7.0 + 2.4 * uShapeRandomness;
      float phaseWarp = 0.38 * sin(along * detail * 0.68 + across * detail * 0.43 + fi * 1.13)
        + 0.16 * sin((along - across) * detail * 1.22 + sc * 4.0);
      float ringPhase = behindFront * detail + phaseWarp;
      float ring = sin(ringPhase) * waveEnvelope;
      float localKick = influence
        * sin(waveAge * 2.8 - localRadius * detail * 0.86 + phaseWarp)
        * exp(-waveAge * 0.58);
      float waveMask = enabled * step(0.0, eventAge) * reached * rangeMask;
      surfaceResponse += waveMask * ring * uSurfaceWave
        + enabled * step(0.0, eventAge) * localKick * uSurfaceWave * 0.44;

      float shearStrength = waveMask * waveEnvelope * uSurfaceWave * (0.22 + 0.18 * uShapeRandomness);
      surfaceShear += (
        tangentA * cos(ringPhase)
        + tangentB * sin(ringPhase * 0.67 + fi)
      ) * shearStrength;
    }
  }

  surfaceResponse = clamp(surfaceResponse, -uSurfaceWave * 2.4, uSurfaceWave * 2.4);
  surfaceShear = clamp(surfaceShear, vec3(-0.085), vec3(0.085));
  eruptionVisual = clamp(eruptionVisual, 0.0, 1.0);
  settlingVisual = clamp(settlingVisual, 0.0, 1.0);
  tractionVisual = clamp(tractionVisual, 0.0, 1.0);

  vec3 world = dir * (baseR + surfaceResponse) + surfaceShear + eruptionOffset;

  float excursion = length(eruptionOffset);
  vec3 spectrum = spectrumWeight > 0.0001
    ? spectrumColorSum / spectrumWeight
    : vec3(1.0, 0.995, 0.98);

  float spectralPresence = smoothstep(0.0006, 0.009, excursion)
    * clamp(spectrumWeight * 3.1 + eruptionVisual * 1.15, 0.0, 1.0);
  vec3 shellColor = uShellColor * uShellBrightness;
  vec3 rootGlow = vec3(1.0, 0.98, 0.92) * tractionVisual * 0.38 * uProminenceBrightness;
  vColor = mix(shellColor, spectrum, spectralPresence) + rootGlow;

  float tw = 0.5 + 0.5 * sin(uTime * mix(1.8, 5.2, sb) + sa * 61.0);
  vSpark = pow(tw, 10.0) * (0.24 + 0.62 * sc);
  vAlpha = shellVisibility
    * mix(0.34, 0.98, spectralPresence)
    * (0.82 + 0.18 * sb)
    * mix(1.0, 0.95, settlingVisual);
  vSeed = sa;

  float size = mix(0.0058, 0.0085, sb)
    * uParticleSize
    * mix(1.0, 1.18, spectralPresence)
    * (1.0 + vSpark * 0.20);

  vec3 billboard = world + (uCamRight * position.x + uCamUp * position.y) * size;
  gl_Position = uViewProj * vec4(billboard, 1.0);
  vUv = position.xy;
}
