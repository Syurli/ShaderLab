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
  float sparkle = vSpark * pow(max(core, 0.0), 5.0) * 1.65;
  vec3 color = vColor * (0.92 + 0.54 * core) + vec3(sparkle);
  outColor = vec4(color, mask * vAlpha * (0.86 + 0.14 * grain));
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uParticleCount": {
      "type": "int", "default": 34000, "min": 6000, "max": 200000, "step": 2000,
      "label": { "zh": "粒子数量", "en": "Particle Count" },
      "description": { "zh": "更小的中央球体使用更多细粒子维持连续高亮表面。", "en": "The smaller central body uses more fine grains to preserve a bright coherent surface." },
      "group": { "zh": "性能", "en": "Performance" }
    },
    "uEruptionRate": {
      "type": "float", "default": 2.1, "min": 0.25, "max": 4.5, "step": 0.05,
      "label": { "zh": "喷射频率", "en": "Eruption Rate" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uEruptionChance": {
      "type": "float", "default": 0.82, "min": 0.2, "max": 1.0, "step": 0.01,
      "label": { "zh": "喷发概率", "en": "Eruption Chance" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uInfluenceRadius": {
      "type": "float", "default": 0.58, "min": 0.12, "max": 0.9, "step": 0.01,
      "label": { "zh": "局部波及范围", "en": "Local Influence Radius" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uEjectionDensity": {
      "type": "float", "default": 3.4, "min": 0.5, "max": 4.0, "step": 0.05,
      "label": { "zh": "喷射粒子密度", "en": "Ejection Density" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uSourceExcavation": {
      "type": "float", "default": 1.7, "min": 0.8, "max": 2.4, "step": 0.05,
      "label": { "zh": "源区掀开范围", "en": "Source Excavation" },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uRibbonLength": {
      "type": "float", "default": 0.26, "min": 0.045, "max": 0.36, "step": 0.005,
      "label": { "zh": "喷射条长度", "en": "Ribbon Length" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uRibbonWidth": {
      "type": "float", "default": 0.038, "min": 0.006, "max": 0.07, "step": 0.001,
      "label": { "zh": "喷射条宽度", "en": "Ribbon Width" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uArcHeight": {
      "type": "float", "default": 0.36, "min": 0.12, "max": 1.3, "step": 0.01,
      "label": { "zh": "日珥高度", "en": "Arc Height" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uArcLength": {
      "type": "float", "default": 0.66, "min": 0.05, "max": 0.95, "step": 0.01,
      "label": { "zh": "弧向展开", "en": "Arc Span" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uShapeRandomness": {
      "type": "float", "default": 0.68, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "形状随机度", "en": "Shape Randomness" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uShellCoverage": {
      "type": "float", "default": 0.70, "min": 0.25, "max": 0.95, "step": 0.01,
      "label": { "zh": "球面覆盖率", "en": "Shell Coverage" },
      "description": { "zh": "更高覆盖率让缩小后的主体保持接近参考图的明亮块面，同时仍保留明显孔洞。", "en": "Higher coverage keeps the reduced body bright and sheet-like while preserving large perforations." },
      "group": { "zh": "球面形态", "en": "Shell Pattern" }
    },
    "uShellPatternScale": {
      "type": "float", "default": 0.95, "min": 0.45, "max": 2.5, "step": 0.05,
      "label": { "zh": "大陆纹理尺度", "en": "Continent Scale" },
      "group": { "zh": "球面形态", "en": "Shell Pattern" }
    },
    "uFlightDuration": {
      "type": "float", "default": 2.1, "min": 0.55, "max": 3.5, "step": 0.05,
      "label": { "zh": "飞行时长", "en": "Flight Duration" },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uRotationSpeed": {
      "type": "float", "default": 1.35, "min": 0.0, "max": 3.0, "step": 0.05,
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
      "type": "float", "default": 0.07, "min": 0.0, "max": 0.4, "step": 0.005,
      "label": { "zh": "球面波浪强度", "en": "Surface Wave Strength" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveRange": {
      "type": "float", "default": 1.5, "min": 0.25, "max": 2.0, "step": 0.025,
      "label": { "zh": "球面波传播范围", "en": "Wave Range" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveSpeed": {
      "type": "float", "default": 0.72, "min": 0.25, "max": 4.0, "step": 0.05,
      "label": { "zh": "球面波速度", "en": "Wave Speed" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveDamping": {
      "type": "float", "default": 0.40, "min": 0.05, "max": 2.5, "step": 0.025,
      "label": { "zh": "球面波衰减", "en": "Wave Damping" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uParticleSize": {
      "type": "float", "default": 0.76, "min": 0.35, "max": 2.2, "step": 0.05,
      "label": { "zh": "粒子尺寸", "en": "Particle Size" },
      "group": { "zh": "外观", "en": "Appearance" }
    },
    "uShellColor": {
      "type": "color", "default": "#ffffff",
      "label": { "zh": "球面粒子颜色", "en": "Shell Color" },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uShellBrightness": {
      "type": "float", "default": 3.20, "min": 0.2, "max": 5.0, "step": 0.05,
      "label": { "zh": "球面亮度", "en": "Shell Brightness" },
      "description": { "zh": "缩小主体后显著提高白色粒子的发光强度，使主体重新成为画面视觉中心。", "en": "Strongly boosts the white grains after shrinking the body so it remains the visual focus." },
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
      "type": "float", "default": 3.25, "min": 0.2, "max": 5.0, "step": 0.05,
      "label": { "zh": "日珥亮度", "en": "Prominence Brightness" },
      "group": { "zh": "色散", "en": "Dispersion" }
    },
    "uDispersionSeparation": {
      "type": "float", "default": 1.85, "min": 0.0, "max": 3.0, "step": 0.05,
      "label": { "zh": "粒子色散空间分离", "en": "Particle Spectrum Separation" },
      "description": { "zh": "在三维轨迹中实际拉开不同波长粒子的位置。", "en": "Physically separates different spectral bands in the 3D prominence trajectory." },
      "group": { "zh": "色散", "en": "Dispersion" }
    },
    "uChromaticAberration": {
      "type": "float", "default": 8.5, "min": 0.0, "max": 20.0, "step": 0.5,
      "label": { "zh": "后期色散强度", "en": "Post Chromatic Split" },
      "description": { "zh": "屏幕空间额外分离红绿蓝通道，专门用于复现参考图中非常强的棱镜色边。单位近似为像素。", "en": "Adds an extra screen-space RGB channel split to reproduce the reference's strong prism fringes." },
      "group": { "zh": "后期色散", "en": "Post Dispersion" }
    },
    "uChromaticThreshold": {
      "type": "float", "default": 0.08, "min": 0.0, "max": 0.8, "step": 0.01,
      "label": { "zh": "色散亮度阈值", "en": "Dispersion Luma Threshold" },
      "description": { "zh": "降低会让更多白色轮廓和喷发边缘参与后期色散。", "en": "Lower values allow more bright shell and prominence edges to receive the post split." },
      "group": { "zh": "后期色散", "en": "Post Dispersion" }
    },
    "uChromaticGlow": {
      "type": "float", "default": 0.85, "min": 0.0, "max": 2.0, "step": 0.05,
      "label": { "zh": "色散光晕", "en": "Dispersion Glow" },
      "description": { "zh": "加强红蓝分离边缘的辉光强度。", "en": "Boosts the luminous red/blue fringe around split highlights." },
      "group": { "zh": "后期色散", "en": "Post Dispersion" }
    },
    "uOrbitLineColor": {
      "type": "color", "default": "#ffffff",
      "label": { "zh": "轨道线颜色", "en": "Orbit Line Color" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitLineBrightness": {
      "type": "float", "default": 0.78, "min": 0.2, "max": 4.0, "step": 0.05,
      "label": { "zh": "轨道线亮度", "en": "Orbit Brightness" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitLineOpacity": {
      "type": "float", "default": 0.28, "min": 0.05, "max": 1.0, "step": 0.01,
      "label": { "zh": "轨道线透明度", "en": "Orbit Opacity" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitThickness": {
      "type": "float", "default": 0.0014, "min": 0.0006, "max": 0.02, "step": 0.0001,
      "label": { "zh": "轨道线粗细", "en": "Orbit Thickness" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitRadius": {
      "type": "float", "default": 1.78, "min": 1.25, "max": 3.2, "step": 0.05,
      "label": { "zh": "轨道半径", "en": "Orbit Radius" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitRotationSpeed": {
      "type": "float", "default": 0.55, "min": 0.0, "max": 3.0, "step": 0.05,
      "label": { "zh": "轨道旋转速度", "en": "Orbit Rotation" },
      "description": { "zh": "轨道现在会叠加多个低频非同步律动，不再像匀速刚体旋转。", "en": "The orbit now combines several slow asynchronous motions instead of rigid constant-speed rotation." },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitPulse": {
      "type": "float", "default": 0.026, "min": 0.0, "max": 0.18, "step": 0.002,
      "label": { "zh": "轨道不规则律动", "en": "Orbit Irregular Pulse" },
      "description": { "zh": "控制轨道沿不同位置缓慢、不完全同步的呼吸形变。", "en": "Controls slow asynchronous breathing deformation along different parts of the orbit." },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitPullStrength": {
      "type": "float", "default": 0.78, "min": 0.0, "max": 1.2, "step": 0.02,
      "label": { "zh": "轨道牵引强度", "en": "Orbit Pull Strength" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitInfluenceWidth": {
      "type": "float", "default": 0.08, "min": 0.025, "max": 0.28, "step": 0.005,
      "label": { "zh": "轨道牵引范围", "en": "Tether Width" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitHighlightStrength": {
      "type": "float", "default": 1.25, "min": 0.0, "max": 4.0, "step": 0.05,
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