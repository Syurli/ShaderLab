import type {
  ParameterValues,
  ShaderParameterMetadata,
} from '../core/types';
import type {
  BackendSurfaceInfo,
  RendererBackend,
  RendererBackendOptions,
} from './RendererBackend';

const SLOT_FLOATS = 4;
const SLOT_BYTES = SLOT_FLOATS * Float32Array.BYTES_PER_ELEMENT;

function colorToLinearishRgb(value: string): [number, number, number] {
  const normalized = value.trim().replace('#', '');
  const hex = normalized.length === 3
    ? normalized.split('').map((c) => c + c).join('')
    : normalized.padEnd(6, '0').slice(0, 6);
  const numeric = Number.parseInt(hex, 16);
  return [
    ((numeric >> 16) & 255) / 255,
    ((numeric >> 8) & 255) / 255,
    (numeric & 255) / 255,
  ];
}

function parameterScalar(value: number | boolean | string, config: ShaderParameterMetadata) {
  if (typeof value === 'number') return value;
  if (typeof value === 'boolean') return value ? 1 : 0;
  if (config.type === 'enum') {
    const index = config.options?.findIndex((option) => option.value === value) ?? -1;
    return Math.max(index, 0);
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function buildInjectedWGSL(parameterNames: string[]) {
  for (const name of parameterNames) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
      throw new Error(`Invalid WGSL parameter identifier: ${name}`);
    }
  }

  const fields = parameterNames.length
    ? parameterNames.map((name) => `  ${name}: vec4f,`).join('\n')
    : '  _padding: vec4f,';

  return `
struct ShaderLabFrame {
  timeResolution: vec4f,
  pointerPixelRatio: vec4f,
};

struct ShaderLabParams {
${fields}
};

@group(0) @binding(0) var<uniform> frame: ShaderLabFrame;
@group(0) @binding(1) var<uniform> params: ShaderLabParams;
`;
}

export class RawWebGPUBackend implements RendererBackend {
  readonly id = 'raw-webgpu';

  private readonly canvas: HTMLCanvasElement;
  private readonly experiment: RendererBackendOptions['experiment'];
  private readonly parameterNames: string[];
  private values: ParameterValues;
  private pointerX = 0.5;
  private pointerY = 0.5;
  private pixelRatio = 1;
  private width = 1;
  private height = 1;

  private adapter?: GPUAdapter;
  private device?: GPUDevice;
  private context?: GPUCanvasContext;
  private pipeline?: GPURenderPipeline;
  private bindGroup?: GPUBindGroup;
  private frameBuffer?: GPUBuffer;
  private parameterBuffer?: GPUBuffer;

  constructor(options: RendererBackendOptions) {
    this.canvas = options.canvas;
    this.experiment = options.experiment;
    this.values = { ...options.initialValues };
    this.parameterNames = Object.keys(options.experiment.metadata.parameters);
  }

