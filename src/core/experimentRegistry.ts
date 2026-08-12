import type { ExperimentDefinition } from './types';
import { parseShaderLabMetadata } from './shaderMetadata';
import commonVertex from './commonVertex.glsl?raw';
import uvGradientFragment from '../experiments/basics/uv-gradient/shader.frag?raw';
import sdfSphereFragment from '../experiments/raymarch/sdf-sphere/shader.frag?raw';
import basicVolumeFragment from '../experiments/volume/basic-volume/shader.frag?raw';

function defineExperiment(
  definition: Omit<ExperimentDefinition, 'metadata' | 'vertexShader'> & {
    vertexShader?: string;
  },
): ExperimentDefinition {
  return {
    ...definition,
    vertexShader: definition.vertexShader ?? commonVertex,
    metadata: parseShaderLabMetadata(definition.fragmentShader),
  };
}

export const experiments: ExperimentDefinition[] = [
  defineExperiment({
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
  defineExperiment({
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
  defineExperiment({
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
];

export function getExperiment(id: string | undefined): ExperimentDefinition | undefined {
  return experiments.find((experiment) => experiment.id === id);
}
