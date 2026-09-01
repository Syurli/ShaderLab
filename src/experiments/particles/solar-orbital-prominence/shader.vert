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
  f += sin(dot(p, vec3(1.37, 0.42, 0.91)) * 3.10 * s + 0.80) * 0.36;
  f += sin(dot(p, vec3(-0.63, 1.51, 0.74)) * 4.70 * s - 1.30) * 0.27;
  f += sin(dot(p, vec3(1.11, -1.24, 1.63)) * 6.90 * s + 2.20) * 0.18;
  f += sin((p.x * p.z * 2.80 + p.y * 0.70) * 5.40 * s + 0.40) * 0.13;
  return f;
}

// One smooth, closed orbital weave. The azimuth always moves forward while the latitude modes
// provide the atomic-orbit crossing pattern without producing hard local reversals.
vec3 orbitCurveDir(float t) {
  float phase = TAU * fract(t);
  float azimuth = 3.0 * phase + 0.085 * sin(6.0 * phase) + 0.025 * sin(12.0 * phase + 0.4);
  float latitude = 0.50 * sin(5.0 * phase + 0.35) + 0.075 * sin(10.0 * phase - 0.55);
  float cosLat = cos(latitude);
  vec3 p = vec3(
    cosLat * cos(azimuth),
    sin(latitude),
    cosLat * sin(azimuth)
  );
  vec3 spinAxis = safeNorm(vec3(0.18, 1.0, 0.07));
  return safeNorm(rotateAxis(p, spinAxis, uTime * 0.18 * uOrbitRotationSpeed));
}

vec3 orbitCurveTangent(float t) {
  const float e = 0.0010;
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
  vec3 warmWhite = vec3(1.00, 0.985, 0.94);
  vec3 redOrange = vec3(1.00, 0.16, 0.025);
  vec3 gold = vec3(1.00, 0.78, 0.055);
  vec3 green = vec3(0.18, 1.00, 0.37);
  vec3 cyan = vec3(0.04, 0.92, 1.00);
  vec3 blue = vec3(0.12, 0.30, 1.00);
  vec3 violet = vec3(0.78, 0.18, 1.00);

  if (t < 0.095) return mix(warmWhite, redOrange, t / 0.095);
  if (t < 0.255) return mix(redOrange, gold, (t - 0.095) / 0.160);
  if (t < 0.425) return mix(gold, green, (t - 0.255) / 0.170);
  if (t < 0.605) return mix(green, cyan, (t - 0.425) / 0.180);
  if (t < 0.805) return mix(cyan, blue, (t - 0.605) / 0.200);
  return mix(blue, violet, (t - 0.805) / 0.195);
}

