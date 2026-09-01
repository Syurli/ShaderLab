import * as THREE from 'three';
import type { ParameterValues } from '../core/types';
import type { BackendSurfaceInfo, PointerState, RendererBackend, RendererBackendOptions } from './RendererBackend';

function toUniformValue(value: number | boolean | string, type: string) {
  if (type === 'color') return new THREE.Color(String(value));
  return value;
}

function withGlsl3Version(source: string) {
  return /^\s*#version\s+300\s+es\b/.test(source) ? source : `#version 300 es\n${source}`;
}

function compileShader(gl: WebGL2RenderingContext, type: number, source: string, label: string) {
  const shader = gl.createShader(type);
  if (!shader) throw new Error(`[ParticleWebGL2] Failed to create ${label} shader.`);
  gl.shaderSource(shader, withGlsl3Version(source));
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const log = gl.getShaderInfoLog(shader) || 'Unknown GLSL compiler error.';
    gl.deleteShader(shader);
    throw new Error(`[ParticleWebGL2] ${label} shader compile failed:\n${log}`);
  }
  return shader;
}

function validateShaderProgram(gl: WebGL2RenderingContext, vertexSource: string, fragmentSource: string) {
  const vertex = compileShader(gl, gl.VERTEX_SHADER, vertexSource, 'vertex');
  const fragment = compileShader(gl, gl.FRAGMENT_SHADER, fragmentSource, 'fragment');
  const program = gl.createProgram();
  if (!program) throw new Error('[ParticleWebGL2] Failed to create validation program.');
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  const linked = gl.getProgramParameter(program, gl.LINK_STATUS);
  const log = gl.getProgramInfoLog(program) || '';
  gl.deleteProgram(program);
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);
  if (!linked) throw new Error(`[ParticleWebGL2] Shader program link failed:\n${log || 'Unknown GLSL linker error.'}`);
}

const TAU = Math.PI * 2;
const ORBIT_AXIS = new THREE.Vector3(0.18, 1.0, 0.07).normalize();
const ORBIT_SEGMENTS = 512;
const ORBIT_SIDES = 4;
// Active cutter segments are intentionally pulled below the 1.08 particle-shell radius.
const ORBIT_SHELL_TARGET_RADIUS = 0.90;

function fract(value: number) {
  return value - Math.floor(value);
}

