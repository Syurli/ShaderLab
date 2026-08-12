import type {
  ParameterValues,
  ShaderParameterMetadata,
} from '../core/types';
import type {
  BackendSurfaceInfo,
  PointerState,
  RendererBackend,
  RendererBackendOptions,
} from './RendererBackend';

const SLOT_FLOATS = 4;
const SLOT_BYTES = SLOT_FLOATS * Float32Array.BYTES_PER_ELEMENT;
const FLUID_SIZE = 96;
const FLUID_CELL_FLOATS = 4;
const FLUID_BUFFER_BYTES = FLUID_SIZE * FLUID_SIZE * FLUID_CELL_FLOATS * Float32Array.BYTES_PER_ELEMENT;

function colorToRgb(value: string): [number, number, number] {
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
  const fields = parameterNames.length
    ? parameterNames.map((name) => {
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
          throw new Error(`Invalid WGSL parameter identifier: ${name}`);
        }
        return `  ${name}: vec4f,`;
      }).join('\n')
    : '  _padding: vec4f,';

  return `
const FLUID_SIZE: u32 = ${FLUID_SIZE}u;

struct ShaderLabFrame {
  timeResolution: vec4f,
  pointer: vec4f,
  pointerDelta: vec4f,
};

struct ShaderLabParams {
${fields}
};

struct FluidBuffer {
  cells: array<vec4f>,
};

@group(0) @binding(0) var<uniform> frame: ShaderLabFrame;
@group(0) @binding(1) var<uniform> params: ShaderLabParams;
@group(1) @binding(0) var<storage, read> fluidIn: FluidBuffer;
@group(1) @binding(1) var<storage, read_write> fluidOut: FluidBuffer;
`;
}

export class FluidVolumeWebGPUBackend implements RendererBackend {
  readonly id = 'fluid-webgpu';

  private readonly canvas: HTMLCanvasElement;
  private readonly experiment: RendererBackendOptions['experiment'];
  private readonly parameterNames: string[];
  private values: ParameterValues;
  private pointer: PointerState = { x: 0.5, y: 0.5, down: false, dx: 0, dy: 0 };
  private width = 1;
  private height = 1;
  private pixelRatio = 1;
  private lastElapsed = 0;
  private sourceIndex = 0;

  private device?: GPUDevice;
  private context?: GPUCanvasContext;
  private computePipeline?: GPUComputePipeline;
  private renderPipeline?: GPURenderPipeline;
  private frameBuffer?: GPUBuffer;
  private parameterBuffer?: GPUBuffer;
  private fluidBuffers: GPUBuffer[] = [];
  private uniformBindGroup?: GPUBindGroup;
  private fluidBindGroups: GPUBindGroup[] = [];

  constructor(options: RendererBackendOptions) {
    this.canvas = options.canvas;
    this.experiment = options.experiment;
    this.values = { ...options.initialValues };
    this.parameterNames = Object.keys(options.experiment.metadata.parameters);
  }

