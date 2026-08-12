import * as THREE from 'three';
import type { ParameterValues } from '../core/types';
import type {
  BackendSurfaceInfo,
  RendererBackend,
  RendererBackendOptions,
} from './RendererBackend';

function toUniformValue(value: number | boolean | string, type: string) {
  if (type === 'color') return new THREE.Color(String(value));
  return value;
}

export class WebGL2Backend implements RendererBackend {
  readonly id = 'webgl2';

  private readonly canvas: HTMLCanvasElement;
  private readonly experiment: RendererBackendOptions['experiment'];
  private readonly uniforms: Record<string, THREE.IUniform> = {};
  private renderer?: THREE.WebGLRenderer;
  private scene?: THREE.Scene;
  private camera?: THREE.OrthographicCamera;
  private geometry?: THREE.PlaneGeometry;
  private material?: THREE.ShaderMaterial;
  private width = 1;
  private height = 1;

  constructor(options: RendererBackendOptions) {
    this.canvas = options.canvas;
    this.experiment = options.experiment;
  }

  async initialize() {
    if (!this.experiment.vertexShader || !this.experiment.fragmentShader) {
      throw new Error('WebGL2 experiments require vertexShader and fragmentShader sources.');
    }

    this.renderer = new THREE.WebGLRenderer({
      canvas: this.canvas,
      antialias: true,
      powerPreference: 'high-performance',
    });
    this.renderer.setClearColor(0x07090c, 1);

    this.scene = new THREE.Scene();
    this.camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    this.geometry = new THREE.PlaneGeometry(2, 2);

    this.uniforms.uTime = { value: 0 };
    this.uniforms.uResolution = { value: new THREE.Vector2(1, 1) };
    this.uniforms.uPointer = { value: new THREE.Vector2(0.5, 0.5) };

    Object.entries(this.experiment.metadata.parameters).forEach(([name, config]) => {
      this.uniforms[name] = { value: toUniformValue(config.default, config.type) };
    });

    this.material = new THREE.ShaderMaterial({
      vertexShader: this.experiment.vertexShader,
      fragmentShader: this.experiment.fragmentShader,
      uniforms: this.uniforms,
      depthWrite: false,
      depthTest: false,
    });

    this.scene.add(new THREE.Mesh(this.geometry, this.material));
  }

  resize(width: number, height: number, pixelRatio: number) {
    if (!this.renderer) return;
    this.width = Math.max(1, Math.floor(width));
    this.height = Math.max(1, Math.floor(height));
    this.renderer.setPixelRatio(Math.min(pixelRatio, 2));
    this.renderer.setSize(this.width, this.height, false);
    (this.uniforms.uResolution.value as THREE.Vector2).set(this.width, this.height);
  }

  setPointer(x: number, y: number) {
    const pointer = this.uniforms.uPointer?.value as THREE.Vector2 | undefined;
    pointer?.set(x, y);
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
  }

  render(elapsedSeconds: number) {
    if (!this.renderer || !this.scene || !this.camera) return;
    this.uniforms.uTime.value = elapsedSeconds;
    this.renderer.render(this.scene, this.camera);
  }

  getSurfaceInfo(): BackendSurfaceInfo {
    return {
      width: this.width,
      height: this.height,
      drawCalls: this.renderer?.info.render.calls ?? 0,
      renderer: 'Three.js / WebGL2',
    };
  }

  dispose() {
    this.geometry?.dispose();
    this.material?.dispose();
    this.renderer?.dispose();
  }
}
