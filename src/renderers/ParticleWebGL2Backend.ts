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

const ORBIT_NORMALS = [
  new THREE.Vector3(0.22, 0.94, 0.26).normalize(),
  new THREE.Vector3(-0.61, 0.63, 0.48).normalize(),
  new THREE.Vector3(0.72, 0.38, -0.58).normalize(),
  new THREE.Vector3(-0.32, 0.76, -0.56).normalize(),
];
const ORBIT_FACTORS = [1.0, 1.07, 1.14, 1.21];
const ORBIT_AXIS = new THREE.Vector3(0.18, 1.0, 0.07).normalize();

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
  private orbitGroup?: THREE.Group;
  private orbitLines: THREE.LineLoop[] = [];
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
    this.renderer = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: false, powerPreference: 'high-performance' });
    this.renderer.setClearColor(0x050506, 1);
    validateShaderProgram(this.renderer.getContext() as WebGL2RenderingContext, this.experiment.vertexShader, this.experiment.fragmentShader);

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(47, 1, 0.05, 30);
    this.geometry = new THREE.InstancedBufferGeometry();
    this.geometry.setAttribute('position', new THREE.Float32BufferAttribute([-1,-1,0, 1,-1,0, -1,1,0, 1,1,0], 3));
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

    if (this.experiment.metadata.parameters.uOrbitRadius) this.createOrbitLines();
    this.setParameters(Object.fromEntries(Object.entries(this.experiment.metadata.parameters).map(([name, config]) => [name, config.default])));
  }

  private createOrbitLines() {
    if (!this.scene) return;
    this.orbitGroup = new THREE.Group();
    ORBIT_NORMALS.forEach((normal, i) => {
      const helper = Math.abs(normal.y) < 0.92 ? new THREE.Vector3(0,1,0) : new THREE.Vector3(1,0,0);
      const a = helper.clone().cross(normal).normalize();
      const b = normal.clone().cross(a).normalize();
      const points: THREE.Vector3[] = [];
      for (let j = 0; j < 256; j++) {
        const t = (j / 256) * Math.PI * 2;
        points.push(a.clone().multiplyScalar(Math.cos(t)).add(b.clone().multiplyScalar(Math.sin(t))));
      }
      const geometry = new THREE.BufferGeometry().setFromPoints(points);
      const core = new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.82, blending: THREE.AdditiveBlending, depthTest: false, depthWrite: false, toneMapped: false });
      const halo = new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.16, blending: THREE.AdditiveBlending, depthTest: false, depthWrite: false, toneMapped: false });
      const line = new THREE.LineLoop(geometry, core);
      const glow = new THREE.LineLoop(geometry.clone(), halo);
      line.userData = { factor: ORBIT_FACTORS[i], phase: i * 1.71, halo: false };
      glow.userData = { factor: ORBIT_FACTORS[i] * 1.004, phase: i * 1.71, halo: true };
      line.renderOrder = 3;
      glow.renderOrder = 2;
      this.orbitGroup!.add(glow, line);
      this.orbitLines.push(glow, line);
    });
    this.scene.add(this.orbitGroup);
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
      this.geometry.instanceCount = THREE.MathUtils.clamp(Math.floor(requested), 1000, mobile ? 120000 : 240000);
    }
    if (this.orbitLines.length) {
      const base = new THREE.Color(String(values.uOrbitLineColor ?? '#ffffff'));
      const brightness = Number(values.uOrbitLineBrightness ?? 2.2);
      const opacity = Number(values.uOrbitLineOpacity ?? 0.82);
      for (const line of this.orbitLines) {
        const mat = line.material as THREE.LineBasicMaterial;
        mat.color.copy(base).multiplyScalar(brightness);
        mat.opacity = line.userData.halo ? opacity * 0.22 : opacity;
      }
    }
  }

  render(elapsedSeconds: number) {
    if (!this.renderer || !this.scene || !this.camera) return;
    this.uniforms.uTime.value = elapsedSeconds;
    if (!this.pointerDown) this.yaw += 0.00055;
    const distance = Number(this.uniforms.uCameraDistance?.value ?? 6.15);
    const cp = Math.cos(this.pitch), sp = Math.sin(this.pitch), cy = Math.cos(this.yaw), sy = Math.sin(this.yaw);
    this.camera.position.set(distance * cp * sy, distance * sp, distance * cp * cy);
    this.camera.lookAt(0,0,0);
    this.camera.updateMatrixWorld();
    this.viewProj.multiplyMatrices(this.camera.projectionMatrix, this.camera.matrixWorldInverse);
    const e = this.camera.matrixWorld.elements;
    (this.uniforms.uCamRight.value as THREE.Vector3).set(e[0],e[1],e[2]);
    (this.uniforms.uCamUp.value as THREE.Vector3).set(e[4],e[5],e[6]);

    if (this.orbitGroup) {
      const speed = Number(this.uniforms.uOrbitRotationSpeed?.value ?? 1.0);
      const radius = Number(this.uniforms.uOrbitRadius?.value ?? 2.15);
      const pulse = Number(this.uniforms.uOrbitPulse?.value ?? 0.045);
      this.orbitGroup.setRotationFromAxisAngle(ORBIT_AXIS, elapsedSeconds * 0.18 * speed);
      for (const line of this.orbitLines) {
        const s = radius * Number(line.userData.factor) * (1 + pulse * Math.sin(elapsedSeconds * 0.72 + Number(line.userData.phase)));
        line.scale.setScalar(s);
      }
    }
    this.renderer.render(this.scene, this.camera);
  }

  getSurfaceInfo(): BackendSurfaceInfo {
    return { width: this.width, height: this.height, drawCalls: this.renderer?.info.render.calls ?? 0, renderer: this.orbitGroup ? 'Three.js / Instanced Particles + Orbit Lines' : 'Three.js / Instanced WebGL2 Particles' };
  }

  dispose() {
    for (const line of this.orbitLines) {
      line.geometry.dispose();
      (line.material as THREE.Material).dispose();
    }
    this.geometry?.dispose();
    this.material?.dispose();
    this.renderer?.dispose();
  }
}
