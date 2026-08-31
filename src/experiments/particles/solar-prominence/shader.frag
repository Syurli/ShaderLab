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
      "default": 26000,
      "min": 4000,
      "max": 60000,
      "step": 1000,
      "label": { "zh": "粒子数量", "en": "Particle Count" },
      "description": { "zh": "球面粒子总数。手机建议 12000~30000。", "en": "Total shell particle count. 12000~30000 is recommended on phones." },
      "group": { "zh": "性能", "en": "Performance" }
    },
    "uEruptionRate": {
      "type": "float",
      "default": 1.55,
      "min": 0.25,
      "max": 3.5,
      "step": 0.05,
      "label": { "zh": "喷射频率", "en": "Eruption Rate" },
      "description": { "zh": "提高后各独立喷发通道更快地产生新事件，因此同时出现多个喷发点的概率也会上升。", "en": "Raises the event rate of each independent eruption lane, increasing the likelihood of concurrent prominences." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uEruptionChance": {
      "type": "float",
      "default": 0.86,
      "min": 0.2,
      "max": 1.0,
      "step": 0.01,
      "label": { "zh": "喷发概率", "en": "Eruption Chance" },
      "description": { "zh": "每个时间槽真正发生喷发的概率。降低可产生更明显的随机间隔。", "en": "Probability that a time slot actually produces an eruption. Lower values create more obvious random gaps." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uInfluenceRadius": {
      "type": "float",
      "default": 0.34,
      "min": 0.12,
      "max": 0.75,
      "step": 0.01,
      "label": { "zh": "波及范围", "en": "Influence Radius" },
      "description": { "zh": "喷发周围球面受到柔和波动的范围，不等于真正被抛出的细条宽度。", "en": "Radius of the soft surface disturbance around an eruption; independent from the narrow emitted ribbon." },
      "group": { "zh": "喷发", "en": "Eruption" }
    },
    "uRibbonLength": {
      "type": "float",
      "default": 0.145,
      "min": 0.045,
      "max": 0.32,
      "step": 0.005,
      "label": { "zh": "喷射条长度", "en": "Ribbon Source Length" },
      "description": { "zh": "球面上真正参与喷射的细长源区长度。", "en": "Length of the narrow source strip on the sphere that actually joins the eruption." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uRibbonWidth": {
      "type": "float",
      "default": 0.024,
      "min": 0.006,
      "max": 0.07,
      "step": 0.001,
      "label": { "zh": "喷射条宽度", "en": "Ribbon Width" },
      "description": { "zh": "决定喷发束厚度。数值越小，从侧面越接近一条线而不是一个面。", "en": "Controls filament thickness. Smaller values keep the prominence line-like instead of sheet-like from the side." },
      "group": { "zh": "形状", "en": "Shape" }
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
      "default": 0.44,
      "min": 0.05,
      "max": 0.95,
      "step": 0.01,
      "label": { "zh": "弧向展开", "en": "Arc Span" },
      "description": { "zh": "沿球面切线方向的弧形展开距离。提高会让日珥更明显地弯成拱形。", "en": "Tangential span of the arc. Higher values make the prominence bend into a more pronounced arch." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uShapeRandomness": {
      "type": "float",
      "default": 0.58,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "label": { "zh": "形状随机度", "en": "Shape Randomness" },
      "description": { "zh": "控制细条弯曲、发射时差和不同喷发事件之间的形态差异。", "en": "Controls centerline bending, launch staggering, and shape variation between eruption events." },
      "group": { "zh": "形状", "en": "Shape" }
    },
    "uFlightDuration": {
      "type": "float",
      "default": 1.55,
      "min": 0.55,
      "max": 3.5,
      "step": 0.05,
      "label": { "zh": "飞行时长", "en": "Flight Duration" },
      "description": { "zh": "粒子完成一次抛出并回到球面的时间。", "en": "Time for a particle to leave the shell and return to it." },
      "group": { "zh": "运动", "en": "Motion" }
    },
    "uReturnDamping": {
      "type": "float",
      "default": 2.2,
      "min": 0.35,
      "max": 6.0,
      "step": 0.05,
      "label": { "zh": "回落阻尼", "en": "Return Damping" },
      "description": { "zh": "粒子落回球面后的阻尼。越大越快恢复平静，越小尾部波动持续越久。", "en": "Damping after impact. Higher values settle faster; lower values preserve the residual ripple longer." },
      "group": { "zh": "回落", "en": "Return" }
    },
    "uReturnFrequency": {
      "type": "float",
      "default": 1.35,
      "min": 0.3,
      "max": 4.0,
      "step": 0.05,
      "label": { "zh": "回落振动频率", "en": "Return Oscillation" },
      "description": { "zh": "落回后的轻微阻尼振动频率。", "en": "Frequency of the small damped oscillation after particles land." },
      "group": { "zh": "回落", "en": "Return" }
    },
    "uSurfaceWave": {
      "type": "float",
      "default": 0.075,
      "min": 0.0,
      "max": 0.22,
      "step": 0.005,
      "label": { "zh": "球面余波", "en": "Surface Ripple" },
      "description": { "zh": "控制喷发外围以及粒子落地后的球面轻微波动幅度。", "en": "Amplitude of the broad disturbance and the residual ripple after impact." },
      "group": { "zh": "回落", "en": "Return" }
    },
    "uParticleSize": {
      "type": "float",
      "default": 1.0,
      "min": 0.45,
      "max": 2.2,
      "step": 0.05,
      "label": { "zh": "粒子尺寸", "en": "Particle Size" },
      "description": { "zh": "沙砾粒子的视觉尺寸。", "en": "Visual size of the sand-like particles." },
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
