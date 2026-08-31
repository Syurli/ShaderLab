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
      "default": 18000,
      "min": 6000,
      "max": 200000,
      "step": 2000,
      "label": { "zh": "粒子数量", "en": "Particle Count" },
      "description": { "zh": "球面粒子总数。默认采用当前调试值 18000；提高会直接增加球面与日珥中的可用粒子。", "en": "Total shell particle count. The tuned default is 18000; raising it directly increases available shell and prominence particles." },
      "group": { "zh": "性能", "en": "Performance" }
    },
    "uEruptionRate": {
      "type": "float",
      "default": 4.5,
      "min": 0.25,
      "max": 4.5,
      "step": 0.05,
      "label": { "zh": "喷射频率", "en": "Eruption Rate" },
      "description": { "zh": "提高后更频繁地产生新喷发。历史事件会连续保留并衰减。", "en": "Creates new eruptions more frequently while historical events remain alive and fade continuously." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uEruptionChance": {
      "type": "float",
      "default": 1.0,
      "min": 0.2,
      "max": 1.0,
      "step": 0.01,
      "label": { "zh": "喷发概率", "en": "Eruption Chance" },
      "description": { "zh": "每个事件槽发生喷发的概率。", "en": "Probability that an event slot produces an eruption." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uInfluenceRadius": {
      "type": "float",
      "default": 0.9,
      "min": 0.12,
      "max": 0.9,
      "step": 0.01,
      "label": { "zh": "局部波及范围", "en": "Local Influence Radius" },
      "description": { "zh": "喷发源附近先被扰动的球面范围。", "en": "Initial shell area disturbed around an eruption source." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uEjectionDensity": {
      "type": "float",
      "default": 4.0,
      "min": 0.5,
      "max": 4.0,
      "step": 0.05,
      "label": { "zh": "喷射粒子密度", "en": "Ejection Density" },
      "description": { "zh": "控制发射源区域中有多少现有球面粒子真正被掀起。高值会让源区更明显地被抽空。", "en": "Controls how many existing shell particles in the source region are actually lifted. High values make the source visibly evacuate." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uSourceExcavation": {
      "type": "float",
      "default": 1.45,
      "min": 0.8,
      "max": 2.4,
      "step": 0.05,
      "label": { "zh": "源区掀开范围", "en": "Source Excavation" },
      "description": { "zh": "相对于日珥条带尺寸，决定真正从球面被掀起并留下空洞的源区大小。上升后这些粒子会自动向窄束收拢。", "en": "Size of the shell patch physically peeled away relative to the ribbon. Lifted particles are funnelled into a narrower arc as they rise." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uRibbonLength": {
      "type": "float",
      "default": 0.36,
      "min": 0.045,
      "max": 0.36,
      "step": 0.005,
      "label": { "zh": "喷射条长度", "en": "Ribbon Source Length" },
      "description": { "zh": "球面上喷发源沿主方向的长度。", "en": "Length of the eruption source along its main direction." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uRibbonWidth": {
      "type": "float",
      "default": 0.07,
      "min": 0.006,
      "max": 0.07,
      "step": 0.001,
      "label": { "zh": "喷射条宽度", "en": "Ribbon Width" },
      "description": { "zh": "喷发源基础宽度。掀起后会被压缩成更窄的三维束。", "en": "Base source width. The lifted patch is compressed into a narrower 3D filament during ascent." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uArcHeight": {
      "type": "float",
      "default": 1.0,
      "min": 0.12,
      "max": 1.3,
      "step": 0.01,
      "label": { "zh": "日珥高度", "en": "Arc Height" },
      "description": { "zh": "日珥离开球面的最大高度。", "en": "Maximum radial height of the prominence above the shell." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uArcLength": {
      "type": "float",
      "default": 0.95,
      "min": 0.05,
      "max": 0.95,
      "step": 0.01,
      "label": { "zh": "弧向展开", "en": "Arc Span" },
      "description": { "zh": "沿球面切线方向的弧形展开距离。", "en": "Tangential span of the prominence arc." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uShapeRandomness": {
      "type": "float",
      "default": 1.0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "label": { "zh": "形状随机度", "en": "Shape Randomness" },
      "description": { "zh": "控制源区毛边、弯曲、时差与不同事件之间的形态差异。", "en": "Controls ragged source edges, curvature, launch staggering, and event-to-event variation." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uShellCoverage": {
      "type": "float",
      "default": 0.62,
      "min": 0.25,
      "max": 0.95,
      "step": 0.01,
      "label": { "zh": "球面覆盖率", "en": "Shell Coverage" },
      "description": { "zh": "控制大陆式粒子区域占整个球面的比例。降低会产生更多、更明显的镂空区域。", "en": "Controls how much of the sphere is occupied by continent-like particle regions. Lower values create larger visible holes." },
      "group": { "zh": "球面形态", "en": "Shell Pattern" }
    },
    "uShellPatternScale": {
      "type": "float",
      "default": 1.0,
      "min": 0.45,
      "max": 2.5,
      "step": 0.05,
      "label": { "zh": "大陆纹理尺度", "en": "Continent Scale" },
      "description": { "zh": "控制球面不规则占据区域的块状尺度。低值形成大块大陆，高值形成更多碎片。", "en": "Scale of the irregular shell occupancy field. Lower values form larger continents; higher values create more fragmented islands." },
      "group": { "zh": "球面形态", "en": "Shell Pattern" }
    },
    "uFlightDuration": {
      "type": "float",
      "default": 2.45,
      "min": 0.55,
      "max": 3.5,
      "step": 0.05,
      "label": { "zh": "飞行时长", "en": "Flight Duration" },
      "description": { "zh": "粒子完成一次掀起、日珥运动并连续回到原球面位置的时间。", "en": "Time for particles to peel away, travel through the prominence, and continuously return to their original shell position." },
      "group": { "zh": "运动", "en": "Motion" }
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
    "uReturnDamping": {
      "type": "float",
      "default": 1.55,
      "min": 0.3,
      "max": 6.0,
      "step": 0.05,
      "label": { "zh": "回落阻尼", "en": "Return Damping" },
      "description": { "zh": "粒子落回球面后的阻尼。", "en": "Damping after landing back on the shell." },
      "group": { "zh": "回落", "en": "Return" }
    },
    "uReturnFrequency": {
      "type": "float",
      "default": 1.05,
      "min": 0.3,
      "max": 4.0,
      "step": 0.05,
      "label": { "zh": "回落振动频率", "en": "Return Oscillation" },
      "description": { "zh": "落回后的阻尼振动频率。", "en": "Frequency of the damped oscillation after landing." },
      "group": { "zh": "回落", "en": "Return" }
    },
    "uSurfaceWave": {
      "type": "float",
      "default": 0.075,
      "min": 0.0,
      "max": 0.4,
      "step": 0.005,
      "label": { "zh": "球面波浪强度", "en": "Surface Wave Strength" },
      "description": { "zh": "喷发、落地和传播波浪的总体位移幅度。", "en": "Overall displacement amplitude for eruption, landing, and travelling waves." },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveRange": {
      "type": "float",
      "default": 2.0,
      "min": 0.25,
      "max": 2.0,
      "step": 0.025,
      "label": { "zh": "球面波传播范围", "en": "Wave Range" },
      "description": { "zh": "控制水波从喷发点沿球面传播多远。2.0 接近球体对侧。", "en": "How far eruption waves travel across the sphere. 2.0 reaches approximately the opposite side." },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveSpeed": {
      "type": "float",
      "default": 0.5,
      "min": 0.25,
      "max": 4.0,
      "step": 0.05,
      "label": { "zh": "球面波速度", "en": "Wave Speed" },
      "description": { "zh": "波峰沿球面向外传播的速度。", "en": "Speed at which wave fronts propagate across the sphere." },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uWaveDamping": {
      "type": "float",
      "default": 0.3,
      "min": 0.05,
      "max": 2.5,
      "step": 0.025,
      "label": { "zh": "球面波衰减", "en": "Wave Damping" },
      "description": { "zh": "全局球面波随时间衰减的速度。", "en": "Temporal damping of global surface waves." },
      "group": { "zh": "球面波浪", "en": "Surface Waves" }
    },
    "uParticleSize": {
      "type": "float",
      "default": 2.2,
      "min": 0.4,
      "max": 2.2,
      "step": 0.05,
      "label": { "zh": "粒子尺寸", "en": "Particle Size" },
      "description": { "zh": "纯白球面沙砾与彩虹喷射粒子的视觉尺寸。", "en": "Visual size of the white shell grains and rainbow ejected particles." },
      "group": { "zh": "外观", "en": "Appearance" }
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
