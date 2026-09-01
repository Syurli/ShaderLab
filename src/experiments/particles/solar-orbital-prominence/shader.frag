precision highp float;

in vec2 vUv;
in vec3 vColor;
in float vAlpha;
in float vSpark;
flat in float vSeed;
out vec4 outColor;

void main() {
  float r = length(vUv);
  float n1 = sin(vUv.x * 29.0 + vUv.y * 43.0 + vSeed * 91.7);
  float n2 = sin(vUv.x * 67.0 - vUv.y * 31.0 + vSeed * 37.3);
  float grain = clamp(0.5 + 0.25 * n1 + 0.14 * n2, 0.0, 1.0);
  float mask = 1.0 - smoothstep(0.58, 1.0, r + (grain - 0.5) * 0.075);
  if (mask < 0.01) discard;

  float core = 1.0 - smoothstep(0.0, 0.62, r);
  float sparkle = vSpark * pow(max(core, 0.0), 5.0) * 1.55;
  vec3 color = vColor * (0.94 + 0.56 * core) + vec3(sparkle);
  outColor = vec4(color, mask * vAlpha * (0.86 + 0.14 * grain));
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uParticleCount": {
      "type": "int", "default": 28000, "min": 6000, "max": 60000, "step": 2000,
      "label": { "zh": "粒子数量", "en": "Particle Count" },
      "description": { "zh": "轨道版本会为日珥额外绘制局部 RGB 色散副本；此数值表示基础球面粒子数。", "en": "The orbital version adds localized RGB prominence copies; this value is the base shell-particle count." },
      "group": { "zh": "性能", "en": "Performance" }
    },
    "uEruptionRate": {
      "type": "float", "default": 1.7, "min": 0.25, "max": 4.5, "step": 0.05,
      "label": { "zh": "喷射频率", "en": "Eruption Rate" },
      "description": { "zh": "默认减少同时存在的喷发，避免参考图目标被大量离面粒子淹没。", "en": "The default reduces overlapping events so detached grains do not overwhelm the reference-like body." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uEruptionChance": {
      "type": "float", "default": 0.78, "min": 0.2, "max": 1.0, "step": 0.01,
      "label": { "zh": "喷发概率", "en": "Eruption Chance" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uInfluenceRadius": {
      "type": "float", "default": 0.50, "min": 0.12, "max": 0.9, "step": 0.01,
      "label": { "zh": "局部波及范围", "en": "Local Influence Radius" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uEjectionDensity": {
      "type": "float", "default": 3.8, "min": 0.5, "max": 4.0, "step": 0.05,
      "label": { "zh": "喷射粒子密度", "en": "Ejection Density" },
      "description": { "zh": "提高真正参与日珥的局部粒子密度，让 RGB 分离形成连续光边而不是零散彩点。", "en": "Raises local prominence density so RGB separation forms continuous fringes rather than isolated colored dots." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uSourceExcavation": {
      "type": "float", "default": 1.6, "min": 0.8, "max": 2.4, "step": 0.05,
      "label": { "zh": "源区掀开范围", "en": "Source Excavation" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uRibbonLength": {
      "type": "float", "default": 0.24, "min": 0.045, "max": 0.36, "step": 0.005,
      "label": { "zh": "喷射条长度", "en": "Ribbon Length" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uRibbonWidth": {
      "type": "float", "default": 0.032, "min": 0.006, "max": 0.07, "step": 0.001,
      "label": { "zh": "喷射条宽度", "en": "Ribbon Width" },
      "description": { "zh": "保持较窄的日珥束，让局部红绿蓝副本形成清晰色散边。", "en": "Keeps the prominence narrow so the local red/green/blue copies form crisp spectral fringes." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uArcHeight": {
      "type": "float", "default": 0.34, "min": 0.12, "max": 1.3, "step": 0.01,
      "label": { "zh": "日珥高度", "en": "Arc Height" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uArcLength": {
      "type": "float", "default": 0.58, "min": 0.05, "max": 0.95, "step": 0.01,
      "label": { "zh": "弧向展开", "en": "Arc Span" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uShapeRandomness": {
      "type": "float", "default": 0.58, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "形状随机度", "en": "Shape Randomness" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uShellCoverage": {
      "type": "float", "default": 0.76, "min": 0.25, "max": 0.95, "step": 0.01,
      "label": { "zh": "球面覆盖率", "en": "Shell Coverage" },
      "description": { "zh": "让主体优先读成高亮白色颗粒壳，同时保留几块大的镂空。", "en": "Makes the body read first as a bright white grain shell while retaining several large holes." },
      "group": { "zh": "球面形态", "en": "Shell Pattern" }
    },
    "uShellPatternScale": {
      "type": "float", "default": 0.88, "min": 0.45, "max": 2.5, "step": 0.05,
      "label": { "zh": "大陆纹理尺度", "en": "Continent Scale" },
      "group": { "zh": "球面形态", "en": "Shell Pattern" }
    },
    "uFlightDuration": {
      "type": "float", "default": 2.1, "min": 0.55, "max": 3.5, "step": 0.05,
      "label": { "zh": "飞行时长", "en": "Flight Duration" },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uRotationSpeed": {
      "type": "float", "default": 1.20, "min": 0.0, "max": 3.0, "step": 0.05,
      "label": { "zh": "球面旋转速度", "en": "Shell Rotation" },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uReturnDamping": {
      "type": "float", "default": 1.35, "min": 0.3, "max": 6.0, "step": 0.05,
      "label": { "zh": "回落阻尼", "en": "Return Damping" },
      "group": { "zh": "回落", "en": "Return" }
    },
    "uReturnFrequency": {
      "type": "float", "default": 1.0, "min": 0.3, "max": 4.0, "step": 0.05,
      "label": { "zh": "回落振动频率", "en": "Return Oscillation" },
      "group": { "zh": "回落", "en": "Return" }
    },
    "uSurfaceWave": {
      "type": "float", "default": 0.065, "min": 0.0, "max": 0.4, "step": 0.005,
      "label": { "zh": "球面波浪强度", "en": "Surface Wave Strength" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveRange": {
      "type": "float", "default": 1.45, "min": 0.25, "max": 2.0, "step": 0.025,
      "label": { "zh": "球面波传播范围", "en": "Wave Range" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveSpeed": {
      "type": "float", "default": 0.68, "min": 0.25, "max": 4.0, "step": 0.05,
      "label": { "zh": "球面波速度", "en": "Wave Speed" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveDamping": {
      "type": "float", "default": 0.42, "min": 0.05, "max": 2.5, "step": 0.025,
      "label": { "zh": "球面波衰减", "en": "Wave Damping" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uParticleSize": {
      "type": "float", "default": 0.68, "min": 0.35, "max": 2.2, "step": 0.05,
      "label": { "zh": "粒子尺寸", "en": "Particle Size" },
      "group": { "zh": "外观", "en": "Appearance" }
    },
    "uShellColor": {
      "type": "color", "default": "#ffffff",
      "label": { "zh": "球面粒子颜色", "en": "Shell Color" },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uShellBrightness": {
      "type": "float", "default": 3.60, "min": 0.2, "max": 5.0, "step": 0.05,
      "label": { "zh": "球面亮度", "en": "Shell Brightness" },
      "description": { "zh": "主体保持纯白高亮；局部 RGB 色散不会再污染球面。", "en": "Keeps the body bright white; localized RGB dispersion no longer contaminates the shell." },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uProminenceHueOffset": {
      "type": "float", "default": 0.0, "min": -0.5, "max": 0.5, "step": 0.01,
      "label": { "zh": "色散起点偏移", "en": "Dispersion Offset" },
      "group": { "zh": "色散", "en": "Dispersion" }
    },
    "uProminenceHueSpan": {
      "type": "float", "default": 1.0, "min": 0.15, "max": 1.5, "step": 0.02,
      "label": { "zh": "色散展开", "en": "Dispersion Spread" },
      "group": { "zh": "色散", "en": "Dispersion" }
    },
    "uProminenceSaturation": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "日珥色散饱和度", "en": "Dispersion Saturation" },
      "group": { "zh": "色散", "en": "Dispersion" }
    },
    "uProminenceBrightness": {
      "type": "float", "default": 2.8, "min": 0.2, "max": 5.0, "step": 0.05,
      "label": { "zh": "日珥亮度", "en": "Prominence Brightness" },
      "group": { "zh": "色散", "en": "Dispersion" }
    },
    "uDispersionSeparation": {
      "type": "float", "default": 1.35, "min": 0.0, "max": 3.0, "step": 0.05,
      "label": { "zh": "日珥光谱宽度", "en": "Prominence Spectrum Width" },
      "description": { "zh": "控制日珥内部的物理光谱展开，不会作用到静止球面。", "en": "Controls physical spectrum spread inside prominence ribbons only, never the resting shell." },
      "group": { "zh": "色散", "en": "Dispersion" }
    },
    "uChromaticAberration": {
      "type": "float", "default": 1.25, "min": 0.0, "max": 3.0, "step": 0.05,
      "label": { "zh": "局部 RGB 分离强度", "en": "Localized RGB Split" },
      "description": { "zh": "不再是全屏后期。只复制真正离开球面的日珥粒子，并将红、绿、蓝三层局部错开。", "en": "No longer a full-screen post effect. Only true prominence particles receive locally offset red, green and blue copies." },
      "group": { "zh": "局部色散", "en": "Localized Dispersion" }
    },
    "uChromaticThreshold": {
      "type": "float", "default": 0.12, "min": 0.0, "max": 0.8, "step": 0.01,
      "label": { "zh": "局部色散触发阈值", "en": "Local Split Threshold" },
      "description": { "zh": "提高后只有更明确的日珥离面部分才生成 RGB 副本，可彻底避免球体染色。", "en": "Higher values restrict RGB copies to more clearly detached prominence regions and keep the shell clean." },
      "group": { "zh": "局部色散", "en": "Localized Dispersion" }
    },
    "uChromaticGlow": {
      "type": "float", "default": 1.15, "min": 0.0, "max": 2.0, "step": 0.05,
      "label": { "zh": "RGB 色边亮度", "en": "RGB Fringe Brightness" },
      "description": { "zh": "控制局部红绿蓝色边的亮度，而不会改变白色球面的亮度。", "en": "Controls localized RGB fringe brightness without changing the white shell." },
      "group": { "zh": "局部色散", "en": "Localized Dispersion" }
    },
    "uOrbitLineColor": {
      "type": "color", "default": "#ffffff",
      "label": { "zh": "轨道线颜色", "en": "Orbit Line Color" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitLineBrightness": {
      "type": "float", "default": 0.62, "min": 0.2, "max": 4.0, "step": 0.05,
      "label": { "zh": "轨道线亮度", "en": "Orbit Brightness" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitLineOpacity": {
      "type": "float", "default": 0.22, "min": 0.05, "max": 1.0, "step": 0.01,
      "label": { "zh": "轨道线透明度", "en": "Orbit Opacity" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitThickness": {
      "type": "float", "default": 0.0009, "min": 0.0004, "max": 0.02, "step": 0.0001,
      "label": { "zh": "轨道线粗细", "en": "Orbit Thickness" },
      "description": { "zh": "进一步压细轨道，使它更接近参考图的微弱光丝。", "en": "Further thins the orbit toward the reference's subtle filament-like line." },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitRadius": {
      "type": "float", "default": 1.62, "min": 1.20, "max": 3.2, "step": 0.05,
      "label": { "zh": "轨道半径", "en": "Orbit Radius" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitRotationSpeed": {
      "type": "float", "default": 0.48, "min": 0.0, "max": 3.0, "step": 0.05,
      "label": { "zh": "轨道旋转速度", "en": "Orbit Rotation" },
      "description": { "zh": "轨道使用多个不同低频分量缓慢漂移，不再表现为规则刚体旋转。", "en": "The orbit drifts through several slow incommensurate terms rather than a regular rigid rotation." },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitPulse": {
      "type": "float", "default": 0.020, "min": 0.0, "max": 0.18, "step": 0.002,
      "label": { "zh": "轨道不规则律动", "en": "Orbit Irregular Pulse" },
      "description": { "zh": "控制轨道不同位置互不同步的慢速呼吸形变。", "en": "Controls slow asynchronous breathing deformation at different points along the single closed orbit." },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitPullStrength": {
      "type": "float", "default": 0.80, "min": 0.0, "max": 1.2, "step": 0.02,
      "label": { "zh": "轨道牵引强度", "en": "Orbit Pull Strength" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitInfluenceWidth": {
      "type": "float", "default": 0.07, "min": 0.025, "max": 0.28, "step": 0.005,
      "label": { "zh": "轨道牵引范围", "en": "Tether Width" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitHighlightStrength": {
      "type": "float", "default": 1.35, "min": 0.0, "max": 4.0, "step": 0.05,
      "label": { "zh": "牵引段高亮", "en": "Tether Highlight" },
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