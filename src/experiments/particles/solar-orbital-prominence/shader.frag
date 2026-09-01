precision highp float;

in vec2 vUv;
in vec3 vColor;
in float vAlpha;
in float vSpark;
flat in float vSeed;
out vec4 outColor;

void main() {
  float r = length(vUv);
  float n1 = sin(vUv.x * 31.0 + vUv.y * 47.0 + vSeed * 91.7);
  float n2 = sin(vUv.x * 73.0 - vUv.y * 29.0 + vSeed * 37.3);
  float grain = clamp(0.5 + 0.32 * n1 + 0.18 * n2, 0.0, 1.0);
  float mask = 1.0 - smoothstep(0.52, 0.98, r + (grain - 0.5) * 0.10);
  if (mask < 0.01) discard;

  float core = 1.0 - smoothstep(0.0, 0.68, r);
  float sparkle = vSpark * pow(max(core, 0.0), 5.0) * 1.85;
  vec3 color = vColor * (0.82 + 0.55 * core) + vec3(sparkle);
  outColor = vec4(color, mask * vAlpha * (0.80 + 0.20 * grain));
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uParticleCount": {
      "type": "int", "default": 14000, "min": 6000, "max": 200000, "step": 2000,
      "label": { "zh": "粒子数量", "en": "Particle Count" },
      "group": { "zh": "性能", "en": "Performance" }
    },
    "uEruptionRate": {
      "type": "float", "default": 4.5, "min": 0.25, "max": 4.5, "step": 0.05,
      "label": { "zh": "喷射频率", "en": "Eruption Rate" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uEruptionChance": {
      "type": "float", "default": 1.0, "min": 0.2, "max": 1.0, "step": 0.01,
      "label": { "zh": "喷发概率", "en": "Eruption Chance" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uInfluenceRadius": {
      "type": "float", "default": 0.9, "min": 0.12, "max": 0.9, "step": 0.01,
      "label": { "zh": "局部波及范围", "en": "Local Influence Radius" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uEjectionDensity": {
      "type": "float", "default": 4.0, "min": 0.5, "max": 4.0, "step": 0.05,
      "label": { "zh": "喷射粒子密度", "en": "Ejection Density" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uSourceExcavation": {
      "type": "float", "default": 2.4, "min": 0.8, "max": 2.4, "step": 0.05,
      "label": { "zh": "源区掀开范围", "en": "Source Excavation" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uRibbonLength": {
      "type": "float", "default": 0.36, "min": 0.045, "max": 0.36, "step": 0.005,
      "label": { "zh": "喷射条长度", "en": "Ribbon Length" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uRibbonWidth": {
      "type": "float", "default": 0.07, "min": 0.006, "max": 0.07, "step": 0.001,
      "label": { "zh": "喷射条宽度", "en": "Ribbon Width" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uArcHeight": {
      "type": "float", "default": 0.39, "min": 0.12, "max": 1.3, "step": 0.01,
      "label": { "zh": "日珥高度", "en": "Arc Height" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uArcLength": {
      "type": "float", "default": 0.95, "min": 0.05, "max": 0.95, "step": 0.01,
      "label": { "zh": "弧向展开", "en": "Arc Span" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uShapeRandomness": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "形状随机度", "en": "Shape Randomness" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uShellCoverage": {
      "type": "float", "default": 0.32, "min": 0.25, "max": 0.95, "step": 0.01,
      "label": { "zh": "球面覆盖率", "en": "Shell Coverage" },
      "group": { "zh": "球面形态", "en": "Shell Pattern" }
    },
    "uShellPatternScale": {
      "type": "float", "default": 1.8, "min": 0.45, "max": 2.5, "step": 0.05,
      "label": { "zh": "大陆纹理尺度", "en": "Continent Scale" },
      "group": { "zh": "球面形态", "en": "Shell Pattern" }
    },
    "uFlightDuration": {
      "type": "float", "default": 2.45, "min": 0.55, "max": 3.5, "step": 0.05,
      "label": { "zh": "飞行时长", "en": "Flight Duration" },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uRotationSpeed": {
      "type": "float", "default": 3.0, "min": 0.0, "max": 3.0, "step": 0.05,
      "label": { "zh": "球面旋转速度", "en": "Shell Rotation" },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uReturnDamping": {
      "type": "float", "default": 1.55, "min": 0.3, "max": 6.0, "step": 0.05,
      "label": { "zh": "回落阻尼", "en": "Return Damping" },
      "group": { "zh": "回落", "en": "Return" }
    },
    "uReturnFrequency": {
      "type": "float", "default": 1.05, "min": 0.3, "max": 4.0, "step": 0.05,
      "label": { "zh": "回落振动频率", "en": "Return Oscillation" },
      "group": { "zh": "回落", "en": "Return" }
    },
    "uSurfaceWave": {
      "type": "float", "default": 0.075, "min": 0.0, "max": 0.4, "step": 0.005,
      "label": { "zh": "球面波浪强度", "en": "Surface Wave Strength" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveRange": {
      "type": "float", "default": 2.0, "min": 0.25, "max": 2.0, "step": 0.025,
      "label": { "zh": "球面波传播范围", "en": "Wave Range" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveSpeed": {
      "type": "float", "default": 0.5, "min": 0.25, "max": 4.0, "step": 0.05,
      "label": { "zh": "球面波速度", "en": "Wave Speed" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveDamping": {
      "type": "float", "default": 0.3, "min": 0.05, "max": 2.5, "step": 0.025,
      "label": { "zh": "球面波衰减", "en": "Wave Damping" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uParticleSize": {
      "type": "float", "default": 1.05, "min": 0.4, "max": 2.2, "step": 0.05,
      "label": { "zh": "粒子尺寸", "en": "Particle Size" },
      "description": { "zh": "参考图风格默认更细小，让白色球面形成高密度砂砾而不是大光点。", "en": "Smaller reference-style grains keep the shell dense and sandy instead of reading as large light dots." },
      "group": { "zh": "外观", "en": "Appearance" }
    },
    "uShellColor": {
      "type": "color", "default": "#ffffff",
      "label": { "zh": "球面粒子颜色", "en": "Shell Color" },
      "description": { "zh": "静止球面粒子的基础颜色。", "en": "Base color of resting shell particles." },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uShellBrightness": {
      "type": "float", "default": 2.05, "min": 0.2, "max": 4.0, "step": 0.05,
      "label": { "zh": "球面亮度", "en": "Shell Brightness" },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uProminenceHueOffset": {
      "type": "float", "default": 0.0, "min": -0.5, "max": 0.5, "step": 0.01,
      "label": { "zh": "色散起点偏移", "en": "Dispersion Offset" },
      "description": { "zh": "沿阳光色散序列平移日珥颜色起点。0 从暖白/红橙开始。", "en": "Offsets the start point along the sunlight-dispersion palette. Zero starts at warm white/red-orange." },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uProminenceHueSpan": {
      "type": "float", "default": 1.15, "min": 0.15, "max": 1.5, "step": 0.02,
      "label": { "zh": "色散展开", "en": "Dispersion Spread" },
      "description": { "zh": "现在主要控制日珥横向色散分离程度；越高越容易在同一条喷发中同时看到红黄绿青蓝紫。", "en": "Primarily controls transverse spectral separation; higher values reveal more simultaneous prism colors within one prominence." },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uProminenceSaturation": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "日珥色散饱和度", "en": "Dispersion Saturation" },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uProminenceBrightness": {
      "type": "float", "default": 2.2, "min": 0.2, "max": 4.0, "step": 0.05,
      "label": { "zh": "日珥亮度", "en": "Prominence Brightness" },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uOrbitLineColor": {
      "type": "color", "default": "#ffffff",
      "label": { "zh": "轨道线颜色", "en": "Orbit Line Color" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitLineBrightness": {
      "type": "float", "default": 1.45, "min": 0.2, "max": 4.0, "step": 0.05,
      "label": { "zh": "轨道线亮度", "en": "Orbit Brightness" },
      "description": { "zh": "参考图默认降低常态轨道亮度，喷发牵引段仍会局部增强并出现轻微色散。", "en": "The reference preset keeps idle orbit lines subdued while active tether segments brighten and gain slight chromatic dispersion." },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitLineOpacity": {
      "type": "float", "default": 0.62, "min": 0.05, "max": 1.0, "step": 0.01,
      "label": { "zh": "轨道线透明度", "en": "Orbit Opacity" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitThickness": {
      "type": "float", "default": 0.0035, "min": 0.0015, "max": 0.035, "step": 0.0005,
      "label": { "zh": "轨道线粗细", "en": "Orbit Thickness" },
      "description": { "zh": "单根闭合轨道的世界空间半径。参考图预设明显变细，与细小球面粒子的比例更接近光丝。", "en": "World-space radius of the single closed orbit tube. The reference preset is much thinner relative to the smaller shell grains." },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitRadius": {
      "type": "float", "default": 2.30, "min": 1.75, "max": 3.2, "step": 0.05,
      "label": { "zh": "轨道半径", "en": "Orbit Radius" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitRotationSpeed": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 3.0, "step": 0.05,
      "label": { "zh": "轨道旋转速度", "en": "Orbit Rotation" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitPulse": {
      "type": "float", "default": 0.025, "min": 0.0, "max": 0.18, "step": 0.005,
      "label": { "zh": "轨道律动幅度", "en": "Orbit Pulse" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitPullStrength": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 1.2, "step": 0.02,
      "label": { "zh": "轨道牵引强度", "en": "Orbit Pull Strength" },
      "description": { "zh": "控制活跃轨道段向球面靠近的程度，以及喷发粒子沿轨道切线被牵引的力度。", "en": "Controls how strongly the active orbit segment dips toward the shell and how strongly ejected particles follow the orbit tangent." },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitInfluenceWidth": {
      "type": "float", "default": 0.12, "min": 0.025, "max": 0.28, "step": 0.005,
      "label": { "zh": "轨道牵引范围", "en": "Tether Width" },
      "description": { "zh": "控制喷发点附近有多长一段轨道向球面弯下并参与牵引。", "en": "Controls how much of the orbit bends toward the shell around an active eruption point." },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitHighlightStrength": {
      "type": "float", "default": 1.8, "min": 0.0, "max": 4.0, "step": 0.05,
      "label": { "zh": "牵引段高亮", "en": "Tether Highlight" },
      "description": { "zh": "喷发发生时，对应轨道段会同步增强亮度并带少量色散，强化轨道牵引关系。", "en": "Brightens the active orbit segment and adds a small spectral tint to emphasize the tether relationship." },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uCameraDistance": {
      "type": "float", "default": 6.15, "min": 3.3, "max": 10.0, "step": 0.05,
      "label": { "zh": "相机距离", "en": "Camera Distance" },
      "group": { "zh": "观察", "en": "View" }
    }
  }
}
@endshaderlab */