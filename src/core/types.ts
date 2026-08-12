export type Locale = 'zh' | 'en';

export interface LocalizedText {
  zh: string;
  en: string;
}

export type Backend = 'webgl2' | 'webgpu' | 'auto' | 'raw-webgpu';
export type ShaderLanguage = 'GLSL' | 'WGSL' | 'TSL';
export type ParameterType = 'float' | 'int' | 'boolean' | 'color' | 'enum';

export interface ShaderParameterOption {
  value: number | string;
  label: LocalizedText;
}

export interface ShaderParameterMetadata {
  type: ParameterType;
  default: number | boolean | string;
  min?: number;
  max?: number;
  step?: number;
  label: LocalizedText;
  description?: LocalizedText;
  group?: LocalizedText;
  options?: ShaderParameterOption[];
}

export interface ShaderLabMetadata {
  version: 1;
  parameters: Record<string, ShaderParameterMetadata>;
}

export type ParameterValues = Record<string, number | boolean | string>;

export interface ExperimentDefinition {
  id: string;
  title: LocalizedText;
  description: LocalizedText;
  category: LocalizedText;
  tags: string[];
  backend: Backend;
  languages: ShaderLanguage[];
  sourceFile: string;
  vertexShader?: string;
  fragmentShader?: string;
  wgsl?: string;
  /** Multiplier applied to the physical drawing-buffer size. Useful for expensive fullscreen effects. */
  renderScale?: number;
  /** Upper bound for devicePixelRatio used by the renderer. */
  maxPixelRatio?: number;
  metadata: ShaderLabMetadata;
}

export interface PerfSnapshot {
  fps: number;
  frameMs: number;
  width: number;
  height: number;
  drawCalls: number;
  renderer: string;
}
