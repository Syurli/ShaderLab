import type { ExperimentDefinition } from './types';
import { parseShaderLabMetadata } from './shaderMetadata';
import commonVertex from './commonVertex.glsl?raw';
import uvGradientFragment from '../experiments/basics/uv-gradient/shader.frag?raw';
import sdfSphereFragment from '../experiments/raymarch/sdf-sphere/shader.frag?raw';
import basicVolumeFragment from '../experiments/volume/basic-volume/shader.frag?raw';
import chimneySmokeWGSL from '../experiments/volume/chimney-smoke/shader.wgsl?raw';
import interactiveFluidGasWGSL from '../experiments/volume/interactive-fluid-gas/shader.wgsl?raw';
import solarProminenceVertex from '../experiments/particles/solar-prominence/shader.vert?raw';
import solarProminenceFragment from '../experiments/particles/solar-prominence/shader.frag?raw';
import solarOrbitalProminenceVertex from '../experiments/particles/solar-orbital-prominence/shader.vert?raw';
import solarOrbitalProminenceFragment from '../experiments/particles/solar-orbital-prominence/shader.frag?raw';

const interactiveFluidGasRuntimeWGSL = interactiveFluidGasWGSL.replace(/\bactive\b/g, 'burstActivity');
type ExperimentInput = Omit<ExperimentDefinition, 'metadata'>;

function defineExperiment(definition: ExperimentInput): ExperimentDefinition {
  const metadataSource = definition.wgsl ?? definition.fragmentShader;
  if (!metadataSource) throw new Error(`[ShaderLab] Experiment ${definition.id} has no shader source.`);
  return { ...definition, metadata: parseShaderLabMetadata(metadataSource) };
}

function defineGLSLExperiment(definition: Omit<ExperimentInput, 'vertexShader' | 'wgsl' | 'sourceFile'> & { sourceFile?: string }): ExperimentDefinition {
  return defineExperiment({ ...definition, sourceFile: definition.sourceFile ?? 'shader.frag', vertexShader: commonVertex });
}

