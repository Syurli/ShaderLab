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

out vec2 vUv;
out vec3 vColor;
out float vAlpha;
out float vSpark;
flat out float vSeed;

const float PI = 3.141592653589793;
const float TAU = 6.283185307179586;
const float GOLDEN = 2.399963229728653;

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

vec3 hsv2rgb(vec3 c) {
  vec3 k = vec3(0.0, 0.6666667, 0.3333333);
  vec3 p = abs(fract(vec3(c.x) + k) * 6.0 - vec3(3.0));
  return c.z * mix(vec3(1.0), clamp(p - vec3(1.0), vec3(0.0), vec3(1.0)), c.y);
}

vec3 sphereDir(float id) {
  float z = 1.0 - 2.0 * hash11(id * 1.371 + 0.17);
  float a = TAU * hash11(id * 2.417 + 7.13);
  float r = sqrt(max(0.0, 1.0 - z * z));
  return vec3(r * cos(a), z, r * sin(a));
}

vec3 eruptionDir(float eventId, float channel) {
  float n = eventId * 1.317 + channel * 17.13;
  float a = n * GOLDEN + 0.52 * sin(n * 0.73);
  float y = 0.66 * sin(n * 1.61803398875 + channel * 0.91);
  float r = sqrt(max(0.0, 1.0 - y * y));
  return safeNorm(vec3(r * cos(a), y, r * sin(a)));
}

// A low-frequency field attached to the material coordinates of the sphere. The mixed
// directional bands create large coherent islands and bays instead of per-particle noise.
float shellField(vec3 p) {
  float s = max(uShellPatternScale, 0.25);
  float f = 0.0;
  f += sin(dot(p, vec3(1.37, 0.42, 0.91)) * 3.10 * s + 0.80) * 0.36;
  f += sin(dot(p, vec3(-0.63, 1.51, 0.74)) * 4.70 * s - 1.30) * 0.27;
  f += sin(dot(p, vec3(1.11, -1.24, 1.63)) * 6.90 * s + 2.20) * 0.18;
  f += sin((p.x * p.z * 2.80 + p.y * 0.70) * 5.40 * s + 0.40) * 0.13;
  return f;
}

