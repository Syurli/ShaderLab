import type { ExperimentDefinition, ParameterValues } from '../core/types';

export interface BackendSurfaceInfo {
  width: number;
  height: number;
  drawCalls: number;
  renderer: string;
}

export interface PointerState {
  x: number;
  y: number;
  down: boolean;
  dx: number;
  dy: number;
}

export interface RendererBackend {
  readonly id: string;
  initialize(): Promise<void>;
  resize(width: number, height: number, pixelRatio: number): void;
  setPointer(x: number, y: number): void;
  /** Optional richer pointer input for interactive simulations. */
  setPointerState?(state: PointerState): void;
  setParameters(values: ParameterValues): void;
  render(elapsedSeconds: number): void;
  /** Optional GPU completion fence used by uncapped benchmark loops. */
  waitForSubmittedWork?(): Promise<void>;
  getSurfaceInfo(): BackendSurfaceInfo;
  dispose(): void;
}

export interface RendererBackendOptions {
  canvas: HTMLCanvasElement;
  experiment: ExperimentDefinition;
  initialValues: ParameterValues;
}
