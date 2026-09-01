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
  float sparkle = vSpark * pow(max(core, 0.0), 5.0) * 1.45;
  vec3 color = vColor * (0.86 + 0.46 * core) + vec3(sparkle);
  outColor = vec4(color, mask * vAlpha * (0.84 + 0.16 * grain));
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uParticleCount": {
      "type": "int", "default": 26000, "min": 6000, "max": 200000, "step": 2000,
      "label": { "zh": "粒子数量", "en": "Particle Count" },
      "description": { "zh": "目标风格使用更多、更小的粒子组成连续白色颗粒壳。", "en": "The target preset uses more, smaller grains to build a denser white shell." },
      "group": { "zh": "性能", "en": "Performance" }
    },
    "uEruptionRate": {
      "type": "float", "default": 2.1, "min": 0.25, "max": 4.5, "step": 0.05,
      "label": { "zh": "喷射频率", "en": "Eruption Rate" },
      "description": { "zh": "默认降低同时喷发数量，避免主体外围变成散乱粒子云。", "en": "The default lowers overlapping eruptions so the silhouette stays coherent." },
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
      "type": "float", "default": 3.2, "min": 0.5, "max": 4.0, "step": 0.05,
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
      "type": "float", "default": 0.036, "min": 0.006, "max": 0.07, "step": 0.001,
      "label": { "zh": "喷射条宽度", "en": "Ribbon Width" },
      "description": { "zh": "默认收窄喷发条带，使色散边缘更接近参考图中的撕裂光边。", "en": "The default narrows the ejected ribbon so its spectral edges read like torn light fringes." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uArcHeight": {
      "type": "float", "default": 0.34, "min": 0.12, "max": 1.3, "step": 0.01,
      "label": { "zh": "日珥高度", "en": "Arc Height" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uArcLength": {
      "type": "float", "default": 0.62, "min": 0.05, "max": 0.95, "step": 0.01,
      "label": { "zh": "弧向展开", "en": "Arc Span" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uShapeRandomness": {
      "type": "float", "default": 0.62, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "形状随机度", "en": "Shape Randomness" },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uShellCoverage": {
      "type": "float", "default": 0.58, "min": 0.25, "max": 0.95, "step": 0.01,
      "label": { "zh": "球面覆盖率", "en": "Shell Coverage" },
      "description": { "zh": "提高默认覆盖率，让主体先读成一颗有缺口的连续颗粒球，而不是稀疏点云。", "en": "Higher default coverage makes the body read as a coherent perforated grain shell rather than a sparse point cloud." },
      "group": { "zh": "球面形态", "en": "Shell Pattern" }
    },
    "uShellPatternScale": {
      "type": "float", "default": 1.15, "min": 0.45, "max": 2.5, "step": 0.05,
      "label": { "zh": "大陆纹理尺度", "en": "Continent Scale" },
      "description": { "zh": "降低默认尺度，形成更大的连续白色块面与洞口。", "en": "Lower default scale produces larger connected white regions and holes." },
      "group": { "zh": "球面形态", "en": "Shell Pattern" }
    },
    "uFlightDuration": {
      "type": "float", "default": 2.1, "min": 0.55, "max": 3.5, "step": 0.05,
      "label": { "zh": "飞行时长", "en": "Flight Duration" },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uRotationSpeed": {
      "type": "float", "default": 1.5, "min": 0.0, "max": 3.0, "step": 0.05,
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
      "type": "float", "default": 0.06, "min": 0.0, "max": 0.4, "step": 0.005,
      "label": { "zh": "球面波浪强度", "en": "Surface Wave Strength" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveRange": {
      "type": "float", "default": 1.5, "min": 0.25, "max": 2.0, "step": 0.025,
      "label": { "zh": "球面波传播范围", "en": "Wave Range" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveSpeed": {
      "type": "float", "default": 0.75, "min": 0.25, "max": 4.0, "step": 0.05,
      "label": { "zh": "球面波速度", "en": "Wave Speed" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveDamping": {
      "type": "float", "default": 0.42, "min": 0.05, "max": 2.5, "step": 0.025,
      "label": { "zh": "球面波衰减", "en": "Wave Damping" },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uParticleSize": {
      "type": "float", "default": 0.72, "min": 0.35, "max": 2.2, "step": 0.05,
      "label": { "zh": "粒子尺寸", "en": "Particle Size" },
      "description": { "zh": "默认显著缩小粒子，让白色壳层接近参考图的细砂颗粒。", "en": "The default is substantially smaller so the shell reads as fine grain like the reference." },
      "group": { "zh": "外观", "en": "Appearance" }
    },
    "uShellColor": {
      "type": "color", "default": "#ffffff",
      "label": { "zh": "球面粒子颜色", "en": "Shell Color" },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uShellBrightness": {
      "type": "float", "default": 1.9, "min": 0.2, "max": 4.0, "step": 0.05,
      "label": { "zh": "球面亮度", "en": "Shell Brightness" },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uProminenceHueOffset": {
      "type": "float", "default": 0.0, "min": -0.5, "max": 0.5, "step": 0.01,
      "label": { "zh": "色散起点偏移", "en": "Dispersion Offset" },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uProminenceHueSpan": {
      "type": "float", "default": 1.0, "min": 0.15, "max": 1.5, "step": 0.02,
      "label": { "zh": "色散展开", "en": "Dispersion Spread" },
      "description": { "zh": "控制喷发条带横向从红橙到蓝紫的光谱跨度。", "en": "Controls the transverse spectrum span from warm red/orange to blue/violet." },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uProminenceSaturation": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "日珥色散饱和度", "en": "Dispersion Saturation" },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uProminenceBrightness": {
      "type": "float", "default": 2.6, "min": 0.2, "max": 4.0, "step": 0.05,
      "label": { "zh": "日珥亮度", "en": "Prominence Brightness" },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uDispersionSeparation": {
      "type": "float", "default": 1.25, "min": 0.0, "max": 2.5, "step": 0.05,
      "label": { "zh": "色散空间分离", "en": "Spatial Dispersion" },
      "description": { "zh": "真正把不同光谱位置的喷发粒子横向分开，而不只是修改颜色。提高后红/黄/青/蓝/紫边缘会更明显。", "en": "Physically separates prominence particles sideways by spectral coordinate instead of only recoloring them." },
      "group": { "zh": "颜色", "en": "Color" }
    },
    "uOrbitLineColor": {
      "type": "color", "default": "#ffffff",
      "label": { "zh": "轨道线颜色", "en": "Orbit Line Color" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitLineBrightness": {
      "type": "float", "default": 0.95, "min": 0.2, "max": 4.0, "step": 0.05,
      "label": { "zh": "轨道线亮度", "en": "Orbit Brightness" },
      "description": { "zh": "目标参考中轨道是低亮度灰白光丝，不抢主体。", "en": "The target reference uses subdued gray-white orbit filaments that do not overpower the body." },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitLineOpacity": {
      "type": "float", "default": 0.34, "min": 0.05, "max": 1.0, "step": 0.01,
      "label": { "zh": "轨道线透明度", "en": "Orbit Opacity" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitThickness": {
      "type": "float", "default": 0.0018, "min": 0.0007, "max": 0.02, "step": 0.0001,
      "label": { "zh": "轨道线粗细", "en": "Orbit Thickness" },
      "description": { "zh": "默认约为此前版本的一半，目标是接近 1px 左右的细光丝。", "en": "About half the previous default, targeting a roughly one-pixel luminous filament." },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitRadius": {
      "type": "float", "default": 2.18, "min": 1.75, "max": 3.2, "step": 0.05,
      "label": { "zh": "轨道半径", "en": "Orbit Radius" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitRotationSpeed": {
      "type": "float", "default": 0.65, "min": 0.0, "max": 3.0, "step": 0.05,
      "label": { "zh": "轨道旋转速度", "en": "Orbit Rotation" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitPulse": {
      "type": "float", "default": 0.012, "min": 0.0, "max": 0.18, "step": 0.002,
      "label": { "zh": "轨道律动幅度", "en": "Orbit Pulse" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitPullStrength": {
      "type": "float", "default": 0.72, "min": 0.0, "max": 1.2, "step": 0.02,
      "label": { "zh": "轨道牵引强度", "en": "Orbit Pull Strength" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitInfluenceWidth": {
      "type": "float", "default": 0.08, "min": 0.025, "max": 0.28, "step": 0.005,
      "label": { "zh": "轨道牵引范围", "en": "Tether Width" },
      "group": { "zh": "牵引轨道", "en": "Tether Orbit" }
    },
    "uOrbitHighlightStrength": {
      "type": "float", "default": 1.2, "min": 0.0, "max": 4.0, "step": 0.05,
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