  async initialize() {
    if (!navigator.gpu) {
      throw new Error('WebGPU is not available in this browser. Use a recent WebGPU-capable browser.');
    }
    if (!this.experiment.wgsl) {
      throw new Error('Raw WebGPU experiments require a WGSL module.');
    }

    this.adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' }) ?? undefined;
    if (!this.adapter) throw new Error('WebGPU adapter request failed.');

    this.device = await this.adapter.requestDevice();
    this.context = this.canvas.getContext('webgpu') ?? undefined;
    if (!this.context) throw new Error('Could not acquire a WebGPU canvas context.');

    const format = navigator.gpu.getPreferredCanvasFormat();
    this.context.configure({
      device: this.device,
      format,
      alphaMode: 'opaque',
    });

    const code = `${buildInjectedWGSL(this.parameterNames)}\n${this.experiment.wgsl}`;
    const module = this.device.createShaderModule({
      label: `${this.experiment.id} shader module`,
      code,
    });

    const compilation = await module.getCompilationInfo();
    const errors = compilation.messages.filter((message) => message.type === 'error');
    if (errors.length) {
      throw new Error(errors.map((message) => `WGSL ${message.lineNum}:${message.linePos} ${message.message}`).join('\n'));
    }

    this.pipeline = this.device.createRenderPipeline({
      label: `${this.experiment.id} fullscreen pipeline`,
      layout: 'auto',
      vertex: { module, entryPoint: 'vsMain' },
      fragment: {
        module,
        entryPoint: 'fsMain',
        targets: [{ format }],
      },
      primitive: { topology: 'triangle-list' },
    });

    this.frameBuffer = this.device.createBuffer({
      label: 'ShaderLab frame uniforms',
      size: 32,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    this.parameterBuffer = this.device.createBuffer({
      label: 'ShaderLab parameter uniforms',
      size: Math.max(SLOT_BYTES, this.parameterNames.length * SLOT_BYTES),
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    this.bindGroup = this.device.createBindGroup({
      label: 'ShaderLab frame bind group',
      layout: this.pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: this.frameBuffer } },
        { binding: 1, resource: { buffer: this.parameterBuffer } },
      ],
    });

    this.uploadParameters();
  }

  resize(width: number, height: number, pixelRatio: number) {
    const maxPixelRatio = Math.max(0.5, this.experiment.maxPixelRatio ?? 2);
    const renderScale = Math.min(1, Math.max(0.25, this.experiment.renderScale ?? 1));
    this.pixelRatio = Math.min(pixelRatio, maxPixelRatio) * renderScale;

    const physicalWidth = Math.max(1, Math.floor(width * this.pixelRatio));
    const physicalHeight = Math.max(1, Math.floor(height * this.pixelRatio));
    if (this.canvas.width !== physicalWidth) this.canvas.width = physicalWidth;
    if (this.canvas.height !== physicalHeight) this.canvas.height = physicalHeight;
    this.width = physicalWidth;
    this.height = physicalHeight;
  }

  setPointer(x: number, y: number) {
    this.pointerX = x;
    this.pointerY = y;
  }

  setParameters(values: ParameterValues) {
    if (values === this.values) return;
    this.values = values;
    this.uploadParameters();
  }

  private uploadParameters() {
    if (!this.device || !this.parameterBuffer) return;
    const packed = new Float32Array(Math.max(SLOT_FLOATS, this.parameterNames.length * SLOT_FLOATS));

    this.parameterNames.forEach((name, index) => {
      const config = this.experiment.metadata.parameters[name];
      const value = this.values[name] ?? config.default;
      const offset = index * SLOT_FLOATS;
      if (config.type === 'color') {
        const [r, g, b] = colorToLinearishRgb(String(value));
        packed[offset] = r;
        packed[offset + 1] = g;
        packed[offset + 2] = b;
        packed[offset + 3] = 1;
      } else {
        packed[offset] = parameterScalar(value, config);
      }
    });

    this.device.queue.writeBuffer(this.parameterBuffer, 0, packed);
  }

  render(elapsedSeconds: number) {
    if (!this.device || !this.context || !this.pipeline || !this.bindGroup || !this.frameBuffer) return;

    const aspect = this.width / Math.max(this.height, 1);
    const frame = new Float32Array([
      elapsedSeconds,
      this.width,
      this.height,
      aspect,
      this.pointerX,
      this.pointerY,
      this.pixelRatio,
      0,
    ]);
    this.device.queue.writeBuffer(this.frameBuffer, 0, frame);

    const encoder = this.device.createCommandEncoder({ label: 'ShaderLab frame encoder' });
    const pass = encoder.beginRenderPass({
      colorAttachments: [{
        view: this.context.getCurrentTexture().createView(),
        clearValue: { r: 0.025, g: 0.03, b: 0.04, a: 1 },
        loadOp: 'clear',
        storeOp: 'store',
      }],
    });
    pass.setPipeline(this.pipeline);
    pass.setBindGroup(0, this.bindGroup);
    pass.draw(3);
    pass.end();
    this.device.queue.submit([encoder.finish()]);
  }

  getSurfaceInfo(): BackendSurfaceInfo {
    return {
      width: this.width,
      height: this.height,
      drawCalls: 1,
      renderer: 'Raw WebGPU / WGSL',
    };
  }

  dispose() {
    this.frameBuffer?.destroy();
    this.parameterBuffer?.destroy();
    this.context?.unconfigure();
    this.device?.destroy();
  }
}