void main() {
  float id = float(gl_InstanceID);
  float sa = hash11(id * 4.123 + 1.7);
  float sb = hash11(id * 8.711 + 9.2);
  float sc = hash11(id * 1.993 + 5.4);

  vec3 materialDir = sphereDir(id);
  float coverageThreshold = mix(0.40, -0.70, clamp(uShellCoverage, 0.0, 1.0));
  float shellVisibility = smoothstep(
    coverageThreshold - 0.075,
    coverageThreshold + 0.075,
    shellField(materialDir)
  );

  vec3 dir = materialDir;
  vec3 spinAxis = safeNorm(vec3(0.18, 1.0, 0.07));
  float latitude = abs(dot(dir, spinAxis));
  float spinRate = mix(0.082, 0.052, latitude) * uRotationSpeed;
  dir = rotateAxis(dir, spinAxis, uTime * spinRate + (sa - 0.5) * 0.045);

  float baseR = 1.62 + (sb - 0.5) * 0.030;
  vec3 eruptionOffset = vec3(0.0);
  vec3 surfaceShear = vec3(0.0);
  float eruptionVisual = 0.0;
  float surfaceResponse = 0.0;
  float settlingVisual = 0.0;
  float tractionVisual = 0.0;

  vec3 spectrumColorSum = vec3(0.0);
  float spectrumWeight = 0.0;

  for (int i = 0; i < 4; ++i) {
    float fi = float(i);
    float randomPeriod = mix(3.7, 5.4, hash11(fi * 41.7 + 3.1));
    float slotLength = max(randomPeriod / max(uEruptionRate, 0.15), max(uFlightDuration * 0.72, 0.55));
    float shiftedTime = uTime + fi * 1.271;
    float currentSlot = floor(shiftedTime / slotLength);

    for (int h = 0; h < 3; ++h) {
      float eventIndex = currentSlot - float(h);
      float slotLocalAge = shiftedTime - eventIndex * slotLength;
      float enabled = step(hash11(eventIndex * 5.73 + fi * 19.17), uEruptionChance);
      float startDelay = 0.06 + hash11(eventIndex * 3.11 + fi * 7.77) * 0.20;
      float eventAge = slotLocalAge - startDelay;
      enabled *= 1.0 - smoothstep(slotLength * 2.30, slotLength * 2.88, max(eventAge, 0.0));

      vec3 emitDir;
      vec3 tangentA;
      orbitFrame(eventIndex + fi * 9.17, fi, emitDir, tangentA);
      vec3 tangentB = safeNorm(cross(tangentA, emitDir));

      float facing = dot(dir, emitDir);
      float along = dot(dir, tangentA);
      float across = dot(dir, tangentB);
      float localRadius = sqrt(along * along + across * across);
      float influence = (1.0 - smoothstep(uInfluenceRadius * 0.42, uInfluenceRadius, localRadius))
        * smoothstep(0.52, 0.99, facing);

      float randomBend = (hash11(eventIndex * 13.7 + fi * 2.1) - 0.5) * uShapeRandomness;
      float centerLine = sin(along * mix(14.0, 25.0, sc) + eventIndex * 1.7 + fi)
        * uRibbonWidth * (0.35 + 0.75 * uShapeRandomness)
        + randomBend * uRibbonWidth * 0.70;
      float strandOffset = (sa - 0.5) * uRibbonWidth * 0.30;
      float crossDistance = abs(across - centerLine - strandOffset);
      float sourceWidth = max(uRibbonWidth * uSourceExcavation, 0.002);
      float sourceLength = max(uRibbonLength * uSourceExcavation, 0.004);
      float raggedEdge = 1.0 + 0.16 * uShapeRandomness * sin(along * 31.0 + sc * 9.0 + eventIndex * 1.3);
      float sourceAcross = 1.0 - smoothstep(sourceWidth * 0.68, sourceWidth, crossDistance * raggedEdge);
      float sourceAlong = 1.0 - smoothstep(sourceLength * 0.70, sourceLength, abs(along));
      float sourcePatch = sourceAcross * sourceAlong * shellVisibility;

      float flightDuration = max(uFlightDuration, 0.15);
      float tractionEnvelope = enabled
        * smoothstep(-0.22, 0.06, eventAge)
        * (1.0 - smoothstep(flightDuration * 0.72, flightDuration * 1.04, eventAge));
      float tractionMask = sourcePatch * tractionEnvelope;
      vec3 tractionOffset = dir * (0.016 + uSurfaceWave * 0.24) * uOrbitPullStrength
        + tangentA * 0.024 * uOrbitPullStrength;
      eruptionOffset += tractionOffset * tractionMask;
      tractionVisual += tractionMask;

      float filamentNoise = clamp(
        0.56
        + 0.27 * sin(along * 56.0 + sa * 4.0 + eventIndex)
        + 0.17 * sin(along * 91.0 - sc * 8.0 - fi * 2.3),
        0.0,
        1.0
      );
      float density01 = clamp((uEjectionDensity - 0.5) / 3.5, 0.0, 1.0);
      float threshold = mix(0.64, 0.015, density01);
      float densityMask = smoothstep(
        threshold,
        min(threshold + mix(0.24, 0.15, density01), 0.98),
        filamentNoise
      );
      float liftedSource = sourcePatch * densityMask;

      float particleDelay = sa * mix(0.08, 0.34, uShapeRandomness) + abs(along) * 0.18;
      float travelAge = eventAge - particleDelay;
      float p = clamp(travelAge / flightDuration, 0.0, 1.0);
      float travelling = enabled * step(0.0, travelAge) * step(travelAge, flightDuration);
      float arch = pow(max(sin(p * PI), 0.0), 1.08);
      float asymmetry = 1.0 + (hash11(eventIndex * 9.31 + fi * 3.7) - 0.5) * 0.42 * uShapeRandomness;
      float peelProfile = mix(0.58, 1.0, 1.0 - smoothstep(0.0, sourceWidth, crossDistance));
      float height = uArcHeight * arch * asymmetry * peelProfile;

      float travelSign = mix(-1.0, 1.0, step(0.5, hash11(eventIndex * 8.2 + fi * 7.1)));
      float side = uArcLength * sin(p * PI) * (0.70 + 0.30 * sin(p * PI * 0.5));
      side *= travelSign * (0.72 + 0.48 * uOrbitPullStrength);

      float gather = arch * smoothstep(0.015, 0.33, p);
      float funnel = clamp(0.79 + 0.07 * uShapeRandomness + 0.05 * (uSourceExcavation - 1.0), 0.72, 0.95);
      vec3 gatherOffset = tangentB * (-(across - centerLine) * funnel * gather)
        + tangentA * (-along * 0.22 * gather);
      vec3 tubeOffset = tangentB * ((sa - 0.5) * uRibbonWidth * 0.72 * arch);
      float travelMask = liftedSource * travelling;
      eruptionOffset += (dir * height + tangentA * side + gatherOffset + tubeOffset) * travelMask;
      eruptionVisual += travelMask * arch;

      // Reference-style chromatic splitting: color changes mainly across the ribbon width rather
      // than making the entire prominence one height-dependent color. The center remains bright
      // and pale while the torn edges separate into saturated warm/cool fringes.
      float signedCross = clamp((across - centerLine) / max(sourceWidth, 0.001), -1.0, 1.0);
      float crossCoord = signedCross * 0.5 + 0.5;
      float ribbonCoord = clamp(0.5 + 0.5 * along / max(sourceLength, 0.001), 0.0, 1.0);
      float eventBias = (hash11(eventIndex * 4.91 + fi * 2.37) - 0.5) * 0.08;
      float spectralCoord = clamp(
        uProminenceHueOffset
        + (0.06 + 0.62 * crossCoord + 0.22 * p + 0.10 * ribbonCoord + eventBias) * uProminenceHueSpan,
        0.0,
        1.0
      );
      vec3 localSpectrum = solarDispersion(spectralCoord);
      localSpectrum = mix(vec3(1.0), localSpectrum, clamp(uProminenceSaturation, 0.0, 1.0));
      float edgeFringe = smoothstep(0.16, 0.92, abs(signedCross));
      float chromaStrength = clamp(mix(0.46, 1.0, edgeFringe) * uProminenceHueSpan, 0.0, 1.0);
      localSpectrum = mix(vec3(1.0, 0.985, 0.95), localSpectrum, chromaStrength);
      localSpectrum *= uProminenceBrightness;
      float localSpectrumWeight = travelMask * (0.20 + 0.80 * arch);
      spectrumColorSum += localSpectrum * localSpectrumWeight;
      spectrumWeight += localSpectrumWeight;

      float settleT = max(travelAge - flightDuration, 0.0);
      float settleEnvelope = exp(-uReturnDamping * settleT);
      float settling = enabled * step(flightDuration, travelAge) * settleEnvelope;
      float residual = sin(settleT * uReturnFrequency * TAU) * settleEnvelope;
      float residualSide = sin(settleT * uReturnFrequency * TAU * 0.83) * settleEnvelope;
      float settleMask = liftedSource * settling;
      eruptionOffset += dir * (residual * uSurfaceWave * 0.72 * settleMask)
        + tangentA * (residualSide * uSurfaceWave * 0.24 * settleMask);
      settlingVisual += settleMask * abs(residual);

      // Irregular travelling ripples: combine radial wave fronts with a subtle tangent shear so
      // the shell looks stretched/torn rather than behaving like a perfectly concentric sine ring.
      float chordDistance = sqrt(max(0.0, 2.0 * (1.0 - clamp(facing, -1.0, 1.0))));
      float waveAge = max(eventAge, 0.0);
      float behindFront = waveAge * uWaveSpeed - chordDistance;
      float reached = step(0.0, behindFront);
      float rangeMask = 1.0 - smoothstep(uWaveRange * 0.84, uWaveRange, chordDistance);
      float waveEnvelope = exp(-uWaveDamping * waveAge) * exp(-max(behindFront, 0.0) * 0.10);
      float detail = 17.0 + 7.0 * uShapeRandomness;
      float phaseWarp = 0.52 * sin(along * detail * 0.83 + across * detail * 0.49 + fi * 1.31)
        + 0.20 * sin((along - across) * detail * 1.72 + sc * 5.0);
      float ringPhase = behindFront * detail + phaseWarp;
      float ring = sin(ringPhase) * waveEnvelope;
      float localKick = influence
        * sin(waveAge * 4.4 - localRadius * detail * 1.16 + phaseWarp)
        * exp(-waveAge * 0.72);
      float waveMask = enabled * step(0.0, eventAge) * reached * rangeMask;
      surfaceResponse += waveMask * ring * uSurfaceWave
        + enabled * step(0.0, eventAge) * localKick * uSurfaceWave * 0.34;

      float shearStrength = waveMask * waveEnvelope * uSurfaceWave * (0.18 + 0.18 * uShapeRandomness);
      surfaceShear += (
        tangentA * cos(ringPhase)
        + tangentB * sin(ringPhase * 0.73 + fi)
      ) * shearStrength;
    }
  }

  surfaceResponse = clamp(surfaceResponse, -uSurfaceWave * 2.4, uSurfaceWave * 2.4);
  surfaceShear = clamp(surfaceShear, vec3(-0.13), vec3(0.13));
  eruptionVisual = clamp(eruptionVisual, 0.0, 1.0);
  settlingVisual = clamp(settlingVisual, 0.0, 1.0);
  tractionVisual = clamp(tractionVisual, 0.0, 1.0);

  vec3 world = dir * (baseR + surfaceResponse) + surfaceShear + eruptionOffset;

  float excursion = length(eruptionOffset);
  vec3 spectrum = spectrumWeight > 0.0001
    ? spectrumColorSum / spectrumWeight
    : vec3(1.0, 0.985, 0.95);

  float spectralPresence = smoothstep(0.0015, 0.022, excursion)
    * clamp(spectrumWeight * 2.0 + eruptionVisual * 0.92, 0.0, 1.0);
  vec3 shellColor = uShellColor * uShellBrightness;
  vec3 rootGlow = vec3(1.0, 0.95, 0.84) * tractionVisual * 0.44 * uProminenceBrightness;
  vColor = mix(shellColor, spectrum, spectralPresence) + rootGlow;

  float tw = 0.5 + 0.5 * sin(uTime * mix(2.0, 6.4, sb) + sa * 61.0);
  vSpark = pow(tw, 9.0) * (0.28 + 0.72 * sc);
  vAlpha = shellVisibility
    * mix(0.16, 0.84, spectralPresence)
    * (0.77 + 0.23 * sb)
    * mix(1.0, 0.94, settlingVisual);
  vSeed = sa;

  // Smaller, denser-looking grains make the white shell read like the fine reference texture;
  // erupted particles grow only slightly so the line/particle thickness ratio stays delicate.
  float size = mix(0.0062, 0.0092, sb)
    * uParticleSize
    * mix(1.0, 1.18, spectralPresence)
    * (1.0 + vSpark * 0.22);

  vec3 billboard = world + (uCamRight * position.x + uCamUp * position.y) * size;
  gl_Position = uViewProj * vec4(billboard, 1.0);
  vUv = position.xy;
}