void main() {
  float id = float(gl_InstanceID);
  float sa = hash11(id * 4.123 + 1.7);
  float sb = hash11(id * 8.711 + 9.2);
  float sc = hash11(id * 1.993 + 5.4);

  // Build the shell occupancy before rotation so the continent-like pattern is carried by
  // the particles as the sphere rotates, rather than being fixed in world space.
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

  float sphereR = 1.62;
  float baseR = sphereR + (sb - 0.5) * 0.030;

  vec3 eruptionOffset = vec3(0.0);
  float eruptionVisual = 0.0;
  float surfaceResponse = 0.0;
  float settlingVisual = 0.0;

  // Four independent lanes, each keeping the current event plus two historical events.
  // Historical generations fade continuously, so high eruption rates do not snap particles.
  for (int i = 0; i < 4; ++i) {
    float fi = float(i);
    float randomPeriod = mix(3.7, 5.4, hash11(fi * 41.7 + 3.1));
    float slotLength = randomPeriod / max(uEruptionRate, 0.15);
    slotLength = max(slotLength, max(uFlightDuration * 0.72, 0.55));

    float shiftedTime = uTime + fi * 1.271;
    float currentSlot = floor(shiftedTime / slotLength);

    for (int h = 0; h < 3; ++h) {
      float fh = float(h);
      float eventIndex = currentSlot - fh;
      float slotLocalAge = shiftedTime - eventIndex * slotLength;

      float chanceNoise = hash11(eventIndex * 5.73 + fi * 19.17);
      float enabled = step(chanceNoise, uEruptionChance);
      float startDelay = 0.06 + hash11(eventIndex * 3.11 + fi * 7.77) * 0.20;
      float eventAge = slotLocalAge - startDelay;
      float historyFade = 1.0 - smoothstep(slotLength * 2.30, slotLength * 2.88, max(eventAge, 0.0));
      enabled *= historyFade;

      vec3 emitDir = eruptionDir(eventIndex + fi * 9.17, fi);
      vec3 helper = abs(emitDir.y) < 0.92 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
      vec3 tangentA = safeNorm(cross(helper, emitDir));
      float orientation = TAU * hash11(eventIndex * 2.71 + fi * 5.19);
      tangentA = rotateAxis(tangentA, emitDir, orientation);
      vec3 tangentB = safeNorm(cross(tangentA, emitDir));

      float facing = dot(dir, emitDir);
      float along = dot(dir, tangentA);
      float across = dot(dir, tangentB);
      float localRadius = sqrt(along * along + across * across);

      float influence = 1.0 - smoothstep(uInfluenceRadius * 0.42, uInfluenceRadius, localRadius);
      influence *= smoothstep(0.52, 0.99, facing);

      float randomBend = (hash11(eventIndex * 13.7 + fi * 2.1) - 0.5) * uShapeRandomness;
      float centerLine =
        sin(along * mix(14.0, 25.0, sc) + eventIndex * 1.7 + fi) * uRibbonWidth * (0.35 + 0.75 * uShapeRandomness)
        + randomBend * uRibbonWidth * 0.70;
      float strandOffset = (sa - 0.5) * uRibbonWidth * 0.30;
      float crossDistance = abs(across - centerLine - strandOffset);

      // The visible source is deliberately broader than the final filament. These are the
      // actual shell particles that are peeled away, so their previous positions become a
      // real hole. As they rise, the tangential gather below funnels them into a narrow arc.
      float sourceWidth = max(uRibbonWidth * uSourceExcavation, 0.002);
      float sourceLength = max(uRibbonLength * uSourceExcavation, 0.004);
      float raggedEdge = 1.0 + 0.16 * uShapeRandomness * sin(along * 31.0 + sc * 9.0 + eventIndex * 1.3);
      float sourceAcross = 1.0 - smoothstep(sourceWidth * 0.68, sourceWidth, crossDistance * raggedEdge);
      float sourceAlong = 1.0 - smoothstep(sourceLength * 0.70, sourceLength, abs(along));
      float sourcePatch = sourceAcross * sourceAlong * shellVisibility;

      float filamentNoise = clamp(
        0.56
        + 0.27 * sin(along * 56.0 + sa * 4.0 + eventIndex)
        + 0.17 * sin(along * 91.0 - sc * 8.0 - fi * 2.3),
        0.0,
        1.0
      );
      float density01 = clamp((uEjectionDensity - 0.5) / 3.5, 0.0, 1.0);
      float densityThreshold = mix(0.64, 0.015, density01);
      float densityMask = smoothstep(
        densityThreshold,
        min(densityThreshold + mix(0.24, 0.15, density01), 0.98),
        filamentNoise
      );
      float liftedSource = sourcePatch * densityMask;

      float launchSpread = mix(0.08, 0.34, uShapeRandomness);
      float particleDelay = sa * launchSpread + abs(along) * 0.18;
      float travelAge = eventAge - particleDelay;
      float flightDuration = max(uFlightDuration, 0.15);
      float p = clamp(travelAge / flightDuration, 0.0, 1.0);
      float travelling = enabled * step(0.0, travelAge) * step(travelAge, flightDuration);

      float arch = pow(max(sin(p * PI), 0.0), 1.08);
      float asymmetry = 1.0 + (hash11(eventIndex * 9.31 + fi * 3.7) - 0.5) * 0.42 * uShapeRandomness;

      // Edge particles rise slightly less than the center, making the source read as a patch
      // being lifted and curled rather than a rigid sheet translating outward.
      float coreAcross = 1.0 - smoothstep(0.0, sourceWidth, crossDistance);
      float peelProfile = mix(0.58, 1.0, coreAcross);
      float height = uArcHeight * arch * asymmetry * peelProfile;

      float side = uArcLength * sin(p * PI) * (0.70 + 0.30 * sin(p * PI * 0.5));
      side *= mix(-1.0, 1.0, step(0.5, hash11(eventIndex * 8.2 + fi * 7.1)));
      side *= 0.90 + 0.10 * clamp(along / max(sourceLength, 0.001), -1.0, 1.0);

      // Funnel the broad lifted patch into a compact three-dimensional filament during the
      // rise. Multiplication by arch guarantees that the gather offset is also zero at launch
      // and landing, preserving exact positional continuity.
      float gather = arch * smoothstep(0.015, 0.33, p);
      float funnelStrength = clamp(0.76 + 0.10 * uShapeRandomness + 0.06 * (uSourceExcavation - 1.0), 0.68, 0.94);
      vec3 gatherOffset =
        tangentB * (-(across - centerLine) * funnelStrength * gather)
        + tangentA * (-along * 0.22 * gather);

      float twist = (sa - 0.5) * uRibbonWidth * 0.90 * arch;
      vec3 tubeOffset = tangentB * twist;

      float travelMask = liftedSource * travelling;
      vec3 prominenceOffset = dir * height + tangentA * side + gatherOffset + tubeOffset;
      eruptionOffset += prominenceOffset * travelMask;
      eruptionVisual += travelMask * arch;

      // The same source particles settle back into their original material positions with a
      // damped residual motion. There is no separate static shell copy beneath the eruption.
      float settleT = max(travelAge - flightDuration, 0.0);
      float settleEnvelope = exp(-uReturnDamping * settleT);
      float settling = enabled * step(flightDuration, travelAge) * settleEnvelope;
      float residual = sin(settleT * uReturnFrequency * TAU) * settleEnvelope;
      float residualSide = sin(settleT * uReturnFrequency * TAU * 0.83) * settleEnvelope;
      float settleMask = liftedSource * settling;
      eruptionOffset += dir * (residual * uSurfaceWave * 0.72 * settleMask);
      eruptionOffset += tangentA * (residualSide * uSurfaceWave * 0.24 * settleMask);
      settlingVisual += settleMask * abs(residual);

      // Water-like travelling spherical waves still propagate through the occupied parts of
      // the shell; the continent holes remain holes instead of being filled by the wave field.
      float chordDistance = sqrt(max(0.0, 2.0 * (1.0 - clamp(facing, -1.0, 1.0))));
      float waveAge = max(eventAge, 0.0);
      float waveFront = waveAge * uWaveSpeed;
      float behindFront = waveFront - chordDistance;
      float reached = step(0.0, behindFront);
      float rangeMask = 1.0 - smoothstep(uWaveRange * 0.84, uWaveRange, chordDistance);
      float waveEnvelope = exp(-uWaveDamping * waveAge) * exp(-max(behindFront, 0.0) * 0.12);
      float ring = sin(behindFront * 14.0 + fi * 0.71) * waveEnvelope;
      float localKick = influence * sin(waveAge * 4.2 - localRadius * 20.0) * exp(-waveAge * 0.85);
      surfaceResponse += enabled * step(0.0, eventAge) * (
        ring * reached * rangeMask * uSurfaceWave
        + localKick * uSurfaceWave * 0.30
      );
    }
  }

  surfaceResponse = clamp(surfaceResponse, -uSurfaceWave * 2.4, uSurfaceWave * 2.4);
  eruptionVisual = clamp(eruptionVisual, 0.0, 1.0);
  settlingVisual = clamp(settlingVisual, 0.0, 1.0);

  vec3 world = dir * (baseR + surfaceResponse) + eruptionOffset;

  vec3 baseColor = vec3(1.0);
  float excursion = length(eruptionOffset);
  float colorHeight = clamp(excursion / max(uArcHeight + uArcLength * 0.55, 0.01), 0.0, 1.0);
  float hue = mix(0.01, 0.88, pow(colorHeight, 0.78));
  vec3 rainbow = hsv2rgb(vec3(hue, 0.92, 1.0));
  float rainbowMix = smoothstep(0.018, 0.16, colorHeight) * eruptionVisual;
  vColor = mix(baseColor, rainbow, rainbowMix);

  float tw = 0.5 + 0.5 * sin(uTime * mix(2.0, 6.4, sb) + sa * 61.0);
  vSpark = pow(tw, 9.0) * (0.30 + 0.70 * sc);
  vAlpha = shellVisibility * mix(0.13, 0.72, rainbowMix) * (0.78 + 0.22 * sb) * mix(1.0, 0.94, settlingVisual);
  vSeed = sa;

  float size = mix(0.0078, 0.0115, sb) * uParticleSize;
  size *= mix(1.0, 1.30, rainbowMix) * (1.0 + vSpark * 0.28);
  vec3 billboard = world + (uCamRight * position.x + uCamUp * position.y) * size;
  gl_Position = uViewProj * vec4(billboard, 1.0);
  vUv = position.xy;
}
