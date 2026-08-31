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
const ORBIT_SEGMENTS = 640;
const ORBIT_SIDES = 8;
const ORBIT_SHELL_TARGET_RADIUS = 1.68;

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

// Must match orbitCurveDir() in solar-orbital-prominence/shader.vert exactly.
// The azimuth derivative is always positive, so the single closed line keeps winding forward
// instead of producing the large local reversals of the previous normalized harmonic curve.
function sampleOrbitDirection(t: number, rotationAngle: number, target: THREE.Vector3) {
  const phase = TAU * fract(t);
  const azimuth = 3.0 * phase + 0.12 * Math.sin(6.0 * phase);
  const latitude = 0.56 * Math.sin(5.0 * phase + 0.35) + 0.10 * Math.sin(10.0 * phase - 0.55);
  const cosLat = Math.cos(latitude);
  target.set(
    cosLat * Math.cos(azimuth),
    Math.sin(latitude),
    cosLat * Math.sin(azimuth),
  );
  target.applyAxisAngle(ORBIT_AXIS, rotationAngle);
  return target.normalize();
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
      opacity: 0.88,
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
    const eruptionRate = Number(this.uniforms.uEruptionRate?.value ?? 4.5);
    const eruptionChance = Number(this.uniforms.uEruptionChance?.value ?? 1.0);
    const flightDuration = Math.max(Number(this.uniforms.uFlightDuration?.value ?? 2.45), 0.15);

    for (let lane = 0; lane < 4; lane += 1) {
      const fi = lane;
      const randomPeriod = THREE.MathUtils.lerp(3.7, 5.4, hash11(fi * 41.7 + 3.1));
      const slotLength = Math.max(
        randomPeriod / Math.max(eruptionRate, 0.15),
        Math.max(flightDuration * 0.72, 0.55),
      );
      const shiftedTime = elapsedSeconds + fi * 1.271;
      const currentSlot = Math.floor(shiftedTime / slotLength);

      for (let history = 0; history < 3; history += 1) {
        const eventIndex = currentSlot - history;
        const slotLocalAge = shiftedTime - eventIndex * slotLength;
        const enabled = hash11(eventIndex * 5.73 + fi * 19.17) <= eruptionChance ? 1 : 0;
        if (!enabled) continue;

        const startDelay = 0.06 + hash11(eventIndex * 3.11 + fi * 7.77) * 0.20;
        const eventAge = slotLocalAge - startDelay;
        const historyFade = 1 - smoothstep(slotLength * 2.30, slotLength * 2.88, Math.max(eventAge, 0));
        const engage = smoothstep(-0.28, 0.05, eventAge);
        const release = 1 - smoothstep(flightDuration * 0.72, flightDuration * 1.18, eventAge);
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
    let weight = 0;
    const safeWidth = Math.max(width, 0.005);
    for (const event of events) {
      const rawDistance = Math.abs(t - event.t);
      const distance = Math.min(rawDistance, 1 - rawDistance);
      const local = (1 - smoothstep(0, safeWidth, distance)) * event.strength;
      weight = Math.max(weight, local);
    }
    return weight;
  }

  private updateOrbitTube(elapsedSeconds: number) {
    if (!this.orbitPositionAttribute || !this.orbitColorAttribute) return;

    const positions = this.orbitPositionAttribute.array as Float32Array;
    const colors = this.orbitColorAttribute.array as Float32Array;
    const radius = Number(this.uniforms.uOrbitRadius?.value ?? 2.15);
    const pulse = Number(this.uniforms.uOrbitPulse?.value ?? 0.035);
    const rotationSpeed = Number(this.uniforms.uOrbitRotationSpeed?.value ?? 1.0);
    const thickness = Number(this.uniforms.uOrbitThickness?.value ?? 0.006);
    const pullStrength = Number(this.uniforms.uOrbitPullStrength?.value ?? 0.9);
    const influenceWidth = Number(this.uniforms.uOrbitInfluenceWidth?.value ?? 0.11);
    const highlightStrength = Number(this.uniforms.uOrbitHighlightStrength?.value ?? 1.5);
    const orbitColor = this.uniforms.uOrbitLineColor?.value as THREE.Color | undefined;
    const brightness = Number(this.uniforms.uOrbitLineBrightness?.value ?? 2.25);
    const rotationAngle = elapsedSeconds * 0.18 * rotationSpeed;
    const events = this.collectActiveOrbitEvents(elapsedSeconds);

    const dir = new THREE.Vector3();
    const previous = new THREE.Vector3();
    const next = new THREE.Vector3();
    const tangent = new THREE.Vector3();
    const frameNormal = new THREE.Vector3();
    const frameBinormal = new THREE.Vector3();
    const center = new THREE.Vector3();
    const vertex = new THREE.Vector3();
    const tangentStep = 0.75 / ORBIT_SEGMENTS;

    const baseR = (orbitColor?.r ?? 1) * brightness;
    const baseG = (orbitColor?.g ?? 1) * brightness;
    const baseB = (orbitColor?.b ?? 1) * brightness;

    for (let segment = 0; segment < ORBIT_SEGMENTS; segment += 1) {
      const t = segment / ORBIT_SEGMENTS;
      const eventWeight = this.orbitEventWeight(t, events, influenceWidth);
      const localPulse = 1 + pulse * Math.sin(elapsedSeconds * 0.72 + t * TAU * 2.0);
      const normalRadius = radius * localPulse;

      // Keep the tether indentation broad and C1-like rather than dragging a short segment almost
      // all the way to the shell. This preserves the visual connection without creating a V-fold.
      const pullAmount = THREE.MathUtils.clamp(eventWeight * pullStrength * 0.74, 0, 0.74);
      const localRadius = THREE.MathUtils.lerp(normalRadius, ORBIT_SHELL_TARGET_RADIUS, pullAmount);

      sampleOrbitDirection(t, rotationAngle, dir);
      sampleOrbitDirection(t - tangentStep, rotationAngle, previous);
      sampleOrbitDirection(t + tangentStep, rotationAngle, next);
      tangent.subVectors(next, previous);
      tangent.addScaledVector(dir, -tangent.dot(dir));
      if (tangent.lengthSq() < 1e-10) {
        tangent.set(-dir.z, 0, dir.x);
      }
      tangent.normalize();
      frameBinormal.crossVectors(tangent, dir);
      if (frameBinormal.lengthSq() < 1e-10) {
        frameBinormal.set(0, 1, 0).cross(dir);
      }
      frameBinormal.normalize();
      frameNormal.crossVectors(frameBinormal, tangent).normalize();
      center.copy(dir).multiplyScalar(localRadius);

      const highlight = Math.min(1 + highlightStrength * eventWeight, 4.0);
      const localThickness = thickness * (1 + 0.10 * eventWeight);

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
        colors[offset] = baseR * highlight;
        colors[offset + 1] = baseG * highlight;
        colors[offset + 2] = baseB * highlight;
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
      const requested = Number(values.uParticleCount ?? 10000);
      const mobile = matchMedia('(pointer: coarse)').matches;
      this.geometry.instanceCount = THREE.MathUtils.clamp(
        Math.floor(requested),
        1000,
        mobile ? 120000 : 240000,
      );
    }

    if (this.orbitMaterial) {
      this.orbitMaterial.opacity = Number(
        values.uOrbitLineOpacity ?? this.uniforms.uOrbitLineOpacity?.value ?? 0.88,
      );
    }
  }

  render(elapsedSeconds: number) {
    if (!this.renderer || !this.scene || !this.camera) return;
    this.uniforms.uTime.value = elapsedSeconds;
    if (!this.pointerDown) this.yaw += 0.00055;

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
        ? 'Three.js / Instanced Particles + Smooth Continuous Tether Orbit'
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
