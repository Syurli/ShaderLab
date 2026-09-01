precision highp float;

in vec2 vUv;
in vec3 vColor;
in float vAlpha;
in float vSpark;
in float vFlare;
flat in float vSeed;
out vec4 outColor;

void main() {
  float r = length(vUv);

  if (vFlare > 0.5) {
    float soft = 1.0 - smoothstep(0.12, 1.0, r);
    float core = 1.0 - smoothstep(0.0, 0.22, r);
    float ring = exp(-pow((r - 0.52) * 6.5, 2.0));
    float halo = 1.0 - smoothstep(0.30, 1.05, r);
    float anisotropy = 0.82 + 0.18 * sin(vUv.x * 6.0 + vUv.y * 4.0 + vSeed * 17.0);
    float energy = core * 1.45 + soft * 0.72 + ring * 0.30 + halo * 0.20;
    vec3 color = vColor * energy * anisotropy + vec3(1.0) * core * 0.32 * vSpark;
    float alpha = vAlpha * (soft * 0.50 + ring * 0.18 + core * 0.34);
    if (alpha < 0.003) discard;
    outColor = vec4(color, alpha);
    return;
  }

  float n1 = sin(vUv.x * 29.0 + vUv.y * 43.0 + vSeed * 91.7);
  float n2 = sin(vUv.x * 67.0 - vUv.y * 31.0 + vSeed * 37.3);
  float grain = clamp(0.5 + 0.25 * n1 + 0.14 * n2, 0.0, 1.0);
  float mask = 1.0 - smoothstep(0.58, 1.0, r + (grain - 0.5) * 0.075);
  if (mask < 0.01) discard;

  float core = 1.0 - smoothstep(0.0, 0.62, r);
  float sparkle = vSpark * pow(max(core, 0.0), 5.0) * 1.55;
  vec3 color = vColor * (0.94 + 0.52 * core) + vec3(sparkle);
  outColor = vec4(color, mask * vAlpha * (0.86 + 0.14 * grain));
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uParticleCount": {
      "type": "int", "default": 30000, "min": 8000, "max": 160000, "step": 2000,
      "label": { "zh": "球面粒子数量", "en": "Shell Particle Count" },
      "description": { "zh": "白色球面主体的粒子数量；大色散光斑使用独立实例数量，不占用这里的粒子。", "en": "White shell particle count. Large chromatic flare sprites use a separate instance budget." },
      "group": { "zh": "性能", "en": "Performance" }
    },
    "uFlareCount": {
      "type": "int", "default": 900, "min": 0, "max": 6000, "step": 100,
      "label": { "zh": "大色散光斑数量", "en": "Chromatic Flare Count" },
      "description": { "zh": "额外生成在空中等离子日珥里的大尺寸色散光斑实例。", "en": "Extra large chromatic flare sprites spawned directly inside airborne plasma prominences." },
      "group": { "zh": "性能", "en": "Performance" }
    },
    "uEruptionRate": {
      "type": "float", "default": 1.75, "min": 0.3, "max": 4.5, "step": 0.05,
      "label": { "zh": "轨道切割频率", "en": "Orbit Cut Rate" },
      "description": { "zh": "不再由球心产生喷发；该值控制轨道线活跃切割段出现的频率。", "en": "No center-driven eruption: this controls how often active cutting segments appear on the orbit." },
      "group": { "zh": "轨道切割", "en": "Orbit Cutting" }
    },
    "uEruptionChance": {
      "type": "float", "default": 0.88, "min": 0.2, "max": 1.0, "step": 0.01,
      "label": { "zh": "切割发生概率", "en": "Cut Chance" },
      "group": { "zh": "轨道切割", "en": "Orbit Cutting" }
    },
    "uRibbonLength": {
      "type": "float", "default": 0.28, "min": 0.06, "max": 0.55, "step": 0.005,
      "label": { "zh": "切割线段长度", "en": "Cut Segment Length" },
      "description": { "zh": "轨道线贴近球面时真正参与切割的局部线段长度。", "en": "Length of the local orbit segment that physically cuts the shell." },
      "group": { "zh": "轨道切割", "en": "Orbit Cutting" }
    },
    "uRibbonWidth": {
      "type": "float", "default": 0.032, "min": 0.004, "max": 0.10, "step": 0.001,
      "label": { "zh": "切口宽度", "en": "Cut Width" },
      "group": { "zh": "轨道切割", "en": "Orbit Cutting" }
    },
    "uSourceExcavation": {
      "type": "float", "default": 1.55, "min": 0.6, "max": 2.8, "step": 0.05,
      "label": { "zh": "切口剥离范围", "en": "Cut Excavation" },
      "description": { "zh": "扩大轨道切口周围被直接剥离并卷入等离子尾迹的球面区域。", "en": "Expands the shell area stripped directly by the cutter and carried into the plasma wake." },
      "group": { "zh": "轨道切割", "en": "Orbit Cutting" }
    },
    "uEjectionDensity": {
      "type": "float", "default": 3.8, "min": 0.5, "max": 4.0, "step": 0.05,
      "label": { "zh": "切割剥离密度", "en": "Stripped Particle Density" },
      "description": { "zh": "决定切口区域有多少原本属于球面的粒子真正被轨道线带走。", "en": "Controls how many original shell particles in the cut are actually stripped into the wake." },
      "group": { "zh": "轨道切割", "en": "Orbit Cutting" }
    },
    "uFlightDuration": {
      "type": "float", "default": 2.25, "min": 0.6, "max": 4.0, "step": 0.05,
      "label": { "zh": "等离子尾迹寿命", "en": "Plasma Wake Lifetime" },
      "group": { "zh": "等离子尾迹", "en": "Plasma Wake" }
    },
    "uArcHeight": {
      "type": "float", "default": 0.48, "min": 0.05, "max": 1.4, "step": 0.01,
      "label": { "zh": "火焰抬升高度", "en": "Plasma Lift" },
      "group": { "zh": "等离子尾迹", "en": "Plasma Wake" }
    },
    "uArcLength": {
      "type": "float", "default": 0.78, "min": 0.05, "max": 1.5, "step": 0.01,
      "label": { "zh": "沿轨道拖尾长度", "en": "Tangential Wake Length" },
      "description": { "zh": "被切走的粒子主要沿轨道线切线方向形成火焰/日珥式拖尾。", "en": "Stripped particles primarily form a flame/prominence wake along the orbit tangent." },
      "group": { "zh": "等离子尾迹", "en": "Plasma Wake" }
    },
    "uShapeRandomness": {
      "type": "float", "default": 0.82, "min": 0.0, "max": 1.5, "step": 0.02,
      "label": { "zh": "等离子湍动", "en": "Plasma Turbulence" },
      "group": { "zh": "等离子尾迹", "en": "Plasma Wake" }
    },
    "uProminenceSaturation": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "等离子色散饱和度", "en": "Plasma Spectrum Saturation" },
      "group": { "zh": "色散", "en": "Dispersion" }
    },
    "uProminenceBrightness": {
      "type": "float", "default": 3.1, "min": 0.2, "max": 6.0, "step": 0.05,
      "label": { "zh": "等离子亮度", "en": "Plasma Brightness" },
      "group": { "zh": "色散", "en": "Dispersion" }
    },
    "uDispersionSeparation": {
      "type": "float", "default": 1.25, "min": 0.0, "max": 3.5, "step": 0.05,
      "label": { "zh": "等离子光谱空间分离", "en": "Plasma Spectrum Separation" },
      "group": { "zh": "色散", "en": "Dispersion" }
    },
    "uFlareSize": {
      "type": "float", "default": 1.0, "min": 0.15, "max": 3.0, "step": 0.05,
      "label": { "zh": "大色散光斑尺寸", "en": "Chromatic Flare Size" },
      "group": { "zh": "大色散光斑", "en": "Chromatic Flares" }
    },
    "uFlareBrightness": {
      "type": "float", "default": 3.8, "min": 0.2, "max": 8.0, "step": 0.05,
      "label": { "zh": "大色散光斑亮度", "en": "Chromatic Flare Brightness" },
      "group": { "zh": "大色散光斑", "en": "Chromatic Flares" }
    },
    "uFlareSpread": {
      "type": "float", "default": 0.22, "min": 0.0, "max": 0.8, "step": 0.01,
      "label": { "zh": "大色散光斑散布", "en": "Chromatic Flare Spread" },
      "group": { "zh": "大色散光斑", "en": "Chromatic Flares" }
    },
    "uSurfaceWave": {
      "type": "float", "default": 0.055, "min": 0.0, "max": 0.30, "step": 0.005,
      "label": { "zh": "切割波纹强度", "en": "Cut Ripple Strength" },
      "description": { "zh": "波纹从轨道切割线段横向传播，而不是从球心或单个喷发点扩散。", "en": "Ripples propagate laterally from the cutting segment, not from the sphere center or a radial source." },
      "group": { "zh": "切割波纹", "en": "Cut Ripples" }
    },
    "uWaveRange": {
      "type": "float", "default": 0.82, "min": 0.15, "max": 2.0, "step": 0.02,
      "label": { "zh": "切割波纹范围", "en": "Cut Ripple Range" },
      "group": { "zh": "切割波纹", "en": "Cut Ripples" }
    },
    "uWaveSpeed": {
      "type": "float", "default": 1.05, "min": 0.1, "max": 4.0, "step": 0.05,
      "label": { "zh": "切割波纹速度", "en": "Cut Ripple Speed" },
      "group": { "zh": "切割波纹", "en": "Cut Ripples" }
    },
    "uWaveDamping": {
      "type": "float", "default": 0.58, "min": 0.05, "max": 3.0, "step": 0.02,
      "label": { "zh": "切割波纹衰减", "en": "Cut Ripple Damping" },
      "group": { "zh": "切割波纹", "en": "Cut Ripples" }
    },
    "uShellCoverage": {
      "type": "float", "default": 0.72, "min": 0.25, "max": 0.98, "step": 0.01,
      "label": { "zh": "球面覆盖率", "en": "Shell Coverage" },
      "group": { "zh": "球面", "en": "Shell" }
    },
    "uShellPatternScale": {
      "type": "float", "default": 0.92, "min": 0.4, "max": 2.5, "step": 0.04,
      "label": { "zh": "球面镂空尺度", "en": "Shell Void Scale" },
      "group": { "zh": "球面", "en": "Shell" }
    },
    "uRotationSpeed": {
      "type": "float", "default": 1.2, "min": 0.0, "max": 3.0, "step": 0.05,
      "label": { "zh": "球面旋转速度", "en": "Shell Rotation" },
      "group": { "zh": "球面", "en": "Shell" }
    },
    "uParticleSize": {
      "type": "float", "default": 0.72, "min": 0.25, "max": 2.2, "step": 0.04,
      "label": { "zh": "球面粒子尺寸", "en": "Shell Particle Size" },
      "group": { "zh": "球面", "en": "Shell" }
    },
    "uShellColor": {
      "type": "color", "default": "#ffffff",
      "label": { "zh": "球面颜色", "en": "Shell Color" },
      "group": { "zh": "球面", "en": "Shell" }
    },
    "uShellBrightness": {
      "type": "float", "default": 3.35, "min": 0.2, "max": 6.0, "step": 0.05,
      "label": { "zh": "球面亮度", "en": "Shell Brightness" },
      "group": { "zh": "球面", "en": "Shell" }
    },
    "uOrbitLineColor": {
      "type": "color", "default": "#ffffff",
      "label": { "zh": "切割轨道颜色", "en": "Cutter Line Color" },
      "group": { "zh": "切割轨道", "en": "Cutter Orbit" }
    },
    "uOrbitLineBrightness": {
      "type": "float", "default": 0.75, "min": 0.1, "max": 4.0, "step": 0.05,
      "label": { "zh": "切割轨道亮度", "en": "Cutter Brightness" },
      "group": { "zh": "切割轨道", "en": "Cutter Orbit" }
    },
    "uOrbitLineOpacity": {
      "type": "float", "default": 0.30, "min": 0.03, "max": 1.0, "step": 0.01,
      "label": { "zh": "切割轨道透明度", "en": "Cutter Opacity" },
      "group": { "zh": "切割轨道", "en": "Cutter Orbit" }
    },
    "uOrbitThickness": {
      "type": "float", "default": 0.0011, "min": 0.0004, "max": 0.02, "step": 0.0001,
      "label": { "zh": "切割轨道粗细", "en": "Cutter Thickness" },
      "group": { "zh": "切割轨道", "en": "Cutter Orbit" }
    },
    "uOrbitRadius": {
      "type": "float", "default": 1.68, "min": 1.20, "max": 3.0, "step": 0.03,
      "label": { "zh": "切割轨道半径", "en": "Cutter Radius" },
      "group": { "zh": "切割轨道", "en": "Cutter Orbit" }
    },
    "uOrbitRotationSpeed": {
      "type": "float", "default": 0.62, "min": 0.0, "max": 3.0, "step": 0.03,
      "label": { "zh": "切割轨道运动速度", "en": "Cutter Motion Speed" },
      "group": { "zh": "切割轨道", "en": "Cutter Orbit" }
    },
    "uOrbitPulse": {
      "type": "float", "default": 0.034, "min": 0.0, "max": 0.20, "step": 0.002,
      "label": { "zh": "切割轨道不规则律动", "en": "Cutter Irregular Motion" },
      "group": { "zh": "切割轨道", "en": "Cutter Orbit" }
    },
    "uOrbitPullStrength": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 1.2, "step": 0.02,
      "label": { "zh": "切割贴合强度", "en": "Cut Contact Strength" },
      "description": { "zh": "活跃轨道段向球面贴合并执行切割的强度。", "en": "How strongly an active orbit segment bends toward the shell to perform the cut." },
      "group": { "zh": "切割轨道", "en": "Cutter Orbit" }
    },
    "uOrbitInfluenceWidth": {
      "type": "float", "default": 0.085, "min": 0.02, "max": 0.30, "step": 0.005,
      "label": { "zh": "活跃切割段范围", "en": "Active Cutter Span" },
      "group": { "zh": "切割轨道", "en": "Cutter Orbit" }
    },
    "uOrbitHighlightStrength": {
      "type": "float", "default": 2.0, "min": 0.0, "max": 5.0, "step": 0.05,
      "label": { "zh": "切割段高亮", "en": "Cut Segment Highlight" },
      "group": { "zh": "切割轨道", "en": "Cutter Orbit" }
    },
    "uCameraDistance": {
      "type": "float", "default": 5.65, "min": 3.0, "max": 10.0, "step": 0.05,
      "label": { "zh": "相机距离", "en": "Camera Distance" },
      "group": { "zh": "观察", "en": "View" }
    }
  }
}
@endshaderlab */
