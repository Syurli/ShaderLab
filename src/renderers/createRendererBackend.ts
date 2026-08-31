import type { RendererBackend, RendererBackendOptions } from './RendererBackend';
import { FluidVolumeWebGPUBackend } from './FluidVolumeWebGPUBackend';
import { ParticleWebGL2Backend } from './ParticleWebGL2Backend';
import { RawWebGPUBackend } from './RawWebGPUBackend';
import { WebGL2Backend } from './WebGL2Backend';

export function createRendererBackend(options: RendererBackendOptions): RendererBackend {
  switch (options.experiment.backend) {
    case 'webgl2':
      return new WebGL2Backend(options);
    case 'particle-webgl2':
      return new ParticleWebGL2Backend(options);
    case 'fluid-webgpu':
      return new FluidVolumeWebGPUBackend(options);
    case 'raw-webgpu':
    case 'webgpu':
      return new RawWebGPUBackend(options);
    case 'auto':
      return navigator.gpu && options.experiment.wgsl
        ? new RawWebGPUBackend(options)
        : new WebGL2Backend(options);
    default:
      throw new Error(`Unsupported renderer backend: ${String(options.experiment.backend)}`);
  }
}
