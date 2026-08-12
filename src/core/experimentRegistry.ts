import type { ExperimentDefinition } from './types';
import { parseShaderLabMetadata } from './shaderMetadata';
import commonVertex from './commonVertex.glsl?raw';
import uvGradientFragment from '../experiments/basics/uv-gradient/shader.frag?raw';
import sdfSphereFragment from '../experiments/raymarch/sdf-sphere/shader.frag?raw';
import basicVolumeFragment from '../experiments/volume/basic-volume/shader.frag?raw';
import chimneySmokeWGSL from '../experiments/volume/chimney-smoke/shader.wgsl?raw';
import interactiveFluidGasWGSL from '../experiments/volume/interactive-fluid-gas/shader.wgsl?raw';

type ExperimentInput = Omit<ExperimentDefinition, 'metadata'>;

function defineExperiment(definition: ExperimentInput): ExperimentDefinition {
  const metadataSource = definition.wgsl ?? definition.fragmentShader;
  if (!metadataSource) {
    throw new Error(`[ShaderLab] Experiment ${definition.id} has no shader source.`);
  }

  return {
    ...definition,
    metadata: parseShaderLabMetadata(metadataSource),
  };
}

function defineGLSLExperiment(
  definition: Omit<ExperimentInput, 'vertexShader' | 'wgsl' | 'sourceFile'> & {
    sourceFile?: string;
  },
): ExperimentDefinition {
  return defineExperiment({
    ...definition,
    sourceFile: definition.sourceFile ?? 'shader.frag',
    vertexShader: commonVertex,
  });
}

export const experiments: ExperimentDefinition[] = [
  defineGLSLExperiment({
    id: 'uv-gradient',
    title: { zh: 'UV 渐变与波形', en: 'UV Gradient & Waves' },
    description: {
      zh: '最小全屏 GLSL 实验，用于验证参数注释、实时 uniform 更新和基础画布框架。',
      en: 'A minimal fullscreen GLSL experiment validating metadata-driven parameters, realtime uniforms, and the base canvas runner.',
    },
    category: { zh: '基础', en: 'Basics' },
    tags: ['WebGL2', 'GLSL', 'UV'],
    backend: 'webgl2',
    languages: ['GLSL'],
    fragmentShader: uvGradientFragment,
  }),
  defineGLSLExperiment({
    id: 'sdf-sphere',
    title: { zh: 'SDF 球体 Ray Marching', en: 'SDF Sphere Ray Marching' },
    description: {
      zh: '使用球体 SDF 和法线估算的基础 Sphere Tracing / Ray Marching 实验。',
      en: 'A foundational sphere-tracing experiment using a sphere SDF and finite-difference normal estimation.',
    },
    category: { zh: '光线步进', en: 'Raymarch' },
    tags: ['WebGL2', 'GLSL', 'SDF', 'Raymarch'],
    backend: 'webgl2',
    languages: ['GLSL'],
    fragmentShader: sdfSphereFragment,
  }),
  defineGLSLExperiment({
    id: 'basic-volume',
    title: { zh: '基础体积 Ray Marching', en: 'Basic Volume Ray Marching' },
    description: {
      zh: '在解析密度场中进行前向体积积分，展示密度、吸收、步数与抖动对结果的影响。',
      en: 'Front-to-back volume integration through an analytic density field, exposing density, absorption, steps, and jitter.',
    },
    category: { zh: '体积', en: 'Volume' },
    tags: ['WebGL2', 'GLSL', 'Volume', 'Raymarch'],
    backend: 'webgl2',
    languages: ['GLSL'],
    fragmentShader: basicVolumeFragment,
  }),
  defineExperiment({
    id: 'chimney-smoke',
    title: { zh: '烟囱烟雾体积渲染', en: 'Chimney Smoke Volume' },
    description: {
      zh: 'Raw WebGPU + WGSL 的程序化烟柱：使用多尺度 FBM、域扭曲涡旋、向上平流、细节侵蚀、体积光线步进、Beer-Lambert 吸收、近似自阴影与 Henyey-Greenstein 相函数。',
      en: 'A Raw WebGPU + WGSL procedural smoke plume using multi-scale FBM, domain-warped vortices, upward advection, detail erosion, volume ray marching, Beer-Lambert absorption, approximate self-shadowing, and a Henyey-Greenstein phase function.',
    },
    category: { zh: '体积', en: 'Volume' },
    tags: ['WebGPU', 'WGSL', 'Volume', 'Smoke', 'Raymarch'],
    backend: 'raw-webgpu',
    languages: ['WGSL'],
    sourceFile: 'shader.wgsl',
    renderScale: 1.0,
    maxPixelRatio: 1.25,
    wgsl: chimneySmokeWGSL,
  }),
  defineExperiment({
    id: 'interactive-fluid-gas',
    title: { zh: '爆裂分形气体核心', en: 'Burst Fractal Gas Core' },
    description: {
      zh: 'Raw WebGPU + WGSL 的二维解算/三维体积混合实验：平静核心持续三维蠕动；点击或音频节拍触发爆裂后完整核心快速消失，由二维半拉格朗日场驱动三维细枝、褶皱和独立 metaball-like 微碎片展开，再随爆裂记忆耗散重新聚合。支持暂停音频驱动、轨道相机和无帧率限制性能测试。',
      en: 'A Raw WebGPU + WGSL 2D-solver/3D-volume hybrid: the idle core continuously crawls in 3D, while pointer or audio bursts collapse the intact core and unfold sharp branches, folds, and independent metaball-like micro fragments driven by a semi-Lagrangian field. The volume reforms as burst memory dissipates, with audio pause, orbit-camera, and uncapped benchmark controls.',
    },
    category: { zh: '体积', en: 'Volume' },
    tags: ['WebGPU', 'WGSL', 'Volume', '2D Fluid', 'Fractal', 'Metaball', 'Burst', 'Audio Reactive', 'Raymarch'],
    backend: 'fluid-webgpu',
    languages: ['WGSL'],
    sourceFile: 'shader.wgsl',
    renderScale: 0.76,
    maxPixelRatio: 1.0,
    wgsl: interactiveFluidGasWGSL,
  }),
];

export function getExperiment(id: string | undefined): ExperimentDefinition | undefined {
  return experiments.find((experiment) => experiment.id === id);
}