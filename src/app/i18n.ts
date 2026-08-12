import type { Locale, LocalizedText } from '../core/types';

const messages = {
  zh: {
    gallery: '实验库',
    experiments: '实验',
    search: '搜索实验、标签或技术…',
    parameters: '参数',
    view: '预览',
    code: '代码',
    info: '说明',
    perf: '性能',
    reset: '重置参数',
    noParameters: '这个实验没有可调参数。',
    noResults: '没有找到匹配的实验。',
    openExperiment: '打开实验',
    source: 'Shader 源码',
    backend: '后端',
    languages: '语言',
    category: '分类',
    parameterRule: '参数注释由 Shader 源码自动解析',
    webgpuReady: 'WebGPU 可用',
    webgpuUnavailable: 'WebGPU 不可用',
    currentRenderer: '当前渲染器',
    frame: '帧时间',
    resolution: '分辨率',
    drawCalls: 'Draw Calls',
    introTitle: '实时图形实验室',
    introBody:
      '用于长期积累 WebGL、WebGPU、WGSL、GLSL、SDF、体积渲染、Compute 与后处理实验。每个实验独立、可参数化并可直接分享链接。',
    metadataHint:
      '变量名保持英文；面板名称、分组与说明由 Shader 尾部 @shaderlab JSON 注释提供中英文文本。',
    github: 'GitHub',
    fullscreen: '全屏',
    backToGallery: '返回实验库',
  },
  en: {
    gallery: 'Gallery',
    experiments: 'Experiments',
    search: 'Search experiments, tags, or techniques…',
    parameters: 'Parameters',
    view: 'View',
    code: 'Code',
    info: 'Info',
    perf: 'Perf',
    reset: 'Reset parameters',
    noParameters: 'This experiment has no adjustable parameters.',
    noResults: 'No matching experiments.',
    openExperiment: 'Open experiment',
    source: 'Shader source',
    backend: 'Backend',
    languages: 'Languages',
    category: 'Category',
    parameterRule: 'Parameter annotations are parsed from shader source',
    webgpuReady: 'WebGPU available',
    webgpuUnavailable: 'WebGPU unavailable',
    currentRenderer: 'Current renderer',
    frame: 'Frame time',
    resolution: 'Resolution',
    drawCalls: 'Draw Calls',
    introTitle: 'Realtime graphics laboratory',
    introBody:
      'A long-lived home for WebGL, WebGPU, WGSL, GLSL, SDF, volume rendering, compute, and post-processing experiments. Every experiment is isolated, parameterized, and directly shareable.',
    metadataHint:
      'Variable names stay in English. Chinese/English labels, groups, and descriptions come from the @shaderlab JSON block at the end of the shader.',
    github: 'GitHub',
    fullscreen: 'Fullscreen',
    backToGallery: 'Back to gallery',
  },
} as const;

export type MessageKey = keyof (typeof messages)['zh'];

export function t(locale: Locale, key: MessageKey): string {
  return messages[locale][key];
}

export function localize(locale: Locale, text: LocalizedText | string): string {
  if (typeof text === 'string') return text;
  return text[locale] || text.en || text.zh;
}
