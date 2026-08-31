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
  float mask = 1.0 - smoothstep(0.48, 1.0, r + (grain - 0.5) * 0.11);
  if (mask < 0.01) discard;

  float core = 1.0 - smoothstep(0.0, 0.72, r);
  float sparkle = vSpark * pow(max(core, 0.0), 5.0) * 1.9;
  vec3 color = vColor * (0.70 + 0.58 * core) + vec3(sparkle);
  outColor = vec4(color, mask * vAlpha * (0.76 + 0.24 * grain));
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uParticleCount": {
      "type": "int",
      "default": 48000,
      "min": 6000,
      "max": 200000,
      "step": 2000,
      "label": { "zh": "粒子数量", "en": "Particle Count" },
      "description": { "zh": "球面粒子总数。提高会直接增加细条日珥中的可用粒子数量；高端桌面可尝试 10~20 万，移动端会由后端做安全上限。", "en": "Total shell particle count. Higher values directly provide more particles for the thin prominences. High-end desktops can try 100k-200k; mobile is safety-capped by the backend." },
      "group": { "zh": "性能", "en": "Performance" }
    },
    "uEruptionRate": {
      "type": "float",
      "default": 1.85,
      "min": 0.25,
      "max": 4.5,
      "step": 0.05,
      "label": { "zh": "喷射频率", "en": "Eruption Rate" },
      "description": { "zh": "提高后更频繁地产生新喷发。事件会保留历史并平滑衰减，因此高频下也不会因时间槽切换而突然闪回球面。", "en": "Creates new eruptions more frequently. Historical events remain alive and fade smoothly, preventing slot-boundary snapping at high rates." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uEruptionChance": {
      "type": "float",
      "default": 0.9,
      "min": 0.2,
      "max": 1.0,
      "step": 0.01,
      "label": { "zh": "喷发概率", "en": "Eruption Chance" },
      "description": { "zh": "每个时间槽真正发生喷发的概率。降低可产生更明显的随机空档。", "en": "Probability that a time slot actually produces an eruption. Lower values create more obvious random gaps." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uInfluenceRadius": {
      "type": "float",
      "default": 0.4,
      "min": 0.12,
      "max": 0.9,
      "step": 0.01,
      "label": { "zh": "局部波及范围", "en": "Local Influence Radius" },
      "description": { "zh": "喷发源附近首先被扰动的区域。全局水波传播范围由“球面波传播范围”单独控制。", "en": "Initial disturbed area around an eruption source. Global water-like propagation is controlled separately by Wave Range." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uRibbonLength": {
      "type": "float",
      "default": 0.16,
      "min": 0.045,
      "max": 0.36,
      "step": 0.005,
      "label": { "zh": "喷射条长度", "en": "Ribbon Source Length" },
      "description": { "zh": "球面上真正参与喷射的细长源区长度。", "en": "Length of the narrow source strip on the sphere that actually joins the eruption." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uRibbonWidth": {
      "type": "float",
      "default": 0.022,
      "min": 0.006,
      "max": 0.07,
      "step": 0.001,
      "label": { "zh": "喷射条宽度", "en": "Ribbon Width" },
      "description": { "zh": "决定喷发束厚度。数值越小，从侧面越接近细丝而不是一个面。", "en": "Controls filament thickness. Smaller values keep the prominence line-like instead of sheet-like from the side." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uEjectionDensity": {
      "type": "float",
      "default": 2.0,
      "min": 0.5,
      "max": 4.0,
      "step": 0.05,
      "label": { "zh": "喷射粒子密度", "en": "Ejection Density" },
      "description": { "zh": "独立控制细条内部有多少球面粒子参与喷发，不会像增加宽度那样把日珥变成薄面。", "en": "Controls how many shell particles join each thin ribbon without widening it into a sheet." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uArcHeight": {
      "type": "float",
      "default": 0.68,
      "min": 0.12,
      "max": 1.3,
      "step": 0.01,
      "label": { "zh": "日珥高度", "en": "Arc Height" },
      "description": { "zh": "日珥离开球面的最大高度。", "en": "Maximum radial height of the prominence above the shell." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uArcLength": {
      "type": "float",
      "default": 0.46,
      "min": 0.05,
      "max": 0.95,
      "step": 0.01,
      "label": { "zh": "弧向展开", "en": "Arc Span" },
      "description": { "zh": "沿球面切线方向的弧形展开距离。提高会让日珥弯曲得更明显。", "en": "Tangential span of the arc. Higher values produce a more pronounced prominence arch." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uShapeRandomness": {
      "type": "float",
      "default": 0.62,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "label": { "zh": "形状随机度", "en": "Shape Randomness" },
      "description": { "zh": "控制细条弯曲、发射时差和不同喷发事件之间的形态差异。", "en": "Controls centerline bending, launch staggering, and shape variation between eruption events." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uFlightDuration": {
      "type": "float",
      "default": 1.5,
      "min": 0.55,
      "max": 3.5,
      "step": 0.05,
      "label": { "zh": "飞行时长", "en": "Flight Duration" },
      "description": { "zh": "粒子完成一次抛出并连续回到球面的时间。", "en": "Time for a particle to leave the shell and continuously return to it." },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uReturnDamping": {
      "type": "float",
      "default": 1.25,
      "min": 0.3,
      "max": 6.0,
      "step": 0.05,
      "label": { "zh": "回落阻尼", "en": "Return Damping" },
      "description": { "zh": "粒子落回球面后的阻尼。默认比旧版更低，让回落后的波动持续更久并逐渐平静。", "en": "Damping after landing. The lower default preserves a longer physical settling tail before the shell calms." },
      "group": { "zh": "回落", "en": "Return" }
    },
    "uReturnFrequency": {
      "type": "float",
      "default": 1.15,
      "min": 0.3,
      "max": 4.0,
      "step": 0.05,
      "label": { "zh": "回落振动频率", "en": "Return Oscillation" },
      "description": { "zh": "落回后的阻尼振动频率。", "en": "Frequency of the damped oscillation after particles land." },
      "group": { "zh": "回落", "en": "Return" }
    },
    "uSurfaceWave": {
      "type": "float",
      "default": 0.13,
      "min": 0.0,
      "max": 0.4,
      "step": 0.005,
      "label": { "zh": "球面波浪强度", "en": "Surface Wave Strength" },
      "description": { "zh": "控制喷发、落地和全球传播波浪的总体位移幅度。多组波会互相叠加形成类似水面的干涉。", "en": "Overall displacement amplitude for eruption, landing, and global travelling waves. Multiple waves interfere like a water surface." },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveRange": {
      "type": "float",
      "default": 1.75,
      "min": 0.25,
      "max": 2.0,
      "step": 0.025,
      "label": { "zh": "球面波传播范围", "en": "Wave Range" },
      "description": { "zh": "控制水波从喷发点沿球面传播多远。2.0 接近传播到球体对侧。", "en": "How far eruption waves travel across the sphere. 2.0 reaches approximately to the opposite side." },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveSpeed": {
      "type": "float",
      "default": 1.45,
      "min": 0.25,
      "max": 4.0,
      "step": 0.05,
      "label": { "zh": "球面波速度", "en": "Wave Speed" },
      "description": { "zh": "波峰沿球面从喷发点向外传播的速度。", "en": "Speed at which wave fronts propagate away from eruption sources." },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveDamping": {
      "type": "float",
      "default": 0.42,
      "min": 0.05,
      "max": 2.5,
      "step": 0.025,
      "label": { "zh": "球面波衰减", "en": "Wave Damping" },
      "description": { "zh": "全局球面波随时间衰减的速度。越低越容易形成持续的水面波浪感。", "en": "Temporal damping of global surface waves. Lower values create a longer-lived water-surface feel." },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uParticleSize": {
      "type": "float",
      "default": 0.95,
      "min": 0.4,
      "max": 2.2,
      "step": 0.05,
      "label": { "zh": "粒子尺寸", "en": "Particle Size" },
      "description": { "zh": "纯白球面沙砾与彩虹喷射粒子的视觉尺寸。", "en": "Visual size of the white shell grains and rainbow ejected particles." },
      "group": { "zh": "外观", "en": "Appearance" }
    },
    "uRotationSpeed": {
      "type": "float",
      "default": 1.0,
      "min": 0.0,
      "max": 3.0,
      "step": 0.05,
      "label": { "zh": "球面旋转速度", "en": "Shell Rotation" },
      "description": { "zh": "基础球面粒子的缓慢差速旋转速度。", "en": "Speed multiplier for the shell's slow differential rotation." },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uCameraDistance": {
      "type": "float",
      "default": 6.15,
      "min": 3.3,
      "max": 10.0,
      "step": 0.05,
      "label": { "zh": "相机距离", "en": "Camera Distance" },
      "description": { "zh": "查看球体的距离。画布中拖动可旋转观察。", "en": "Viewing distance. Drag the canvas to orbit around the shell." },
      "group": { "zh": "观察", "en": "View" }
    }
  }
}
@endshaderlab */
