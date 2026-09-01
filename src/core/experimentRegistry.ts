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
import orbitalCutterPlasmaVertex from '../experiments/particles/orbital-cutter-plasma/shader.vert?raw';
import orbitalCutterPlasmaFragment from '../experiments/particles/orbital-cutter-plasma/shader.frag?raw';

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
    description: { zh: '用一根首尾相连的高亮白色闭合曲线缠绕粒子球。活跃轨道段会向球面弯下并同步增亮，其径向投影直接成为日珥根部；被掀起的粒子沿轨道切线牵引，并使用暖白到红、金、青、蓝、紫的阳光色散映射。轨道粗细、牵引强度与高亮均可参数化。', en: 'A single luminous closed curve weaves around the particle shell. Active orbit segments bend toward the surface and brighten in sync; their radial projection becomes the prominence root, while lifted particles follow the orbit tangent and map through a sunlight-dispersion palette from warm white/red through gold, cyan, blue and violet. Orbit thickness, pull and highlight are parameterized.' },
    category: { zh: '粒子', en: 'Particles' }, tags: ['WebGL2','GLSL','Particles','Prominence','Continuous Orbit','Tether','HLSL-portable'], backend: 'particle-webgl2', languages: ['GLSL'], sourceFile: 'shader.frag', maxPixelRatio: 1.25, vertexShader: solarOrbitalProminenceVertex, fragmentShader: solarOrbitalProminenceFragment,
  }),
  defineExperiment({
    id: 'orbital-cutter-plasma', title: { zh: '轨道切割等离子粒子球', en: 'Orbital Cutter Plasma Shell' },
    description: { zh: '下一阶段的轨道动力学实验：停止球心驱动的日珥力，改由活跃轨道线段向球面贴合并执行切割。切口中的原始球面粒子被直接剥离，沿轨道切线形成火焰/等离子日珥尾迹；切割线段向两侧传播表面波纹，并在空中额外生成大尺寸、强色散的光斑粒子。', en: 'A next-stage orbital dynamics experiment with no center-driven prominence force. Active orbit segments bend into the shell and cut it directly: original shell grains are stripped into flame/plasma wakes along the orbit tangent, cut ripples propagate laterally from the segment, and large strongly dispersed flare sprites are spawned directly in the airborne wake.' },
    category: { zh: '粒子', en: 'Particles' }, tags: ['WebGL2','GLSL','Particles','Orbital Cutter','Plasma','Chromatic Flares','HLSL-portable'], backend: 'particle-webgl2', languages: ['GLSL'], sourceFile: 'shader.frag', maxPixelRatio: 1.2, vertexShader: orbitalCutterPlasmaVertex, fragmentShader: orbitalCutterPlasmaFragment,
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
