#version 300 es
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
uniform float uArcHeight;
uniform float uArcLength;
uniform float uShapeRandomness;
uniform float uFlightDuration;
uniform float uReturnDamping;
uniform float uReturnFrequency;
uniform float uSurfaceWave;
uniform float uParticleSize;
uniform float uRotationSpeed;
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

void main() {
  float id = float(gl_InstanceID);
  float sa = hash11(id * 4.123 + 1.7);
  float sb = hash11(id * 8.711 + 9.2);
  float sc = hash11(id * 1.993 + 5.4);

  vec3 dir = sphereDir(id);
  vec3 spinAxis = safeNorm(vec3(0.18, 1.0, 0.07));
  float latitude = abs(dot(dir, spinAxis));
  float spinRate = mix(0.082, 0.052, latitude) * uRotationSpeed;
  dir = rotateAxis(dir, spinAxis, uTime * spinRate + (sa - 0.5) * 0.045);

  float sphereR = 1.62;
  float baseR = sphereR + (sb - 0.5) * 0.030;

  float bestStrength = 0.0;
  float bestHeight = 0.0;
  float bestSide = 0.0;
  vec3 bestTangent = vec3(1.0, 0.0, 0.0);
  float surfaceResponse = 0.0;
  float postImpact = 0.0;

  // Five independent event lanes. Rate/chance control how often several are alive together.
  for (int i = 0; i < 5; ++i) {
    float fi = float(i);
    float randomPeriod = mix(3.7, 5.4, hash11(fi * 41.7 + 3.1));
    float slotLength = randomPeriod / max(uEruptionRate, 0.15);
    float shiftedTime = uTime + fi * 1.271;
    float slotIndex = floor(shiftedTime / slotLength);
    float slotAge = mod(shiftedTime, slotLength);

    float chanceNoise = hash11(slotIndex * 5.73 + fi * 19.17);
    float enabled = step(chanceNoise, uEruptionChance);
    float startDelay = 0.08 + hash11(slotIndex * 3.11 + fi * 7.77) * 0.24;
    float eventAge = slotAge - startDelay;

    vec3 emitDir = eruptionDir(slotIndex + fi * 9.17, fi);
    vec3 helper = abs(emitDir.y) < 0.92 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangentA = safeNorm(cross(helper, emitDir));
    float orientation = TAU * hash11(slotIndex * 2.71 + fi * 5.19);
    tangentA = rotateAxis(tangentA, emitDir, orientation);
    vec3 tangentB = safeNorm(cross(tangentA, emitDir));

    float facing = dot(dir, emitDir);
    float along = dot(dir, tangentA);
    float across = dot(dir, tangentB);

    // Smooth disturbance footprint. It is intentionally much broader than the emitted filament.
    float localRadius = sqrt(along * along + across * across);
    float influence = 1.0 - smoothstep(uInfluenceRadius * 0.48, uInfluenceRadius, localRadius);
    influence *= smoothstep(0.58, 0.985, facing);

    // A narrow, elongated source tube: thin across, finite along. This prevents the side-view sheet.
    float randomBend = (hash11(slotIndex * 13.7 + fi * 2.1) - 0.5) * uShapeRandomness;
    float centerLine =
      sin(along * mix(14.0, 25.0, sc) + slotIndex * 1.7 + fi) * uRibbonWidth * (0.45 + 0.9 * uShapeRandomness)
      + randomBend * uRibbonWidth * 0.8;
    float crossDistance = abs(across - centerLine);
    float narrowAcross = 1.0 - smoothstep(uRibbonWidth * 0.45, uRibbonWidth, crossDistance);
    float narrowAlong = 1.0 - smoothstep(uRibbonLength * 0.55, uRibbonLength, abs(along));

    // Break the tube into coherent filaments without spreading particles over a whole patch.
    float filamentNoise = 0.62
      + 0.24 * sin(along * 56.0 + sa * 4.0 + slotIndex)
      + 0.14 * sin(along * 91.0 - sc * 8.0 - fi * 2.3);
    float filament = narrowAcross * narrowAlong * smoothstep(0.33, 0.72, filamentNoise);

    // Stagger launch times slightly so many particles occupy different parts of the same arc.
    float launchSpread = mix(0.16, 0.55, uShapeRandomness);
    float particleDelay = sa * launchSpread + abs(along) * 0.32;
    float travelAge = eventAge - particleDelay;
    float p = clamp(travelAge / max(uFlightDuration, 0.15), 0.0, 1.0);
    float travelling = enabled * step(0.0, travelAge) * step(travelAge, uFlightDuration);

    // The arc is a thin parametric tube: both radial and tangential offsets return to zero at landing.
    float arch = pow(max(sin(p * PI), 0.0), 1.08);
    float asymmetry = 1.0 + (hash11(slotIndex * 9.31 + fi * 3.7) - 0.5) * 0.45 * uShapeRandomness;
    float height = uArcHeight * arch * asymmetry;
    float side = uArcLength * sin(p * PI) * (0.72 + 0.28 * sin(p * PI * 0.5));
    side *= mix(-1.0, 1.0, step(0.5, hash11(slotIndex * 8.2 + fi * 7.1)));

    // Smooth post-impact settling. At t=0 residual is exactly zero, so there is no position pop.
    float settleT = max(travelAge - uFlightDuration, 0.0);
    float settleEnvelope = exp(-uReturnDamping * settleT);
    float settling = enabled * step(uFlightDuration, travelAge) * settleEnvelope;
    float residual = sin(settleT * uReturnFrequency * TAU) * settleEnvelope;
    float residualHeight = residual * uSurfaceWave * (0.55 + 0.45 * filament);
    float residualSide = sin(settleT * uReturnFrequency * TAU * 0.83) * settleEnvelope * uSurfaceWave * 0.45;

    float sourceStrength = filament * max(travelling * (0.3 + 0.7 * arch), settling * 0.42);
    if (sourceStrength > bestStrength) {
      bestStrength = sourceStrength;
      bestHeight = height * filament * travelling + residualHeight * filament;
      bestSide = side * filament * travelling + residualSide * filament;
      bestTangent = tangentA;
      postImpact = settling;
    }

    // Broad surrounding particles receive a propagating, damped ripple instead of no response.
    float eventEnvelope = enabled * step(0.0, eventAge);
    float ringPhase = eventAge * 3.2 - localRadius * 18.0;
    float ring = sin(ringPhase) * exp(-max(eventAge, 0.0) * 1.15);
    surfaceResponse += influence * eventEnvelope * ring * uSurfaceWave * 0.32;
  }

  surfaceResponse = clamp(surfaceResponse, -uSurfaceWave, uSurfaceWave);
  vec3 world = dir * (baseR + surfaceResponse + bestHeight) + bestTangent * bestSide;

  vec3 baseColor = vec3(0.83, 0.70, 0.46);
  float colorHeight = clamp((max(bestHeight, 0.0) + abs(bestSide) * 0.45) / max(uArcHeight + uArcLength * 0.45, 0.01), 0.0, 1.0);
  float hue = mix(0.02, 0.88, pow(colorHeight, 0.82));
  vec3 rainbow = hsv2rgb(vec3(hue, 0.82, 1.0));
  float rainbowMix = smoothstep(0.05, 0.24, colorHeight) * clamp(bestStrength * 1.5, 0.0, 1.0);
  vColor = mix(baseColor, rainbow, rainbowMix);

  float tw = 0.5 + 0.5 * sin(uTime * mix(2.0, 6.4, sb) + sa * 61.0);
  vSpark = pow(tw, 9.0) * (0.35 + 0.65 * sc);
  vAlpha = mix(0.17, 0.58, rainbowMix) * (0.76 + 0.24 * sb) * mix(1.0, 0.92, postImpact);
  vSeed = sa;

  float size = mix(0.0082, 0.0120, sb) * uParticleSize;
  size *= mix(1.0, 1.32, rainbowMix) * (1.0 + vSpark * 0.30);
  vec3 billboard = world + (uCamRight * position.x + uCamUp * position.y) * size;
  gl_Position = uViewProj * vec4(billboard, 1.0);
  vUv = position.xy;
}
