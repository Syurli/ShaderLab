import type { ExperimentDefinition, ParameterValues } from '../core/types';

export interface BackendSurfaceInfo {
  width: number;
  height: number;
  drawCalls: number;
  renderer: string;
}

export interface RendererBackend {
  readonly id: string;
  initialize(): Promise<void>;
  resize(width: number, height: number, pixelRatio: number): void;
  setPointer(x: number, y: number): void;
  setParameters(values: ParameterValues): void;
  render(elapsedSeconds: number): void;
  getSurfaceInfo(): BackendSurfaceInfo;
  dispose(): void;
}

export interface RendererBackendOptions {
  canvas: HTMLCanvasElement;
  experiment: ExperimentDefinition;
  initialValues: ParameterValues;
}