function hash11(value: number) {
  let p = fract(value * 0.1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
}

function smoothstep(edge0: number, edge1: number, value: number) {
  const t = THREE.MathUtils.clamp((value - edge0) / Math.max(edge1 - edge0, 1e-6), 0, 1);
  return t * t * (3 - 2 * t);
}

function orbitEventT(eventId: number, lane: number) {
  return fract(hash11(eventId * 2.713 + lane * 13.17) + lane * 0.173);
}

// Must match orbitCurveDir() in particle experiment shaders.
function sampleOrbitDirection(
  t: number,
  elapsedSeconds: number,
  rotationSpeed: number,
  target: THREE.Vector3,
) {
  const phase = TAU * fract(t);
  const driftA = 0.075 * Math.sin(elapsedSeconds * 0.137)
    + 0.031 * Math.sin(elapsedSeconds * 0.053 + 1.7);
  const driftB = 0.052 * Math.sin(elapsedSeconds * 0.091 + 2.3)
    + 0.024 * Math.sin(elapsedSeconds * 0.039 + 0.6);
  const latitudeAmp = 0.34
    + 0.026 * Math.sin(elapsedSeconds * 0.071)
    + 0.014 * Math.sin(elapsedSeconds * 0.029 + 1.3);

  const azimuth = 2.0 * phase
    + 0.020 * Math.sin(3.0 * phase + driftA)
    + 0.009 * Math.sin(5.0 * phase - elapsedSeconds * 0.043 + driftB);
  const latitude = latitudeAmp * Math.sin(3.0 * phase + 0.28 + driftA)
    + 0.034 * Math.sin(2.0 * phase + elapsedSeconds * 0.067 + 0.7)
    + 0.014 * Math.sin(5.0 * phase - 0.4 + driftB);

  const cosLat = Math.cos(latitude);
  target.set(
    cosLat * Math.cos(azimuth),
    Math.sin(latitude),
    cosLat * Math.sin(azimuth),
  );

  const irregularSpin = elapsedSeconds * 0.082 * rotationSpeed
    + 0.075 * Math.sin(elapsedSeconds * 0.061)
    + 0.028 * Math.sin(elapsedSeconds * 0.027 + 1.2);
  target.applyAxisAngle(ORBIT_AXIS, irregularSpin);
  return target.normalize();
}

function sampleSolarDispersion(t: number, target: THREE.Color) {
  const x = THREE.MathUtils.clamp(t, 0, 1);
  const stops = [
    { t: 0.00, c: new THREE.Color(1.00, 0.99, 0.96) },
    { t: 0.15, c: new THREE.Color(1.00, 0.18, 0.02) },
    { t: 0.34, c: new THREE.Color(1.00, 0.88, 0.04) },
    { t: 0.52, c: new THREE.Color(0.10, 1.00, 0.24) },
    { t: 0.70, c: new THREE.Color(0.02, 0.92, 1.00) },
    { t: 0.86, c: new THREE.Color(0.05, 0.18, 1.00) },
    { t: 1.00, c: new THREE.Color(0.72, 0.04, 1.00) },
  ];

  for (let i = 0; i < stops.length - 1; i += 1) {
    const a = stops[i];
    const b = stops[i + 1];
    if (x <= b.t) {
      const u = (x - a.t) / Math.max(b.t - a.t, 1e-6);
      return target.copy(a.c).lerp(b.c, THREE.MathUtils.clamp(u, 0, 1));
    }
  }
  return target.copy(stops[stops.length - 1].c);
}

interface ActiveOrbitEvent {
  t: number;
  strength: number;
}

export class ParticleWebGL2Backend implements RendererBackend {
  readonly id = 'particle-webgl2';
  private readonly canvas: HTMLCanvasElement;
  private readonly experiment: RendererBackendOptions['experiment'];
  private readonly uniforms: Record<string, THREE.IUniform> = {};
  private readonly viewProj = new THREE.Matrix4();
  private renderer?: THREE.WebGLRenderer;
  private scene?: THREE.Scene;
  private camera?: THREE.PerspectiveCamera;
  private geometry?: THREE.InstancedBufferGeometry;
  private material?: THREE.RawShaderMaterial;
  private mesh?: THREE.Mesh;
  private orbitGeometry?: THREE.BufferGeometry;
  private orbitMaterial?: THREE.MeshBasicMaterial;
  private orbitMesh?: THREE.Mesh;
  private orbitPositionAttribute?: THREE.BufferAttribute;
  private orbitColorAttribute?: THREE.BufferAttribute;
  private width = 1;
  private height = 1;
  private yaw = 0.55;
  private pitch = 0.18;
  private pointerDown = false;

  constructor(options: RendererBackendOptions) {
    this.canvas = options.canvas;
    this.experiment = options.experiment;
  }

  async initialize() {
    if (!this.experiment.vertexShader || !this.experiment.fragmentShader) {
      throw new Error('Particle WebGL2 experiments require vertexShader and fragmentShader sources.');
    }

    this.renderer = new THREE.WebGLRenderer({
      canvas: this.canvas,
      antialias: false,
      powerPreference: 'high-performance',
    });
    this.renderer.setClearColor(0x050506, 1);
    validateShaderProgram(
      this.renderer.getContext() as WebGL2RenderingContext,
      this.experiment.vertexShader,
      this.experiment.fragmentShader,
    );

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(47, 1, 0.05, 30);
    this.geometry = new THREE.InstancedBufferGeometry();
    this.geometry.setAttribute(
      'position',
      new THREE.Float32BufferAttribute([-1,-1,0, 1,-1,0, -1,1,0, 1,1,0], 3),
    );
    this.geometry.setIndex([0,1,2,2,1,3]);
    this.geometry.instanceCount = 1;

    this.uniforms.uTime = { value: 0 };
    this.uniforms.uViewProj = { value: this.viewProj };
    this.uniforms.uCamRight = { value: new THREE.Vector3(1,0,0) };
    this.uniforms.uCamUp = { value: new THREE.Vector3(0,1,0) };
    Object.entries(this.experiment.metadata.parameters).forEach(([name, config]) => {
      this.uniforms[name] = { value: toUniformValue(config.default, config.type) };
    });

    this.material = new THREE.RawShaderMaterial({
      vertexShader: this.experiment.vertexShader,
      fragmentShader: this.experiment.fragmentShader,
      uniforms: this.uniforms,
      glslVersion: THREE.GLSL3,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      depthTest: false,
    });

    this.mesh = new THREE.Mesh(this.geometry, this.material);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 1;
    this.scene.add(this.mesh);

    if (this.experiment.metadata.parameters.uOrbitRadius) this.createOrbitTube();
    this.setParameters(Object.fromEntries(
      Object.entries(this.experiment.metadata.parameters).map(([name, config]) => [name, config.default]),
    ));
  }

  private createOrbitTube() {
    if (!this.scene) return;

    const vertexCount = ORBIT_SEGMENTS * ORBIT_SIDES;
    const positions = new Float32Array(vertexCount * 3);
    const colors = new Float32Array(vertexCount * 3);
    const indices = new Uint16Array(ORBIT_SEGMENTS * ORBIT_SIDES * 6);

    let cursor = 0;
    for (let segment = 0; segment < ORBIT_SEGMENTS; segment += 1) {
      const next = (segment + 1) % ORBIT_SEGMENTS;
      for (let side = 0; side < ORBIT_SIDES; side += 1) {
        const nextSide = (side + 1) % ORBIT_SIDES;
        const a = segment * ORBIT_SIDES + side;
        const b = next * ORBIT_SIDES + side;
        const c = next * ORBIT_SIDES + nextSide;
        const d = segment * ORBIT_SIDES + nextSide;
        indices[cursor++] = a;
        indices[cursor++] = b;
        indices[cursor++] = d;
        indices[cursor++] = b;
        indices[cursor++] = c;
        indices[cursor++] = d;
      }
    }

    this.orbitPositionAttribute = new THREE.BufferAttribute(positions, 3).setUsage(THREE.DynamicDrawUsage);
    this.orbitColorAttribute = new THREE.BufferAttribute(colors, 3).setUsage(THREE.DynamicDrawUsage);
    this.orbitGeometry = new THREE.BufferGeometry();
    this.orbitGeometry.setAttribute('position', this.orbitPositionAttribute);
    this.orbitGeometry.setAttribute('color', this.orbitColorAttribute);
    this.orbitGeometry.setIndex(new THREE.BufferAttribute(indices, 1));

    this.orbitMaterial = new THREE.MeshBasicMaterial({
      color: 0xffffff,
      vertexColors: true,
      transparent: true,
      opacity: 0.22,
      blending: THREE.AdditiveBlending,
      depthTest: false,
      depthWrite: false,
      side: THREE.DoubleSide,
      toneMapped: false,
    });

    this.orbitMesh = new THREE.Mesh(this.orbitGeometry, this.orbitMaterial);
    this.orbitMesh.frustumCulled = false;
    this.orbitMesh.renderOrder = 3;
    this.scene.add(this.orbitMesh);
    this.updateOrbitTube(0);
  }

  private collectActiveOrbitEvents(elapsedSeconds: number): ActiveOrbitEvent[] {
    const events: ActiveOrbitEvent[] = [];
    const eruptionRate = Number(this.uniforms.uEruptionRate?.value ?? 1.7);
    const eruptionChance = Number(this.uniforms.uEruptionChance?.value ?? 0.78);
    const flightDuration = Math.max(Number(this.uniforms.uFlightDuration?.value ?? 2.1), 0.15);
    const settleDuration = Math.max(0.70, flightDuration * 0.50);

    for (let lane = 0; lane < 3; lane += 1) {
      const fi = lane;
      const randomPeriod = THREE.MathUtils.lerp(4.2, 5.8, hash11(fi * 41.7 + 3.1));
      const slotLength = Math.max(
        randomPeriod / Math.max(eruptionRate, 0.15),
        Math.max(flightDuration * 0.78, 0.70),
      );
      const shiftedTime = elapsedSeconds + fi * 1.413;
      const currentSlot = Math.floor(shiftedTime / slotLength);

      for (let history = 0; history < 3; history += 1) {
        const eventIndex = currentSlot - history;
        const slotLocalAge = shiftedTime - eventIndex * slotLength;
        const enabled = hash11(eventIndex * 5.73 + fi * 19.17) <= eruptionChance ? 1 : 0;
        if (!enabled) continue;

        const startDelay = 0.08 + hash11(eventIndex * 3.11 + fi * 7.77) * 0.24;
        const eventAge = slotLocalAge - startDelay;
        const historyFade = 1 - smoothstep(slotLength * 2.20, slotLength * 2.85, Math.max(eventAge, 0));
        const engage = smoothstep(-0.38, 0.14, eventAge);
        const release = 1 - smoothstep(
          flightDuration * 0.68,
          flightDuration + settleDuration * 0.32,
          eventAge,
        );
        const strength = historyFade * engage * release;
        if (strength <= 0.001) continue;

        events.push({
          t: orbitEventT(eventIndex + fi * 9.17, fi),
          strength,
        });
      }
    }

    return events;
  }

  private orbitEventWeight(t: number, events: ActiveOrbitEvent[], width: number) {
    let accumulated = 0;
    const safeWidth = Math.max(width, 0.005);
    for (const event of events) {
      const rawDistance = Math.abs(t - event.t);
      const distance = Math.min(rawDistance, 1 - rawDistance);
      const local = (1 - smoothstep(0, safeWidth, distance)) * event.strength;
      accumulated += local;
    }
    // Smooth-union overlapping event segments instead of switching abruptly via max().
    return 1 - Math.exp(-2.5 * accumulated);
  }

  private updateOrbitTube(elapsedSeconds: number) {
    if (!this.orbitPositionAttribute || !this.orbitColorAttribute) return;

    const positions = this.orbitPositionAttribute.array as Float32Array;
    const colors = this.orbitColorAttribute.array as Float32Array;
    const radius = Number(this.uniforms.uOrbitRadius?.value ?? 1.62);
    const pulse = Number(this.uniforms.uOrbitPulse?.value ?? 0.020);
    const rotationSpeed = Number(this.uniforms.uOrbitRotationSpeed?.value ?? 0.48);
    const thickness = Number(this.uniforms.uOrbitThickness?.value ?? 0.0009);
    const pullStrength = Number(this.uniforms.uOrbitPullStrength?.value ?? 0.80);
    const influenceWidth = Number(this.uniforms.uOrbitInfluenceWidth?.value ?? 0.07);
    const highlightStrength = Number(this.uniforms.uOrbitHighlightStrength?.value ?? 1.35);
    const orbitColor = this.uniforms.uOrbitLineColor?.value as THREE.Color | undefined;
    const brightness = Number(this.uniforms.uOrbitLineBrightness?.value ?? 0.62);
    const events = this.collectActiveOrbitEvents(elapsedSeconds);

    const dir = new THREE.Vector3();
    const previous = new THREE.Vector3();
    const next = new THREE.Vector3();
    const tangent = new THREE.Vector3();
    const frameNormal = new THREE.Vector3();
    const frameBinormal = new THREE.Vector3();
    const center = new THREE.Vector3();
    const vertex = new THREE.Vector3();
    const spectral = new THREE.Color();
    const neutral = new THREE.Color();
    const finalColor = new THREE.Color();
    const tangentStep = 0.9 / ORBIT_SEGMENTS;
    const sourceColor = orbitColor ?? new THREE.Color(1, 1, 1);

    for (let segment = 0; segment < ORBIT_SEGMENTS; segment += 1) {
      const t = segment / ORBIT_SEGMENTS;
      const eventWeight = this.orbitEventWeight(t, events, influenceWidth);
      const irregularPulse =
        0.48 * Math.sin(elapsedSeconds * 0.247 + t * TAU * 1.1)
        + 0.31 * Math.sin(elapsedSeconds * 0.109 - t * TAU * 1.8 + 1.4)
        + 0.21 * Math.sin(elapsedSeconds * 0.047 + t * TAU * 0.63 + 2.6);
      const normalRadius = radius * (1 + pulse * irregularPulse);
      const easedEventWeight = eventWeight * eventWeight * (3 - 2 * eventWeight);
      const pullAmount = THREE.MathUtils.clamp(easedEventWeight * pullStrength * 0.98, 0, 1);
      const localRadius = THREE.MathUtils.lerp(normalRadius, ORBIT_SHELL_TARGET_RADIUS, pullAmount);

      sampleOrbitDirection(t, elapsedSeconds, rotationSpeed, dir);
      sampleOrbitDirection(t - tangentStep, elapsedSeconds, rotationSpeed, previous);
      sampleOrbitDirection(t + tangentStep, elapsedSeconds, rotationSpeed, next);
      tangent.subVectors(next, previous);
      tangent.addScaledVector(dir, -tangent.dot(dir));
      if (tangent.lengthSq() < 1e-10) tangent.set(-dir.z, 0, dir.x);
      tangent.normalize();

      frameBinormal.crossVectors(tangent, dir);
      if (frameBinormal.lengthSq() < 1e-10) frameBinormal.set(0, 1, 0).cross(dir);
      frameBinormal.normalize();
      frameNormal.crossVectors(frameBinormal, tangent).normalize();
      center.copy(dir).multiplyScalar(localRadius);

      const baseVariation = 0.50
        + 0.055 * Math.sin(t * TAU * 3.0 - elapsedSeconds * 0.11)
        + 0.025 * Math.sin(t * TAU * 5.0 + elapsedSeconds * 0.049);
      const highlight = Math.min(1 + highlightStrength * eventWeight * 0.55, 1.9);
      const localThickness = thickness * (1 + 0.05 * Math.sin(t * TAU * 2.0 + elapsedSeconds * 0.07));

      neutral.copy(sourceColor).multiplyScalar(brightness * baseVariation * highlight);
      const spectralT = fract(t * 0.9 + elapsedSeconds * 0.006);
      sampleSolarDispersion(spectralT, spectral);
      spectral.multiplyScalar(brightness * 0.92);
      const chroma = THREE.MathUtils.clamp(eventWeight * 0.08, 0, 0.10);
      finalColor.copy(neutral).lerp(spectral, chroma);

      for (let side = 0; side < ORBIT_SIDES; side += 1) {
        const angle = (side / ORBIT_SIDES) * TAU;
        vertex.copy(center)
          .addScaledVector(frameNormal, Math.cos(angle) * localThickness)
          .addScaledVector(frameBinormal, Math.sin(angle) * localThickness);

        const vertexIndex = segment * ORBIT_SIDES + side;
        const offset = vertexIndex * 3;
        positions[offset] = vertex.x;
        positions[offset + 1] = vertex.y;
        positions[offset + 2] = vertex.z;
        colors[offset] = finalColor.r;
        colors[offset + 1] = finalColor.g;
        colors[offset + 2] = finalColor.b;
      }
    }

    this.orbitPositionAttribute.needsUpdate = true;
    this.orbitColorAttribute.needsUpdate = true;
  }

  resize(width: number, height: number, pixelRatio: number) {
    if (!this.renderer || !this.camera) return;
    this.width = Math.max(1, Math.floor(width));
    this.height = Math.max(1, Math.floor(height));
    this.renderer.setPixelRatio(Math.min(pixelRatio, this.experiment.maxPixelRatio ?? 1.5));
    this.renderer.setSize(this.width, this.height, false);
    this.camera.aspect = this.width / Math.max(this.height, 1);
    this.camera.updateProjectionMatrix();
  }

  setPointer(_x: number, _y: number) {}

  setPointerState(state: PointerState) {
    this.pointerDown = state.down;
    if (!state.down) return;
    this.yaw -= state.dx * 3.2;
    this.pitch = THREE.MathUtils.clamp(this.pitch + state.dy * 2.6, -1.25, 1.25);
  }

  setParameters(values: ParameterValues) {
    Object.entries(this.experiment.metadata.parameters).forEach(([name, config]) => {
      const next = values[name];
      const uniform = this.uniforms[name];
      if (!uniform || next === undefined) return;
      if (config.type === 'color') (uniform.value as THREE.Color).set(String(next));
      else uniform.value = next;
    });

    if (this.geometry) {
      const requested = Number(values.uParticleCount ?? 26000);
      const localizedSpectralCopies = this.experiment.metadata.parameters.uChromaticAberration ? 4 : 1;
      const mobile = matchMedia('(pointer: coarse)').matches;
      const baseLimit = localizedSpectralCopies > 1
        ? (mobile ? 30000 : 60000)
        : (mobile ? 120000 : 240000);
      const baseCount = THREE.MathUtils.clamp(Math.floor(requested), 1000, baseLimit);
      this.geometry.instanceCount = baseCount * localizedSpectralCopies;
      if (this.uniforms.uParticleCount) this.uniforms.uParticleCount.value = baseCount;
    }

    if (this.orbitMaterial) {
      this.orbitMaterial.opacity = Number(
        values.uOrbitLineOpacity ?? this.uniforms.uOrbitLineOpacity?.value ?? 0.22,
      );
    }
  }

  render(elapsedSeconds: number) {
    if (!this.renderer || !this.scene || !this.camera) return;
    this.uniforms.uTime.value = elapsedSeconds;
    if (!this.pointerDown) this.yaw += 0.00042;

    const distance = Number(this.uniforms.uCameraDistance?.value ?? 6.15);
    const cp = Math.cos(this.pitch);
    const sp = Math.sin(this.pitch);
    const cy = Math.cos(this.yaw);
    const sy = Math.sin(this.yaw);
    this.camera.position.set(distance * cp * sy, distance * sp, distance * cp * cy);
    this.camera.lookAt(0,0,0);
    this.camera.updateMatrixWorld();
    this.viewProj.multiplyMatrices(this.camera.projectionMatrix, this.camera.matrixWorldInverse);
    const e = this.camera.matrixWorld.elements;
    (this.uniforms.uCamRight.value as THREE.Vector3).set(e[0],e[1],e[2]);
    (this.uniforms.uCamUp.value as THREE.Vector3).set(e[4],e[5],e[6]);

    if (this.orbitMesh) this.updateOrbitTube(elapsedSeconds);
    this.renderer.render(this.scene, this.camera);
  }

  getSurfaceInfo(): BackendSurfaceInfo {
    return {
      width: this.width,
      height: this.height,
      drawCalls: this.renderer?.info.render.calls ?? 0,
      renderer: this.orbitMesh
        ? 'Three.js / Instanced Particles + Localized RGB Spectral Copies + Continuous Tether'
        : 'Three.js / Instanced WebGL2 Particles',
    };
  }

  dispose() {
    this.orbitGeometry?.dispose();
    this.orbitMaterial?.dispose();
    this.geometry?.dispose();
    this.material?.dispose();
    this.renderer?.dispose();
  }
}
