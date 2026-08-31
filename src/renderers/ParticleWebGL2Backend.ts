import * as THREE from 'three';
import type { ParameterValues } from '../core/types';
import type {
  BackendSurfaceInfo,
  PointerState,
  RendererBackend,
  RendererBackendOptions,
} from './RendererBackend';

function toUniformValue(value: number | boolean | string, type: string) {
  if (type === 'color') return new THREE.Color(String(value));
  return value;
}

function withGlsl3Version(source: string) {
  return /^\s*#version\s+300\s+es\b/.test(source) ? source : `#version 300 es\n${source}`;
}

function compileShader(
  gl: WebGL2RenderingContext,
  type: number,
  source: string,
  label: string,
) {
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

function validateShaderProgram(
  gl: WebGL2RenderingContext,
  vertexSource: string,
  fragmentSource: string,
) {
  const vertex = compileShader(gl, gl.VERTEX_SHADER, vertexSource, 'vertex');
  const fragment = compileShader(gl, gl.FRAGMENT_SHADER, fragmentSource, 'fragment');
  const program = gl.createProgram();

  if (!program) {
    gl.deleteShader(vertex);
    gl.deleteShader(fragment);
    throw new Error('[ParticleWebGL2] Failed to create shader validation program.');
  }

  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);

  const linked = gl.getProgramParameter(program, gl.LINK_STATUS);
  const log = gl.getProgramInfoLog(program) || '';

  gl.deleteProgram(program);
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);

  if (!linked) {
    throw new Error(`[ParticleWebGL2] Shader program link failed:\n${log || 'Unknown GLSL linker error.'}`);
  }
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

    // Validate the exact GLSL sources up front. The regular TypeScript/Vite build cannot
    // detect GPU shader compilation failures, so without this a bad shader only appears as
    // a black canvas. RawShaderMaterial receives the sources without their own #version;
    // Three.js injects #version 300 es from glslVersion below.
    const gl = this.renderer.getContext() as WebGL2RenderingContext;
    validateShaderProgram(gl, this.experiment.vertexShader, this.experiment.fragmentShader);

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(47, 1, 0.05, 30);

    this.geometry = new THREE.InstancedBufferGeometry();
    this.geometry.setAttribute(
      'position',
      new THREE.Float32BufferAttribute(
        [
          -1, -1, 0,
           1, -1, 0,
          -1,  1, 0,
           1,  1, 0,
        ],
        3,
      ),
    );
    this.geometry.setIndex([0, 1, 2, 2, 1, 3]);
    this.geometry.instanceCount = 1;

    this.uniforms.uTime = { value: 0 };
    this.uniforms.uViewProj = { value: this.viewProj };
    this.uniforms.uCamRight = { value: new THREE.Vector3(1, 0, 0) };
    this.uniforms.uCamUp = { value: new THREE.Vector3(0, 1, 0) };

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
    this.scene.add(this.mesh);
    this.setParameters(Object.fromEntries(
      Object.entries(this.experiment.metadata.parameters).map(([name, config]) => [name, config.default]),
    ));
  }

  resize(width: number, height: number, pixelRatio: number) {
    if (!this.renderer || !this.camera) return;
    this.width = Math.max(1, Math.floor(width));
    this.height = Math.max(1, Math.floor(height));
    const cap = this.experiment.maxPixelRatio ?? 1.5;
    this.renderer.setPixelRatio(Math.min(pixelRatio, cap));
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
      if (config.type === 'color') {
        (uniform.value as THREE.Color).set(String(next));
      } else {
        uniform.value = next;
      }
    });

    if (this.geometry) {
      const requested = Number(values.uParticleCount ?? 26000);
      const mobile = matchMedia('(pointer: coarse)').matches;
      const hardCap = mobile ? 36000 : 80000;
      this.geometry.instanceCount = THREE.MathUtils.clamp(Math.floor(requested), 1000, hardCap);
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
    this.camera.lookAt(0, 0, 0);
    this.camera.updateMatrixWorld();
    this.viewProj.multiplyMatrices(this.camera.projectionMatrix, this.camera.matrixWorldInverse);

    const e = this.camera.matrixWorld.elements;
    (this.uniforms.uCamRight.value as THREE.Vector3).set(e[0], e[1], e[2]);
    (this.uniforms.uCamUp.value as THREE.Vector3).set(e[4], e[5], e[6]);

    this.renderer.render(this.scene, this.camera);
  }

  getSurfaceInfo(): BackendSurfaceInfo {
    return {
      width: this.width,
      height: this.height,
      drawCalls: this.renderer?.info.render.calls ?? 0,
      renderer: 'Three.js / Instanced WebGL2 Particles',
    };
  }

  dispose() {
    this.geometry?.dispose();
    this.material?.dispose();
    this.renderer?.dispose();
  }
}