export const experiments: ExperimentDefinition[] = [
  defineGLSLExperiment({
    id: 'uv-gradient', title: { zh: 'UV 渐变与波形', en: 'UV Gradient & Waves' },
    description: { zh: '最小全屏 GLSL 实验，用于验证参数注释、实时 uniform 更新和基础画布框架。', en: 'A minimal fullscreen GLSL experiment validating metadata-driven parameters, realtime uniforms, and the base canvas runner.' },
    category: { zh: '基础', en: 'Basics' }, tags: ['WebGL2','GLSL','UV'], backend: 'webgl2', languages: ['GLSL'], fragmentShader: uvGradientFragment,
  }),
  defineGLSLExperiment({
    id: 'sdf-sphere', title: { zh: 'SDF 球体 Ray Marching', en: 'SDF Sphere Ray Marching' },
    description: { zh: '使用球体 SDF 和法线估算的基础 Sphere Tracing / Ray Marching 实验。', en: 'A foundational sphere-tracing experiment using a sphere SDF and finite-difference normal estimation.' },
    category: { zh: '光线步进', en: 'Raymarch' }, tags: ['WebGL2','GLSL','SDF','Raymarch'], backend: 'webgl2', languages: ['GLSL'], fragmentShader: sdfSphereFragment,
  }),
  defineGLSLExperiment({
    id: 'basic-volume', title: { zh: '基础体积 Ray Marching', en: 'Basic Volume Ray Marching' },
    description: { zh: '在解析密度场中进行前向体积积分，展示密度、吸收、步数与抖动对结果的影响。', en: 'Front-to-back volume integration through an analytic density field, exposing density, absorption, steps, and jitter.' },
    category: { zh: '体积', en: 'Volume' }, tags: ['WebGL2','GLSL','Volume','Raymarch'], backend: 'webgl2', languages: ['GLSL'], fragmentShader: basicVolumeFragment,
  }),
  defineExperiment({
    id: 'solar-prominence', title: { zh: '太阳日珥粒子弧', en: 'Solar Prominence Particle Arcs' },
    description: { zh: '大陆式镂空白色粒子球面与可参数化日珥喷发。保留纯粒子版本，不包含外围轨道线。', en: 'A hollow continent-like particle shell with parameterized prominence eruptions. This is the particle-only version without orbital lines.' },
    category: { zh: '粒子', en: 'Particles' }, tags: ['WebGL2','GLSL','Particles','Prominence','HLSL-portable'], backend: 'particle-webgl2', languages: ['GLSL'], sourceFile: 'shader.frag', maxPixelRatio: 1.25, vertexShader: solarProminenceVertex, fragmentShader: solarProminenceFragment,
  }),
  defineExperiment({
    id: 'solar-orbital-prominence', title: { zh: '轨道线日珥粒子球', en: 'Orbital-Line Solar Prominence' },
    description: { zh: '在日珥粒子球外加入四条首尾相接的高亮白色电子轨道线。轨道缓慢旋转并律动，喷发源严格取自轨道线向球面的径向投影；同时提供球面颜色、亮度和日珥连续光谱映射参数。', en: 'Adds four closed luminous electron-like orbit lines around the prominence shell. The lines rotate and pulse slowly, and eruption sources are taken from their radial projection onto the sphere, with adjustable shell color/brightness and prominence spectrum mapping.' },
    category: { zh: '粒子', en: 'Particles' }, tags: ['WebGL2','GLSL','Particles','Prominence','Orbit Lines','HLSL-portable'], backend: 'particle-webgl2', languages: ['GLSL'], sourceFile: 'shader.frag', maxPixelRatio: 1.25, vertexShader: solarOrbitalProminenceVertex, fragmentShader: solarOrbitalProminenceFragment,
  }),
  defineExperiment({
    id: 'chimney-smoke', title: { zh: '烟囱烟雾体积渲染', en: 'Chimney Smoke Volume' },
    description: { zh: 'Raw WebGPU + WGSL 的程序化烟柱：使用多尺度 FBM、域扭曲涡旋、向上平流、细节侵蚀、体积光线步进、Beer-Lambert 吸收、近似自阴影与 Henyey-Greenstein 相函数。', en: 'A Raw WebGPU + WGSL procedural smoke plume using multi-scale FBM, domain-warped vortices, upward advection, detail erosion, volume ray marching, Beer-Lambert absorption, approximate self-shadowing, and a Henyey-Greenstein phase function.' },
    category: { zh: '体积', en: 'Volume' }, tags: ['WebGPU','WGSL','Volume','Smoke','Raymarch'], backend: 'raw-webgpu', languages: ['WGSL'], sourceFile: 'shader.wgsl', renderScale: 1.0, maxPixelRatio: 1.25, wgsl: chimneySmokeWGSL,
  }),
  defineExperiment({
    id: 'interactive-fluid-gas', title: { zh: '爆裂分形气体核心', en: 'Burst Fractal Gas Core' },
    description: { zh: 'Raw WebGPU + WGSL 的二维解算/三维体积混合实验：较小的细节化核心持续三维蠕动；点击或音频节拍将同一团材质沿稀疏径向主干撕开，再由延迟涡量卷曲并通过弹性位移解算融合回核心。', en: 'A Raw WebGPU + WGSL 2D-solver/3D-volume hybrid with a compact detailed core, radial tearing, delayed vorticity and elastic return.' },
    category: { zh: '体积', en: 'Volume' }, tags: ['WebGPU','WGSL','Volume','2D Fluid','Fractal','Elastic Burst','Audio Reactive','Raymarch'], backend: 'fluid-webgpu', languages: ['WGSL'], sourceFile: 'shader.wgsl', renderScale: 1.0, maxPixelRatio: 1.0, wgsl: interactiveFluidGasRuntimeWGSL,
  }),
];

export function getExperiment(id: string | undefined): ExperimentDefinition | undefined {
  return experiments.find((experiment) => experiment.id === id);
}