  async initialize() {
    if (!navigator.gpu) throw new Error('WebGPU is required for the interactive fluid volume experiment.');
    if (!this.experiment.wgsl) throw new Error('Fluid WebGPU experiments require a WGSL module.');

    const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
    if (!adapter) throw new Error('WebGPU adapter request failed.');
    this.device = await adapter.requestDevice();
    this.context = this.canvas.getContext('webgpu') ?? undefined;
    if (!this.context) throw new Error('Could not acquire a WebGPU canvas context.');

    const format = navigator.gpu.getPreferredCanvasFormat();
    this.context.configure({ device: this.device, format, alphaMode: 'opaque' });

    const module = this.device.createShaderModule({
      label: `${this.experiment.id} fluid-volume shader`,
      code: `${buildInjectedWGSL(this.parameterNames)}\n${this.experiment.wgsl}`,
    });
    const compilation = await module.getCompilationInfo();
    const errors = compilation.messages.filter((message) => message.type === 'error');
    if (errors.length) {
      throw new Error(errors.map((message) => `WGSL ${message.lineNum}:${message.linePos} ${message.message}`).join('\n'));
    }

    const uniformLayout = this.device.createBindGroupLayout({
      label: 'fluid-volume uniforms',
      entries: [
        { binding: 0, visibility: GPUShaderStage.COMPUTE | GPUShaderStage.FRAGMENT, buffer: { type: 'uniform' } },
        { binding: 1, visibility: GPUShaderStage.COMPUTE | GPUShaderStage.FRAGMENT, buffer: { type: 'uniform' } },
      ],
    });
    const fluidLayout = this.device.createBindGroupLayout({
      label: 'fluid-volume ping-pong fields',
      entries: [
        { binding: 0, visibility: GPUShaderStage.COMPUTE | GPUShaderStage.FRAGMENT, buffer: { type: 'read-only-storage' } },
        { binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
      ],
    });
    const pipelineLayout = this.device.createPipelineLayout({ bindGroupLayouts: [uniformLayout, fluidLayout] });

    this.computePipeline = this.device.createComputePipeline({
      label: `${this.experiment.id} fluid advection`,
      layout: pipelineLayout,
      compute: { module, entryPoint: 'csFluid' },
    });
    this.renderPipeline = this.device.createRenderPipeline({
      label: `${this.experiment.id} volume raymarch`,
      layout: pipelineLayout,
      vertex: { module, entryPoint: 'vsMain' },
      fragment: { module, entryPoint: 'fsMain', targets: [{ format }] },
      primitive: { topology: 'triangle-list' },
    });

    this.frameBuffer = this.device.createBuffer({
      label: 'fluid-volume frame uniforms',
      size: 48,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });
    this.parameterBuffer = this.device.createBuffer({
      label: 'fluid-volume parameter uniforms',
      size: Math.max(SLOT_BYTES, this.parameterNames.length * SLOT_BYTES),
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    this.fluidBuffers = [0, 1].map((index) => this.device!.createBuffer({
      label: `fluid field ${index}`,
      size: FLUID_BUFFER_BYTES,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    }));

    const seed = new Float32Array(FLUID_SIZE * FLUID_SIZE * FLUID_CELL_FLOATS);
    for (let y = 0; y < FLUID_SIZE; y += 1) {
      for (let x = 0; x < FLUID_SIZE; x += 1) {
        const ux = (x + 0.5) / FLUID_SIZE - 0.5;
        const uy = (y + 0.5) / FLUID_SIZE - 0.5;
        const r2 = ux * ux + uy * uy;
        const offset = (y * FLUID_SIZE + x) * FLUID_CELL_FLOATS;
        seed[offset] = -uy * Math.exp(-r2 * 32) * 0.18;
        seed[offset + 1] = ux * Math.exp(-r2 * 32) * 0.18;
        seed[offset + 2] = Math.exp(-r2 * 24) * 0.35;
      }
    }
    this.device.queue.writeBuffer(this.fluidBuffers[0], 0, seed);
    this.device.queue.writeBuffer(this.fluidBuffers[1], 0, seed);

    this.uniformBindGroup = this.device.createBindGroup({
      layout: uniformLayout,
      entries: [
        { binding: 0, resource: { buffer: this.frameBuffer } },
        { binding: 1, resource: { buffer: this.parameterBuffer } },
      ],
    });
    this.fluidBindGroups = [
      this.device.createBindGroup({
        layout: fluidLayout,
        entries: [
          { binding: 0, resource: { buffer: this.fluidBuffers[0] } },
          { binding: 1, resource: { buffer: this.fluidBuffers[1] } },
        ],
      }),
      this.device.createBindGroup({
        layout: fluidLayout,
        entries: [
          { binding: 0, resource: { buffer: this.fluidBuffers[1] } },
          { binding: 1, resource: { buffer: this.fluidBuffers[0] } },
        ],
      }),
    ];

    this.uploadParameters();
  }

  resize(width: number, height: number, pixelRatio: number) {
    const maxPixelRatio = Math.max(0.5, this.experiment.maxPixelRatio ?? 1.5);
    const renderScale = Math.min(1, Math.max(0.35, this.experiment.renderScale ?? 1));
    this.pixelRatio = Math.min(pixelRatio, maxPixelRatio) * renderScale;
    this.width = Math.max(1, Math.floor(width * this.pixelRatio));
    this.height = Math.max(1, Math.floor(height * this.pixelRatio));
    if (this.canvas.width !== this.width) this.canvas.width = this.width;
    if (this.canvas.height !== this.height) this.canvas.height = this.height;
  }

  setPointer(x: number, y: number) {
    this.pointer = { ...this.pointer, x, y };
  }

  setPointerState(state: PointerState) {
    this.pointer = state;
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
        const [r, g, b] = colorToRgb(String(value));
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
    if (!this.device || !this.context || !this.computePipeline || !this.renderPipeline || !this.uniformBindGroup || !this.frameBuffer) return;

    const dt = Math.min(1 / 30, Math.max(1 / 240, elapsedSeconds - this.lastElapsed || 1 / 60));
    this.lastElapsed = elapsedSeconds;
    const audio = 0.52
      + Math.sin(elapsedSeconds * 2.17) * 0.18
      + Math.sin(elapsedSeconds * 5.83 + 1.3) * 0.10
      + Math.sin(elapsedSeconds * 11.2) * 0.05;
    const frame = new Float32Array([
      elapsedSeconds, this.width, this.height, this.width / Math.max(this.height, 1),
      this.pointer.x, this.pointer.y, this.pointer.down ? 1 : 0, Math.max(0, Math.min(1, audio)),
      this.pointer.dx, this.pointer.dy, dt, this.pixelRatio,
    ]);
    this.device.queue.writeBuffer(this.frameBuffer, 0, frame);

    const encoder = this.device.createCommandEncoder({ label: 'fluid-volume frame' });
    const computePass = encoder.beginComputePass({ label: '2D fluid advection' });
    computePass.setPipeline(this.computePipeline);
    computePass.setBindGroup(0, this.uniformBindGroup);
    computePass.setBindGroup(1, this.fluidBindGroups[this.sourceIndex]);
    computePass.dispatchWorkgroups(Math.ceil(FLUID_SIZE / 8), Math.ceil(FLUID_SIZE / 8));
    computePass.end();

    this.sourceIndex = 1 - this.sourceIndex;

    const renderPass = encoder.beginRenderPass({
      colorAttachments: [{
        view: this.context.getCurrentTexture().createView(),
        clearValue: { r: 0.012, g: 0.016, b: 0.024, a: 1 },
        loadOp: 'clear',
        storeOp: 'store',
      }],
    });
    renderPass.setPipeline(this.renderPipeline);
    renderPass.setBindGroup(0, this.uniformBindGroup);
    renderPass.setBindGroup(1, this.fluidBindGroups[this.sourceIndex]);
    renderPass.draw(3);
    renderPass.end();
    this.device.queue.submit([encoder.finish()]);

    // Pointer impulses should be consumed once instead of accumulating forever.
    this.pointer = { ...this.pointer, dx: 0, dy: 0 };
  }

  getSurfaceInfo(): BackendSurfaceInfo {
    return {
      width: this.width,
      height: this.height,
      drawCalls: 2,
      renderer: `Raw WebGPU / WGSL + ${FLUID_SIZE}² fluid`,
    };
  }

  dispose() {
    this.frameBuffer?.destroy();
    this.parameterBuffer?.destroy();
    this.fluidBuffers.forEach((buffer) => buffer.destroy());
    this.context?.unconfigure();
    this.device?.destroy();
  }
}
